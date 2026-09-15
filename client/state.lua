--- @author DemiAutomatic
--- @file client/state.lua
--- @description Client state: the job snapshot, lifts in range and bound ids.

OpxElevators = OpxElevators or {}

local Config = OPX_ELEVATORS_CONFIG
local Access = OpxElevators.Access

--- @author DemiAutomatic
--- @type {number}
--- @description How long a sighting is believed: two scans, read once.
local STALE_MS = (Access.FiniteNumber(Config.SCAN_MS) or 0) * 2

OpxElevators.State = {}
local State = OpxElevators.State

--- @author DemiAutomatic
--- @type {JobSnapshot|nil}
--- @description The character's job snapshot, or nil before the core answers.
OpxElevators.State.snapshot = nil

--- @author DemiAutomatic
--- @type {table<string, table>}
--- @description Elevator key to the id the server bound, filled by bound.
OpxElevators.State.bound = {}

--- @author DemiAutomatic
--- @type {table<string, table>}
--- @description Elevator key to what the last scan saw of its lift.
OpxElevators.State.seen = {}

--- @author DemiAutomatic
--- @method OpxElevators.State.Adopt
--- @description Keeps the job fields of an opx77_core PlayerData snapshot.
--- @param playerData {table|nil}
--- @param nowMs {integer}
function OpxElevators.State.Adopt(playerData, nowMs)
	if type(playerData) ~= 'table' then return end
	State.snapshot = {
		job = type(playerData.job) == 'table' and playerData.job or nil,
		jobs = type(playerData.jobs) == 'table' and playerData.jobs or nil,
		atMs = nowMs,
	}
end

--- @author DemiAutomatic
--- @method OpxElevators.State.Forget
--- @description Drops the snapshot once the core says there is no character.
function OpxElevators.State.Forget()
	State.snapshot = nil
end

--- @author DemiAutomatic
--- @method OpxElevators.State.Sighted
--- @description Records what one scan saw of a configured lift.
--- @param key {string}
--- @param lift {NativeLift}
--- @param nowMs {integer}
--- @param playerX {number|nil}
--- @param playerY {number|nil}
function OpxElevators.State.Sighted(key, lift, nowMs, playerX, playerY)
	local flat = nil
	if type(playerX) == 'number' and type(playerY) == 'number' then
		flat = Access.FlatDistanceSquared(key, playerX, playerY)
	end
	State.seen[key] = {
		reach = flat ~= nil and math.sqrt(flat) or nil,
		distance = lift.distance,
		id = lift.id,
		managed = lift.managed == true,
		atMs = nowMs,
	}
end

--- @author DemiAutomatic
--- @method current
--- @description Whether a sighting is recent enough to answer with.
--- @param lift {table}
--- @param nowMs {integer}
--- @returns {boolean}
local function current(lift, nowMs)
	return type(lift.atMs) == 'number' and nowMs - lift.atMs <= STALE_MS
end

--- @author DemiAutomatic
--- @method OpxElevators.State.Nearest
--- @description Answers the nearest sighted elevator within USE_RADIUS, or nil.
--- @param nowMs {integer}
--- @returns {string|nil}
function OpxElevators.State.Nearest(nowMs)
	local bestKey, bestDistance
	for key, lift in pairs(State.seen) do
		local reach = lift.reach or lift.distance
		if current(lift, nowMs) and type(reach) == 'number' and
			reach <= Access.USE_RADIUS and (bestDistance == nil or reach < bestDistance or
			(reach == bestDistance and key < bestKey)) then
			bestKey, bestDistance = key, reach
		end
	end
	return bestKey
end

--- @author DemiAutomatic
--- @method OpxElevators.State.Rows
--- @description Builds the floor rows for this player at one elevator.
--- @param key {string}
--- @param nowMs {integer}
--- @returns {FloorRow[]}
function OpxElevators.State.Rows(key, nowMs)
	return Access.List(key, State.snapshot, nowMs)
end

--- @author DemiAutomatic
--- @method OpxElevators.State.Report
--- @description Summarises what this client knows, for the state export.
--- @param nowMs {integer}
--- @returns {table}
function OpxElevators.State.Report(nowMs)
	local seen, bound = 0, 0
	for _, lift in pairs(State.seen) do
		if current(lift, nowMs) then seen = seen + 1 end
	end
	for _ in pairs(State.bound) do bound = bound + 1 end
	local snapshot = State.snapshot
	return {
		job = snapshot and snapshot.job and snapshot.job.name or nil,
		grade = snapshot and snapshot.job and snapshot.job.grade
			and snapshot.job.grade.level or nil,
		onDuty = snapshot and snapshot.job and snapshot.job.onDuty == true or false,
		fresh = snapshot ~= nil and (nowMs - snapshot.atMs) <= Access.JOB_MAX_AGE_MS,
		ageMs = snapshot and (nowMs - snapshot.atMs) or nil,
		seen = seen,
		bound = bound,
		nearest = State.Nearest(nowMs),
	}
end
