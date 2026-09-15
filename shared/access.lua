--- @author DemiAutomatic
--- @file shared/access.lua
--- @description The clock, config reads, coercions and floor decisions for both halves.

OpxElevators = OpxElevators or {}

--- @author DemiAutomatic
--- @type {integer}
--- @description Last clock reading in milliseconds, answered when no clock reads.
local lastMs = 0

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether the fallback to GetGameTimer has been logged.
local clockWarned = false

--- @author DemiAutomatic
--- @type {function|nil}
--- @description The server's GetGameTimer; nil on a client, which has none.
local gameTimer = rawget(_G, 'GetGameTimer')

--- @author DemiAutomatic
--- @method OpxElevators.NowMs
--- @description Reads the scheduler clock in milliseconds, with the server's GetGameTimer fallback.
--- @returns {integer}
function OpxElevators.NowMs()
	local read, seconds = pcall(Open77.time.monotonic)
	if read and type(seconds) == 'number' and seconds == seconds and
		seconds >= 0 and seconds < math.huge then
		lastMs = math.floor(seconds * 1000)
		return lastMs
	end
	if gameTimer == nil then return lastMs end
	local ticked, ms = pcall(gameTimer)
	if ticked and type(ms) == 'number' and ms == ms and ms >= 0 and ms < math.huge then
		if not clockWarned then
			clockWarned = true
			Open77.log.warn('Open77.time.monotonic unreadable; falling back to GetGameTimer')
		end
		lastMs = math.floor(ms)
	end
	return lastMs
end

OpxElevators.Access = {}
local Access = OpxElevators.Access

local Config = OPX_ELEVATORS_CONFIG

--- @author DemiAutomatic
--- @type {table<string, ElevatorSpec>}
--- @description The configured elevators, or an empty table when missing.
local ELEVATORS = type(Config.ELEVATORS) == 'table' and Config.ELEVATORS or {}
OpxElevators.Access.ELEVATORS = ELEVATORS

--- @author DemiAutomatic
--- @type {table<string, integer>}
--- @description Failure ranking, so the closest near-miss is reported.
local RANK = { off_duty = 3, grade_too_low = 2, job_required = 1 }

--- @author DemiAutomatic
--- @method finiteNumber
--- @description Coerces to a number, rejecting NaN and both infinities.
--- @param value {any}
--- @returns {number|nil}
local function finiteNumber(value)
	value = tonumber(value)
	if value == nil or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end
OpxElevators.Access.FiniteNumber = finiteNumber

--- @author DemiAutomatic
--- @type {integer}
--- @description Box every accepted coordinate fits in, and the %d ceiling.
local BOUND = 1000000

--- @author DemiAutomatic
--- @method coordinate
--- @description Coerces a world coordinate: finite and inside BOUND.
--- @param value {any}
--- @returns {number|nil}
local function coordinate(value)
	local parsed = finiteNumber(value)
	if parsed == nil or parsed > BOUND or parsed < -BOUND then return nil end
	return parsed
end
OpxElevators.Access.Coordinate = coordinate

--- @author DemiAutomatic
--- @method integer
--- @description Coerces a whole number inside BOUND.
--- @param value {any}
--- @returns {integer|nil}
local function integer(value)
	local parsed = coordinate(value)
	if parsed == nil or parsed % 1 ~= 0 then return nil end
	return math.floor(parsed)
end
OpxElevators.Access.Integer = integer

--- @author DemiAutomatic
--- @type {table<string, string>}
--- @description Elevator key to its declared ENTITY, lower-cased once at load.
local ENTITY_HASHES = {}

--- @author DemiAutomatic
--- @type {table<string, table>}
--- @description Elevator key to its validated x and y, built once at load.
local POSITIONS = {}

for key, elevator in pairs(ELEVATORS) do
	if type(elevator) == 'table' then
		if type(elevator.ENTITY) == 'string' then ENTITY_HASHES[key] = elevator.ENTITY:lower() end
		local x, y = coordinate(elevator.X), coordinate(elevator.Y)
		if x ~= nil and y ~= nil then POSITIONS[key] = { x = x, y = y } end
	end
end

--- @author DemiAutomatic
--- @type {number}
--- @description MATCH_RADIUS read once; an invalid value reads as zero.
local MATCH_RADIUS = finiteNumber(Config.MATCH_RADIUS) or 0

--- @author DemiAutomatic
--- @type {number}
--- @description USE_RADIUS read once; an invalid value reads as zero.
local USE_RADIUS = finiteNumber(Config.USE_RADIUS) or 0

--- @author DemiAutomatic
--- @type {number}
--- @description SCAN_RADIUS read once; an invalid value reads as zero.
local SCAN_RADIUS = finiteNumber(Config.SCAN_RADIUS) or 0
OpxElevators.Access.MATCH_RADIUS_SQ = MATCH_RADIUS * MATCH_RADIUS
OpxElevators.Access.USE_RADIUS = USE_RADIUS
OpxElevators.Access.USE_RADIUS_SQ = USE_RADIUS * USE_RADIUS
OpxElevators.Access.SCAN_RADIUS_SQ = SCAN_RADIUS * SCAN_RADIUS

--- @author DemiAutomatic
--- @type {number}
--- @description JOB_MAX_AGE_MS read once; an invalid value reads as zero.
local JOB_MAX_AGE_MS = finiteNumber(Config.JOB_MAX_AGE_MS) or 0
OpxElevators.Access.JOB_MAX_AGE_MS = JOB_MAX_AGE_MS

--- @author DemiAutomatic
--- @type {integer}
--- @description SCAN_MS read once in whole milliseconds; an invalid value reads as zero.
OpxElevators.Access.SCAN_MS = math.floor(finiteNumber(Config.SCAN_MS) or 0)

--- @author DemiAutomatic
--- @method OpxElevators.Access.FlatDistanceSquared
--- @description Squared horizontal distance to an elevator's declared position.
--- @param key {string}
--- @param x {number}
--- @param y {number}
--- @returns {number|nil}
function OpxElevators.Access.FlatDistanceSquared(key, x, y)
	local at = POSITIONS[key]
	if at == nil then return nil end
	local dx, dy = x - at.x, y - at.y
	return dx * dx + dy * dy
end

--- @author DemiAutomatic
--- @method OpxElevators.Access.Elevator
--- @description Answers one configured elevator by key, or nil.
--- @param key {any}
--- @returns {ElevatorSpec|nil}
function OpxElevators.Access.Elevator(key)
	if type(key) ~= 'string' then return nil end
	local elevator = ELEVATORS[key]
	if type(elevator) ~= 'table' then return nil end
	return elevator
end

--- @author DemiAutomatic
--- @method OpxElevators.Access.Floor
--- @description Answers one configured floor by its native index, or nil.
--- @param key {string}
--- @param index {integer}
--- @returns {FloorSpec|nil}
function OpxElevators.Access.Floor(key, index)
	local elevator = Access.Elevator(key)
	index = finiteNumber(index)
	if elevator == nil or index == nil then return nil end
	local floors = elevator.FLOORS
	if type(floors) ~= 'table' then return nil end
	for position = 1, #floors do
		local floor = floors[position]
		if type(floor) == 'table' and floor.INDEX == index then return floor end
	end
	return nil
end

--- @author DemiAutomatic
--- @method OpxElevators.Access.Locate
--- @description Matches a native lift position to a configured elevator.
--- @param x {any}
--- @param y {any}
--- @param z {any}
--- @param entity {string|nil}
--- @returns {string|nil, ElevatorSpec|nil}
function OpxElevators.Access.Locate(x, y, z, entity)
	x, y = coordinate(x), coordinate(y)
	if x == nil or y == nil or coordinate(z) == nil then return nil, nil end
	local hash = type(entity) == 'string' and entity:lower() or nil
	local radius = Access.MATCH_RADIUS_SQ
	local bestKey, bestDistance
	for key, at in pairs(POSITIONS) do
		local dx, dy = x - at.x, y - at.y
		local flat = dx * dx + dy * dy
		if flat <= radius then
			local declared = ENTITY_HASHES[key]
			if declared ~= nil and declared == hash then
				return key, ELEVATORS[key]
			end
			if declared == nil and (bestDistance == nil or flat < bestDistance or
				(flat == bestDistance and key < bestKey)) then
				bestKey, bestDistance = key, flat
			end
		end
	end
	if bestKey == nil then return nil, nil end
	return bestKey, ELEVATORS[bestKey]
end

--- @author DemiAutomatic
--- @method heldGrade
--- @description Answers the grade of a job this character holds, or nil.
--- @param snapshot {JobSnapshot}
--- @param name {string}
--- @returns {integer|nil}
local function heldGrade(snapshot, name)
	local job = snapshot.job
	if type(job) == 'table' and job.name == name then
		return type(job.grade) == 'table' and finiteNumber(job.grade.level) or 0
	end
	if Config.MEMBERSHIP ~= 'any' then return nil end
	if type(snapshot.jobs) ~= 'table' then return nil end
	return finiteNumber(snapshot.jobs[name])
end

--- @author DemiAutomatic
--- @method OpxElevators.Access.Evaluate
--- @description Decides whether a character snapshot may select a floor.
--- @param floor {FloorSpec}
--- @param snapshot {JobSnapshot|nil}
--- @param nowMs {integer}
--- @returns {boolean, string|nil}
function OpxElevators.Access.Evaluate(floor, snapshot, nowMs)
	local required = floor.JOBS
	if type(required) ~= 'table' or next(required) == nil then return true, nil end

	local atMs = type(snapshot) == 'table' and finiteNumber(snapshot.atMs) or nil
	if atMs == nil then return false, 'no_character' end
	if nowMs - atMs > JOB_MAX_AGE_MS then return false, 'job_stale' end
	if type(snapshot.job) ~= 'table' then return false, 'no_character' end

	local worst, worstRank = 'job_required', RANK.job_required
	for name, minimum in pairs(required) do
		local held = heldGrade(snapshot, name)
		if held ~= nil then
			if held < (finiteNumber(minimum) or 0) then
				if RANK.grade_too_low > worstRank then
					worst, worstRank = 'grade_too_low', RANK.grade_too_low
				end
			elseif floor.ON_DUTY == true and
				not (snapshot.job.name == name and snapshot.job.onDuty == true) then
				if RANK.off_duty > worstRank then worst, worstRank = 'off_duty', RANK.off_duty end
			else
				return true, nil
			end
		end
	end
	return false, worst
end

--- @author DemiAutomatic
--- @method OpxElevators.Access.List
--- @description Builds every floor row to draw for a character, in order.
--- @param key {string}
--- @param snapshot {JobSnapshot|nil}
--- @param nowMs {integer}
--- @returns {FloorRow[]}
function OpxElevators.Access.List(key, snapshot, nowMs)
	local elevator = Access.Elevator(key)
	if elevator == nil then return {} end
	local floors = elevator.FLOORS
	if type(floors) ~= 'table' then return {} end
	local hide = Config.DENIED_FLOORS == 'hidden'
	local rows = {}
	for position = 1, #floors do
		local floor = floors[position]
		if type(floor) == 'table' then
			local ok, failure = Access.Evaluate(floor, snapshot, nowMs)
			if ok or not hide then
				rows[#rows + 1] = {
					index = floor.INDEX,
					label = floor.LABEL,
					ok = ok,
					error = failure,
					reason = (not ok) and floor.REASON or nil,
				}
			end
		end
	end
	return rows
end

--- @author DemiAutomatic
--- @type {string[]}
--- @description The coordinate axes, in report order.
local AXES = { 'X', 'Y', 'Z' }

--- @author DemiAutomatic
--- @type {string[]}
--- @description Config keys a distance or timer uses, all above zero.
local NUMBERS = { 'MATCH_RADIUS', 'USE_RADIUS', 'SCAN_RADIUS', 'SCAN_MS', 'POLL_MS',
	'JOB_MAX_AGE_MS', 'TRAVEL_MS', 'REQUEST_WINDOW_MS', 'REQUESTS_PER_WINDOW' }

--- @author DemiAutomatic
--- @method OpxElevators.Access.Problems
--- @description Lists every configuration error visible without a world, sorted.
--- @returns {string[]}
function OpxElevators.Access.Problems()
	local lines = {}
	if type(Config.ELEVATORS) ~= 'table' then
		lines[#lines + 1] = 'ELEVATORS must be a table of elevator key -> definition'
	end
	for position = 1, #NUMBERS do
		local name = NUMBERS[position]
		local value = finiteNumber(Config[name])
		if value == nil or value <= 0 then
			lines[#lines + 1] = name .. ' must be a finite number above zero'
		end
	end

	for key, elevator in pairs(ELEVATORS) do
		if type(elevator) ~= 'table' then
			lines[#lines + 1] = tostring(key) .. ': every ELEVATORS entry must be a table'
		else
			for _, axis in ipairs(AXES) do
				if coordinate(elevator[axis]) == nil then
					lines[#lines + 1] = ('%s: %s must be a finite number inside %d'):format(key, axis,
						BOUND)
				end
			end

			local floors = elevator.FLOORS
			if type(floors) ~= 'table' or #floors == 0 then
				lines[#lines + 1] = key .. ': no FLOORS, so its panel would be empty'
			else
				local count = integer(elevator.FLOOR_COUNT)
				if elevator.FLOOR_COUNT ~= nil and (count == nil or count < 1) then
					lines[#lines + 1] = key .. ': FLOOR_COUNT must be a whole number, 1 or more'
					count = nil
				end

				local seen = {}
				for position = 1, #floors do
					local floor = floors[position]
					local where = ('%s floor #%d'):format(key, position)
					if type(floor) ~= 'table' then
						lines[#lines + 1] = where .. ': every FLOORS entry must be a table'
					else
						local index = integer(floor.INDEX)
						if index == nil or index < 0 then
							lines[#lines + 1] = where .. ': INDEX must be a whole number, 0 or more'
							index = nil
						elseif count ~= nil and index >= count then
							lines[#lines + 1] = ('%s: INDEX %d is outside FLOOR_COUNT %d'):format(where,
								index, count)
						elseif seen[index] then
							lines[#lines + 1] = ('%s: INDEX %d is declared twice'):format(where, index)
						end
						if index ~= nil then seen[index] = true end
						if type(floor.LABEL) ~= 'string' or floor.LABEL == '' then
							lines[#lines + 1] = where .. ': no LABEL'
						end
						if floor.JOBS ~= nil then
							if type(floor.JOBS) ~= 'table' then
								lines[#lines + 1] = where .. ': JOBS must be a table of name -> minimum grade'
							else
								for name, minimum in pairs(floor.JOBS) do
									if type(name) ~= 'string' or finiteNumber(minimum) == nil then
										lines[#lines + 1] = where ..
											': JOBS entries are job name -> minimum grade level, e.g. { ncpd = 0 }'
									end
								end
							end
						end
					end
				end
			end
		end
	end
	table.sort(lines)
	return lines
end
