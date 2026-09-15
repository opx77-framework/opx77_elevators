--- @author DemiAutomatic
--- @file server/main.lua
--- @description Server half: adoption, floor requests, the sweep and the diagnostic.

local Config = OPX_ELEVATORS_CONFIG
local Access = OpxElevators.Access
local Text = OpxElevators.Text

--- @author DemiAutomatic
--- @type {table<string, table>}
--- @description Elevator key to what this resource adopted; the host is authority.
local owned = {}

--- @author DemiAutomatic
--- @type {table<string, table<integer, boolean>>}
--- @description Elevator key to the players told its id.
local told = {}

--- @author DemiAutomatic
--- @type {table<integer, table>}
--- @description Per-player rate-limit windows: sightings, requests, log lines, suggestions.
local sightWindows, requestWindows, logWindows, suggestWindows = {}, {}, {}, {}

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description Elevator keys whose floor-count mismatch has been logged.
local warnedCount = {}

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether the malformed engine hash rejection has been logged.
local warnedEntity = false

--- @author DemiAutomatic
--- @type {integer}
--- @description Sightings one player may report per second.
local SIGHTS_PER_SECOND = 12

local nowMs = OpxElevators.NowMs
local coordinate, integer = Access.Coordinate, Access.Integer

--- @author DemiAutomatic
--- @type {number}
--- @description TRAVEL_MS read once; an invalid value reads as zero.
local TRAVEL_MS = Access.FiniteNumber(Config.TRAVEL_MS) or 0

--- @author DemiAutomatic
--- @type {number}
--- @description REQUEST_WINDOW_MS read once; an invalid value reads as zero.
local REQUEST_WINDOW_MS = Access.FiniteNumber(Config.REQUEST_WINDOW_MS) or 0

--- @author DemiAutomatic
--- @type {number}
--- @description REQUESTS_PER_WINDOW read once; an invalid value reads as zero.
local REQUESTS_PER_WINDOW = Access.FiniteNumber(Config.REQUESTS_PER_WINDOW) or 0

--- @author DemiAutomatic
--- @method sameEntity
--- @description Compares two opaque engine identifiers as lower-cased strings.
--- @param left {any}
--- @param right {any}
--- @returns {boolean}
local function sameEntity(left, right)
	return tostring(left or ''):lower() == tostring(right or ''):lower()
end

--- @author DemiAutomatic
--- @type {integer}
--- @description Longest wire value a log line carries, in characters.
local MAX_LOGGED = 64

--- @author DemiAutomatic
--- @method safe
--- @description Cleans and caps a wire value before it reaches a log line.
--- @param value {any}
--- @returns {string}
local function safe(value)
	return Text.Clean(value, MAX_LOGGED, '...') or ''
end

--- @author DemiAutomatic
--- @method within
--- @description Counts one event in a player's window, refusing past the limit.
--- @param windows {table<integer, table>}
--- @param player {integer}
--- @param limit {integer}
--- @param spanMs {integer}
--- @returns {boolean}
local function within(windows, player, limit, spanMs)
	local at = nowMs()
	local window = windows[player]
	if window == nil or at - window.started >= spanMs then
		window = { started = at, count = 0 }
		windows[player] = window
	end
	if window.count >= limit then return false end
	window.count = window.count + 1
	return true
end

--- @author DemiAutomatic
--- @method applyLock
--- @description Sets the host's locked flag on one lift, keeping the others.
--- @param id {integer}
--- @returns {boolean}
local function applyLock(id)
	local lift = Open77.elevators.get(id)
	if lift == nil then return false end
	local flags = (lift.flags or 0) | Open77.elevators.flags.locked
	if flags == lift.flags then return true end
	return Open77.elevators.setFlags(id, flags) == true
end

--- @author DemiAutomatic
--- @method moveCabin
--- @description Sends a cabin to a floor, answering whether the host accepted.
--- @param id {integer}
--- @param index {integer}
--- @returns {boolean}
local function moveCabin(id, index)
	local called, moved = pcall(Open77.elevators.goTo, id, index, { travelMs = TRAVEL_MS })
	return called and moved ~= nil and moved ~= false
end

--- @author DemiAutomatic
--- @method atElevator
--- @description Whether a host-reported lift stands at a configured elevator.
--- @param key {string}
--- @param lift {ServerElevator}
--- @returns {boolean}
local function atElevator(key, lift)
	local position = lift.position or lift
	local x, y = coordinate(position.x), coordinate(position.y)
	if x == nil or y == nil then return false end
	local flat = Access.FlatDistanceSquared(key, x, y)
	return flat ~= nil and flat <= Access.MATCH_RADIUS_SQ
end

--- @author DemiAutomatic
--- @method adopt
--- @description Takes ownership of a sighted native lift, or re-claims it.
--- @param key {string}
--- @param entity {string}
--- @param x {number}
--- @param y {number}
--- @param z {number}
--- @param bucket {integer}
--- @param floorCount {integer}
--- @param activeFloor {integer}
--- @returns {table}
local function adopt(key, entity, x, y, z, bucket, floorCount, activeFloor)
	local adopted = Open77.elevators.all(bucket)
	local adoptedCount = type(adopted) == 'table' and #adopted or 0
	for index = 1, adoptedCount do
		local existing = adopted[index]
		if sameEntity(existing.engineEntity, entity) then
			if not atElevator(key, existing) then
				return { ok = false, error = 'wrong_place' }
			end
			for otherKey, record in pairs(owned) do
				if otherKey ~= key and record.id == existing.id then
					return { ok = false, error = 'already_owned', reason = otherKey }
				end
			end
			owned[key] = { id = existing.id, floorCount = existing.floorCount, atMs = nowMs() }
			if not applyLock(existing.id) then
				Open77.log.warn(('%s re-claimed as %s but could not be locked'):format(key,
					tostring(existing.id)))
			end
			return { ok = true, id = existing.id, already = true }
		end
	end

	local ok, id, reason = pcall(Open77.elevators.adopt, {
		engineEntity = entity,
		position = { x = x, y = y, z = z },
		bucket = bucket,
		floorCount = floorCount,
		initialFloor = activeFloor,
	})
	if not ok then return { ok = false, error = 'adopt_raised', reason = tostring(id) } end
	if id == nil then return { ok = false, error = 'adopt_refused', reason = tostring(reason) } end

	owned[key] = { id = id, floorCount = floorCount, atMs = nowMs() }
	if not applyLock(id) then
		Open77.log.warn(('%s adopted as %s but could not be locked'):format(key, tostring(id)))
	end
	return { ok = true, id = id }
end

--- @author DemiAutomatic
--- @event opx77_elevators:sighted
--- @description Validates a client's lift sighting and adopts or binds the elevator.
--- @param entity {string}
--- @param x {number}
--- @param y {number}
--- @param z {number}
--- @param floorCount {integer}
--- @param activeFloor {integer}
RegisterNetEvent('opx77_elevators:sighted', function(entity, x, y, z, floorCount, activeFloor)
	local player = tonumber(source) or 0
	if player <= 0 then return end
	if not within(sightWindows, player, SIGHTS_PER_SECOND, 1000) then return end

	if type(entity) ~= 'string' or
		entity:match('^0[xX]%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$') == nil then
		if not warnedEntity then
			warnedEntity = true
			Open77.log.warn(('sighting rejected: first argument is not an engine hash (%s); the client and this handler disagree about the wire format'):format(safe(entity)))
		end
		return
	end
	x, y, z = coordinate(x), coordinate(y), coordinate(z)
	floorCount, activeFloor = integer(floorCount), integer(activeFloor)
	if x == nil or y == nil or z == nil or floorCount == nil or activeFloor == nil then return end
	if floorCount < 1 or floorCount > 1025 or activeFloor < 0 or activeFloor >= floorCount then
		return
	end

	local position = Open77.players.position(player)
	if position == nil then return end
	local px, py, pz = coordinate(position.x), coordinate(position.y), coordinate(position.z)
	if px == nil or py == nil or pz == nil then return end
	local dx, dy, dz = x - px, y - py, z - pz
	if dx * dx + dy * dy + dz * dz > Access.SCAN_RADIUS_SQ then return end

	local key, elevator = Access.Locate(x, y, z, entity)
	if key == nil then return end

	local bucket = integer(elevator.BUCKET) or 0
	if position.bucket ~= bucket then return end

	local declared = integer(elevator.FLOOR_COUNT)
	if declared ~= nil and declared >= 1 then
		if declared ~= floorCount and not warnedCount[key] then
			warnedCount[key] = true
			Open77.log.warn(('%s reported %d floors, config declares %d; using the config'):format(
				key, floorCount, declared))
		end
		floorCount = declared
		if activeFloor >= floorCount then activeFloor = 0 end
	end

	local record = owned[key]
	if record == nil then
		local result = adopt(key, entity, x, y, z, bucket, floorCount, activeFloor)
		if not result.ok then
			if within(logWindows, player, 1, 1000) then
				Open77.log.warn(('%s not adopted: %s (%s)'):format(key, result.error,
					tostring(result.reason)))
			end
			return
		end
		Open77.log.info(('%s adopted as elevator %s in bucket %s'):format(key, tostring(result.id),
			tostring(bucket)))
		record = owned[key]
	end
	told[key] = told[key] or {}
	told[key][player] = true
	TriggerClientEvent('opx77_elevators:bound', player, key, record.id, record.floorCount)
end)

--- @author DemiAutomatic
--- @method release
--- @description Drops an adoption and tells every player handed its id.
--- @param key {string}
local function release(key)
	owned[key] = nil
	local audience = told[key]
	if audience == nil then return end
	for player in pairs(audience) do
		TriggerClientEvent('opx77_elevators:released', player, key)
	end
	told[key] = nil
end

--- @author DemiAutomatic
--- @method request
--- @description Checks everything the server can prove, then moves the cabin.
--- @param player {integer}
--- @param key {any}
--- @param index {any}
--- @returns {table}
local function request(player, key, index)
	if not within(requestWindows, player, REQUESTS_PER_WINDOW, REQUEST_WINDOW_MS) then
		return { ok = false, error = 'rate_limited' }
	end

	local elevator = Access.Elevator(key)
	if elevator == nil then return { ok = false, error = 'no_such_elevator' } end
	index = integer(index)
	if Access.Floor(key, index) == nil then return { ok = false, error = 'no_such_floor' } end

	local record = owned[key]
	if record == nil then return { ok = false, error = 'not_adopted' } end
	local lift = Open77.elevators.get(record.id)
	if lift == nil then
		release(key)
		return { ok = false, error = 'not_adopted' }
	end
	local floorCount = integer(lift.floorCount)
	if floorCount == nil or index >= floorCount then
		return { ok = false, error = 'floor_out_of_range' }
	end

	local position = Open77.players.position(player)
	if position == nil then return { ok = false, error = 'no_position' } end
	if position.bucket ~= lift.bucket then return { ok = false, error = 'wrong_bucket' } end
	local px, py = coordinate(position.x), coordinate(position.y)
	if px == nil or py == nil then return { ok = false, error = 'no_position' } end
	local reach = Access.FlatDistanceSquared(key, px, py)
	if reach == nil or reach > Access.USE_RADIUS_SQ then
		return { ok = false, error = 'too_far' }
	end

	if not moveCabin(record.id, index) then return { ok = false, error = 'move_rejected' } end
	record.usedAtMs = nowMs()
	record.rider = player
	record.rideEndsAtMs = record.usedAtMs + TRAVEL_MS
	return { ok = true, id = record.id, floor = index }
end

--- @author DemiAutomatic
--- @event opx77_elevators:request
--- @description Runs a player's floor request and answers the verdict.
--- @param key {any}
--- @param index {any}
RegisterNetEvent('opx77_elevators:request', function(key, index)
	local player = tonumber(source) or 0
	if player <= 0 then return end
	local result = request(player, key, index)
	if result.error ~= 'rate_limited' then
		TriggerClientEvent('opx77_elevators:answer', player, safe(key), integer(index),
			result.ok, result.error)
	end
	if not result.ok and within(logWindows, player, 1, 1000) then
		Open77.log.info(('player %d refused %s floor %s: %s'):format(player, safe(key), safe(index),
			tostring(result.error)))
	end
end)

--- @author DemiAutomatic
--- @event onElevatorRemoved
--- @description Releases the adoption of a lift the host removed.
--- @param id {integer}
--- @param _ {any}
--- @param reason {any}
AddEventHandler('onElevatorRemoved', function(id, _, reason)
	for key, record in pairs(owned) do
		if record.id == tonumber(id) then
			release(key)
			Open77.log.info(('%s released: %s'):format(key, tostring(reason)))
			return
		end
	end
end)

--- @author DemiAutomatic
--- @method forget
--- @description Forgets a departing player and recalls a cabin left in motion.
--- @param playerId {any}
--- @param reason {any}
local function forget(playerId, reason)
	local player = tonumber(playerId) or 0
	if player <= 0 then return end
	sightWindows[player] = nil
	requestWindows[player] = nil
	logWindows[player] = nil
	suggestWindows[player] = nil
	for _, players in pairs(told) do players[player] = nil end

	local at = nowMs()
	for key, record in pairs(owned) do
		if record.rider == player then
			record.rider = nil
			if (record.rideEndsAtMs or 0) > at then
				record.rideEndsAtMs = nil
				local sent = moveCabin(record.id, 0)
				Open77.log.info(('%s: rider %d left mid-travel (%s); recalled to floor 0 (%s)')
					:format(key, player, tostring(reason), tostring(sent)))
			end
		end
	end
end

--- @author DemiAutomatic
--- @type {integer}
--- @description Age past which a never-used adoption is released.
local UNUSED_MS = 600000

--- @author DemiAutomatic
--- @type {integer}
--- @description Age past which the sweep collects a rate-limit window.
local WINDOW_GC_MS = 60000

CreateThread(function()
	while true do
		Wait(60000)
		local swept, failure = pcall(function()
			local at = nowMs()
			for key, record in pairs(owned) do
				if record.usedAtMs == nil and at - (record.atMs or at) > UNUSED_MS then
					release(key)
					Open77.log.warn(('%s released: adopted %d minutes ago and never used')
						:format(key, math.floor(UNUSED_MS / 60000)))
				end
			end
			for _, windows in ipairs({ sightWindows, requestWindows, logWindows, suggestWindows }) do
				for player, window in pairs(windows) do
					if at - (window.started or at) > WINDOW_GC_MS then windows[player] = nil end
				end
			end
		end)
		if not swept then Open77.log.error('the adoption sweep failed: ' .. tostring(failure)) end
	end
end)

--- @author DemiAutomatic
--- @event onPlayerDisconnected
--- @description Forgets an admitted player's windows, audiences and ride.
AddEventHandler('onPlayerDisconnected', forget)

if type(Config.COMMAND) == 'string' and Config.COMMAND ~= '' then
	--- @author DemiAutomatic
	--- @command OPX_ELEVATORS_CONFIG.COMMAND
	--- @description Prints every elevator's position, floors and adoption state.
	RegisterCommand(Config.COMMAND, function(commandSource, args, raw)
		local lines = {}
		local problems = Access.Problems()
		for index = 1, #problems do lines[index] = 'config: ' .. problems[index] end
		local filter = args and args[1]
		local report = {}
		for key, elevator in pairs(Access.ELEVATORS) do
			if (filter == nil or filter == key) and type(elevator) == 'table' then
				local record = owned[key]
				local lift = record and Open77.elevators.get(record.id) or nil
				report[#report + 1] = ('%s %s pos=%.2f,%.2f,%.2f floors=%d/%d id=%s %s'):format(
					key, tostring(elevator.LABEL), coordinate(elevator.X) or 0.0,
					coordinate(elevator.Y) or 0.0, coordinate(elevator.Z) or 0.0,
					type(elevator.FLOORS) == 'table' and #elevator.FLOORS or 0,
					integer(elevator.FLOOR_COUNT) or 0,
					record and tostring(record.id) or '-',
					lift and ('phase=%s floor=%s flags=%s'):format(tostring(lift.phase),
						tostring(lift.activeFloor), tostring(lift.flags)) or 'not adopted')
			end
		end
		table.sort(report)
		for index = 1, #report do lines[#lines + 1] = report[index] end
		lines[#lines + 1] = ('denied=%s membership=%s'):format(Config.DENIED_FLOORS,
			Config.MEMBERSHIP)
		local player = tonumber(commandSource) or 0
		for index = 1, #lines do
			local line = lines[index]
			print(line)
			if player > 0 then
				TriggerClientEvent('chat:addMessage', player, {
					type = 'info',
					author = locale('elevators.title'),
					text = line,
					color = { 120, 220, 232 },
				})
			end
		end
	end, true)

	--- @author DemiAutomatic
	--- @type {integer}
	--- @description Shortest gap between two suggestions to one player.
	local SUGGEST_EVERY_MS = 10000

	--- @author DemiAutomatic
	--- @method permitted
	--- @description Whether the host's ACL grants this player the command.
	--- @param player {integer}
	--- @returns {boolean}
	local function permitted(player)
		local acl = Open77.acl
		if type(acl) ~= 'table' or type(acl.isAllowed) ~= 'function' then return false end
		local read, allowed = pcall(acl.isAllowed, player, 'command.' .. Config.COMMAND)
		return read and allowed == true
	end

	--- @author DemiAutomatic
	--- @event chat:ready
	--- @description Suggests the diagnostic command to a player the ACL grants it.
	RegisterNetEvent('chat:ready', function()
		local player = tonumber(source) or 0
		if player <= 0 or not within(suggestWindows, player, 1, SUGGEST_EVERY_MS) then return end
		if not permitted(player) then return end
		local keys = {}
		for key in pairs(Access.ELEVATORS) do keys[#keys + 1] = tostring(key) end
		table.sort(keys)
		TriggerClientEvent('chat:addSuggestion', player, '/' .. Config.COMMAND,
			locale('elevators.help.where'), {
				{ name = 'key', optional = true, help = locale('elevators.help.whereKey',
					{ keys = #keys > 0 and table.concat(keys, ', ') or '-' }) },
			})
	end)
end

if type(Open77.elevators) ~= 'table' then
	Open77.log.error('native elevator API unavailable; no elevator will be adopted')
else
	local problems = Access.Problems()
	for index = 1, #problems do
		Open77.log.warn('config: ' .. problems[index])
	end

	CreateThread(function()
		local read, state = pcall(GetResourceState, 'open77_elevators')
		local official = read and tostring(state or ''):lower() or ''
		if official ~= 'running' and official ~= 'starting' then return end
		Open77.log.warn('open77_elevators is running; a lift adopted by one is refused to the other')
		Open77.log.warn('  (the platform rejects a different owner), so whichever starts first owns')
		Open77.log.warn('  the cabin. Drop one from resources.load in server.jsonc.')
	end)

	Open77.log.info('ready')
end
