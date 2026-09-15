---@meta

--- The scheduler clock in milliseconds (`Open77.time.monotonic` answers seconds). A non-finite
--- reading is dropped. On the server an unreadable one falls back to `GetGameTimer`, with one
--- warning; a client has no `GetGameTimer`, so there, and when neither answers, the last reading
--- is kept.
---@return integer
function OpxElevators.NowMs() end

OpxElevators.Access = {}

--- The configured elevators, or an empty table when `ELEVATORS` is not a table.
---@type table<ElevatorKey, ElevatorSpec>
OpxElevators.Access.ELEVATORS = {}

--- `MATCH_RADIUS`, squared once at load; an invalid value reads as zero.
---@type number
OpxElevators.Access.MATCH_RADIUS_SQ = 0

--- `USE_RADIUS`, read once at load; an invalid value reads as zero.
---@type number
OpxElevators.Access.USE_RADIUS = 0

--- `USE_RADIUS`, squared once at load.
---@type number
OpxElevators.Access.USE_RADIUS_SQ = 0

--- `SCAN_RADIUS`, squared once at load; an invalid value reads as zero.
---@type number
OpxElevators.Access.SCAN_RADIUS_SQ = 0

--- `JOB_MAX_AGE_MS`, read once at load; an invalid value reads as zero.
---@type number
OpxElevators.Access.JOB_MAX_AGE_MS = 0

--- `SCAN_MS`, read once at load and floored to whole milliseconds; an invalid value reads as
--- zero, and the client then refuses to start its scan loop.
---@type integer
OpxElevators.Access.SCAN_MS = 0

--- Coerces to a number, rejecting NaN and both infinities. Carries no range of its own.
---@type fun(value: any): number|nil
OpxElevators.Access.FiniteNumber = nil

--- A world coordinate: finite, and inside ±1,000,000, which is also the ceiling on any `%d`.
---@type fun(value: any): number|nil
OpxElevators.Access.Coordinate = nil

--- A whole number inside the coordinate box, safe to hand to `%d`.
---@type fun(value: any): integer|nil
OpxElevators.Access.Integer = nil

--- Horizontal distance, squared, from (x, y) to the elevator's declared position, or nil when
--- the elevator has no usable X and Y. Z never enters it.
---@param key string
---@param x number already a coordinate
---@param y number already a coordinate
---@return number|nil
function OpxElevators.Access.FlatDistanceSquared(key, x, y) end

--- One configured elevator by key, or nil for a non-string key or a non-table entry.
---@param key any
---@return ElevatorSpec|nil
function OpxElevators.Access.Elevator(key) end

--- One configured floor by its native index, never its position in `FLOORS`.
---@param key string
---@param index integer
---@return FloorSpec|nil
function OpxElevators.Access.Floor(key, index) end

--- Which configured elevator a native lift at (x, y, z) is, matched across the ground within
--- `MATCH_RADIUS`. A declared `ENTITY` pins which one; the key breaks a distance tie.
---@param x any
---@param y any
---@param z any validated, never compared
---@param entity string|nil
---@return ElevatorKey|nil key
---@return ElevatorSpec|nil elevator
function OpxElevators.Access.Locate(x, y, z, entity) end

--- May this character select this floor? Public floors are always open; a gated floor needs a
--- fresh snapshot and one of its jobs at grade (and on duty when `ON_DUTY`). A refusal names
--- the closest near-miss: `off_duty` over `grade_too_low` over `job_required`.
---@param floor FloorSpec a configured floor table
---@param snapshot JobSnapshot|nil
---@param nowMs integer
---@return boolean ok
---@return ElevatorError|nil error
function OpxElevators.Access.Evaluate(floor, snapshot, nowMs) end

--- Every floor to draw for this character, in configured order; refused rows are left out
--- when `DENIED_FLOORS` is "hidden".
---@param key string
---@param snapshot JobSnapshot|nil
---@param nowMs integer
---@return FloorRow[]
function OpxElevators.Access.List(key, snapshot, nowMs) end

--- Everything wrong with the configuration that can be seen without a world, sorted.
---@return string[]
function OpxElevators.Access.Problems() end
