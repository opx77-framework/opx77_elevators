--- @author DemiAutomatic
--- @file client/main.lua
--- @description Client half: the opx77_core link, the scan and floor requests.

OpxElevators = OpxElevators or {}

local Config = OPX_ELEVATORS_CONFIG
local Access = OpxElevators.Access
local State = OpxElevators.State

OpxElevators.Runtime = {}
local Runtime = OpxElevators.Runtime

--- @author DemiAutomatic
--- @type {string}
--- @description This resource's name, for the lifecycle events.
local RESOURCE = GetCurrentResourceName()

--- @author DemiAutomatic
--- @type {string}
--- @description The resource the character is read from.
local CORE = 'opx77_core'

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two reports of one unadopted lift.
local SIGHT_RETRY_MS = 5000

--- @author DemiAutomatic
--- @type {number}
--- @description POLL_MS read once; an invalid value reads as zero.
local POLL_MS = Access.FiniteNumber(Config.POLL_MS) or 0

--- @author DemiAutomatic
--- @type {table<string, integer>}
--- @description Elevator key to when its lift was last reported.
local sighted = {}

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether the scan loop should keep running.
local running = false

local nowMs = OpxElevators.NowMs

--- @author DemiAutomatic
--- @method publish
--- @description Raises the configured local event with a decision.
--- @param payload {table}
local function publish(payload)
	TriggerEvent(Config.EVENT, payload)
end

--- @author DemiAutomatic
--- @method OpxElevators.Runtime.Call
--- @description Calls another resource's client export, checked at three levels.
--- @param resource {string}
--- @param name {string}
--- @returns {table|nil, string|nil, boolean}
function OpxElevators.Runtime.Call(resource, name, ...)
	local reachable, state = pcall(GetResourceState, resource)
	if not reachable or state ~= 'running' then return nil, 'not_running', false end
	if Open77.exports == nil then return nil, 'not_dispatched', false end
	local dispatched, promise, reason = pcall(Open77.exports.call, resource, name, ...)
	if not dispatched then return nil, tostring(promise), false end
	if not promise then return nil, tostring(reason or 'not_dispatched'), false end
	local result, callError = promise:await()
	if callError then return nil, tostring(callError), false end
	if type(result) ~= 'table' then return nil, 'malformed_answer', true end
	if result.ok == false then return nil, tostring(result.error or 'refused'), true end
	return result, nil, true
end

--- @author DemiAutomatic
--- @method pull
--- @description Re-reads the character from opx77_core, on a coroutine.
--- @returns {boolean, string|nil}
local function pull()
	local result, reason, answered = Runtime.Call(CORE, 'GetPlayerData')
	if result == nil then
		if answered then State.Forget() end
		return false, reason
	end
	State.Adopt(result.data, nowMs())
	return true
end

--- @author DemiAutomatic
--- @event opx77:client:onPlayerLoaded
--- @description Adopts the loaded character's job snapshot.
--- @param playerData {table}
AddEventHandler('opx77:client:onPlayerLoaded', function(playerData)
	State.Adopt(playerData, nowMs())
end)

--- @author DemiAutomatic
--- @event opx77:client:playerDataChanged
--- @description Adopts the changed character's job snapshot at once.
--- @param playerData {table}
AddEventHandler('opx77:client:playerDataChanged', function(playerData)
	State.Adopt(playerData, nowMs())
end)

--- @author DemiAutomatic
--- @event opx77:client:onPlayerUnloaded
--- @description Drops the snapshot when the character unloads.
AddEventHandler('opx77:client:onPlayerUnloaded', function()
	State.Forget()
end)

--- @author DemiAutomatic
--- @method playerXY
--- @description Reads the player's own horizontal position, or nil.
--- @returns {number|nil, number|nil}
local function playerXY()
	local character = Open77.character
	if type(character) ~= 'table' or type(character.position) ~= 'function' then
		return nil, nil
	end
	local read, x, y = pcall(character.position)
	if not read or type(x) ~= 'number' or type(y) ~= 'number' or x ~= x or y ~= y then
		return nil, nil
	end
	return x, y
end

--- @author DemiAutomatic
--- @method scan
--- @description Records configured lifts in range and reports unadopted ones.
local function scan()
	local at = nowMs()
	local nearby = Open77.elevators.nearby(Config.SCAN_RADIUS)
	if type(nearby) ~= 'table' then return end
	local playerX, playerY = playerXY()
	for index = 1, #nearby do
		local lift = nearby[index]
		local position = lift.position or {}
		local key = Access.Locate(position.x, position.y, position.z, lift.engineEntity)
		if key ~= nil then
			State.Sighted(key, lift, at, playerX, playerY)
			local ready = lift.floorCount ~= nil and lift.floorCount > 0 and
				lift.activeFloor ~= nil and lift.activeFloor >= 0
			local due = sighted[key] == nil or at - sighted[key] >= SIGHT_RETRY_MS
			if ready and not lift.managed and State.bound[key] == nil and due then
				sighted[key] = at
				local accepted, reason = TriggerServerEvent('opx77_elevators:sighted',
					lift.engineEntity, position.x, position.y, position.z,
					lift.floorCount, lift.activeFloor)
				if not accepted then
					Open77.log.warn(('sighting of %s was not sent: %s'):format(key, tostring(reason)))
				end
			end
		end
	end
end

--- @author DemiAutomatic
--- @event opx77_elevators:bound
--- @description Stores the id the server adopted an elevator under.
--- @param key {string}
--- @param id {integer}
--- @param floorCount {integer}
RegisterNetEvent('opx77_elevators:bound', function(key, id, floorCount)
	if type(key) ~= 'string' or Access.Elevator(key) == nil then return end
	State.bound[key] = { id = id, floorCount = floorCount, atMs = nowMs() }
	sighted[key] = nil
end)

--- @author DemiAutomatic
--- @event opx77_elevators:answer
--- @description Publishes the server's verdict on a floor request.
--- @param key {string}
--- @param index {integer|nil}
--- @param ok {boolean}
--- @param failure {string|nil}
RegisterNetEvent('opx77_elevators:answer', function(key, index, ok, failure)
	publish({
		elevator = key,
		floor = index,
		ok = ok == true,
		error = ok ~= true and tostring(failure or 'refused') or nil,
		source = 'server',
	})
	if ok ~= true then
		Open77.log.info(('%s floor %s refused: %s'):format(
			tostring(key), tostring(index), tostring(failure)))
	end
end)

--- @author DemiAutomatic
--- @event opx77_elevators:released
--- @description Drops a binding so the next scan re-reports the lift.
--- @param key {string}
RegisterNetEvent('opx77_elevators:released', function(key)
	if type(key) ~= 'string' then return end
	State.bound[key] = nil
	sighted[key] = nil
end)

--- @author DemiAutomatic
--- @method OpxElevators.Runtime.ElevatorId
--- @description Answers the Open77 id of a configured elevator, or nil.
--- @param key {string}
--- @returns {integer|nil}
function OpxElevators.Runtime.ElevatorId(key)
	local bound = State.bound[key]
	if bound ~= nil then return bound.id end
	local seen = State.seen[key]
	if seen ~= nil and seen.managed then return seen.id end
	return nil
end

--- @author DemiAutomatic
--- @method OpxElevators.Runtime.Nearest
--- @description Answers the elevator the player is standing at, or nil.
--- @returns {string|nil}
function OpxElevators.Runtime.Nearest()
	return State.Nearest(nowMs())
end

--- @author DemiAutomatic
--- @method OpxElevators.Runtime.Floors
--- @description Answers the floor list for this player at an elevator.
--- @param key {string|nil}
--- @returns {FloorListing}
function OpxElevators.Runtime.Floors(key)
	key = key or Runtime.Nearest()
	if key == nil then return { ok = false, error = 'no_elevator_nearby' } end
	if Access.Elevator(key) == nil then return { ok = false, error = 'no_such_elevator' } end
	return { ok = true, elevator = key, floors = State.Rows(key, nowMs()) }
end

--- @author DemiAutomatic
--- @method OpxElevators.Runtime.Use
--- @description Checks a floor locally, then sends the request to the server.
--- @param key {string|nil}
--- @param index {integer}
--- @param origin {string|nil} panel, or the invoking resource's name.
--- @returns {FloorDecision}
function OpxElevators.Runtime.Use(key, index, origin)
	key = key or Runtime.Nearest()
	local result = Runtime.Check(key, index)
	result.source = origin or 'export'
	if not result.ok then
		publish(result)
		return result
	end

	local id = Runtime.ElevatorId(key)
	if id == nil then
		result = { ok = false, error = 'not_adopted', elevator = key, floor = index,
			source = result.source }
		publish(result)
		return result
	end

	local accepted, reason = TriggerServerEvent('opx77_elevators:request', key, index)
	if not accepted then
		result = { ok = false, error = tostring(reason or 'not_sent'), elevator = key,
			floor = index, source = result.source }
		publish(result)
		return result
	end
	result.queued = true
	return result
end

--- @author DemiAutomatic
--- @method OpxElevators.Runtime.Check
--- @description Decides locally whether this player may take a floor.
--- @param key {string|nil}
--- @param index {integer}
--- @returns {FloorDecision}
function OpxElevators.Runtime.Check(key, index)
	key = key or Runtime.Nearest()
	if key == nil then return { ok = false, error = 'no_elevator_nearby' } end
	local elevator = Access.Elevator(key)
	if elevator == nil then return { ok = false, error = 'no_such_elevator', elevator = key } end
	local floor = Access.Floor(key, index)
	if floor == nil then
		return { ok = false, error = 'no_such_floor', elevator = key, floor = index }
	end
	local ok, failure = Access.Evaluate(floor, State.snapshot, nowMs())
	return {
		ok = ok,
		error = failure,
		elevator = key,
		floor = index,
		label = floor.LABEL,
		reason = (not ok) and floor.REASON or nil,
	}
end

--- @author DemiAutomatic
--- @method OpxElevators.Runtime.Report
--- @description Answers the client state summary at the current time.
--- @returns {table}
function OpxElevators.Runtime.Report()
	return State.Report(nowMs())
end

--- @author DemiAutomatic
--- @event onClientResourceStart
--- @description Starts the scan and core polling loop for this resource.
--- @param name {string}
AddEventHandler('onClientResourceStart', function(name)
	if name ~= RESOURCE then return end

	if type(Open77.elevators) ~= 'table' then
		Open77.log.error('native elevator API unavailable; nothing will be scanned')
		return
	end

	running = true
	CreateThread(function()
		local nextPullAtMs = 0
		while running do
			local ticked, failure = pcall(function()
				local at = nowMs()
				if at >= nextPullAtMs then
					nextPullAtMs = at + POLL_MS
					CreateThread(pull)
				end
				scan()
			end)
			if not ticked then
				Open77.log.warn('the elevator scan failed: ' .. tostring(failure))
			end
			Wait(Config.SCAN_MS)
		end
	end)
end)

--- @author DemiAutomatic
--- @event onClientResourceStop
--- @description Stops the loop and forgets bindings and sightings.
--- @param name {string}
AddEventHandler('onClientResourceStop', function(name)
	if name ~= RESOURCE then return end
	running = false
	State.bound, State.seen, sighted = {}, {}, {}
end)
