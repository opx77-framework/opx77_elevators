--- The gate: reads config.lua and decides which floors a character may select.

OpxElevators = OpxElevators or {}

local Access = {}
OpxElevators.access = Access

local Config = OPX_ELEVATORS_CONFIG

--- The configured elevators, or an empty table: every read below is reachable from an
--- export, and `problems()` reports a missing ELEVATORS rather than raising on it.
local ELEVATORS = type(Config.ELEVATORS) == "table" and Config.ELEVATORS or {}
Access.ELEVATORS = ELEVATORS

--- Failure ranking, so the closest near-miss is reported rather than the first `pairs` found.
local RANK = { off_duty = 3, grade_too_low = 2, job_required = 1 }

--- Coerce to a number, rejecting NaN and both infinities. Carries no range of its own.
---@param value any
---@return number|nil
local function finiteNumber(value)
  value = tonumber(value)
  -- `value ~= value` is the NaN check, not a typo: NaN is the one value unequal to itself
  if value == nil or value ~= value or value == math.huge or value == -math.huge then
    return nil
  end
  return value
end
Access.finiteNumber = finiteNumber

--- The box every accepted coordinate must fit inside, and the ceiling on any `%d` argument.
local BOUND = 1000000
Access.BOUND = BOUND

--- A world coordinate: finite, and inside BOUND.
---@param value any
---@return number|nil
local function coordinate(value)
  local parsed = finiteNumber(value)
  if parsed == nil or parsed > BOUND or parsed < -BOUND then return nil end
  return parsed
end
Access.coordinate = coordinate

--- A whole number inside BOUND; `%d` raises on a float with no integer representation.
---@param value any
---@return integer|nil
local function integer(value)
  local parsed = coordinate(value)
  if parsed == nil or parsed % 1 ~= 0 then return nil end
  return math.floor(parsed)
end
Access.integer = integer

--- key -> its declared ENTITY, lower-cased once at load.
local ENTITY_HASHES = {}

--- key -> its validated `{ x, y }`. Built once, because `locate` walks every elevator for
--- every lift of every scan: a coordinate coerced there is coerced on all of them, forever.
local POSITIONS = {}

for key, elevator in pairs(ELEVATORS) do
  if type(elevator) == "table" then
    if type(elevator.ENTITY) == "string" then ENTITY_HASHES[key] = elevator.ENTITY:lower() end
    local x, y = coordinate(elevator.X), coordinate(elevator.Y)
    if x ~= nil and y ~= nil then POSITIONS[key] = { x = x, y = y } end
  end
end

--- The three radii, squared once at load. A value `problems()` refuses reads as zero here,
--- so a bad one is a warning at boot rather than a raise inside a net event.
local MATCH_RADIUS = finiteNumber(Config.MATCH_RADIUS) or 0
local USE_RADIUS = finiteNumber(Config.USE_RADIUS) or 0
local SCAN_RADIUS = finiteNumber(Config.SCAN_RADIUS) or 0
Access.MATCH_RADIUS_SQ = MATCH_RADIUS * MATCH_RADIUS
Access.USE_RADIUS = USE_RADIUS
Access.USE_RADIUS_SQ = USE_RADIUS * USE_RADIUS
Access.SCAN_RADIUS_SQ = SCAN_RADIUS * SCAN_RADIUS

--- Read once for the same reason: an export must answer, and comparing a millisecond count
--- with a value an operator mistyped as a string raises.
local JOB_MAX_AGE_MS = finiteNumber(Config.JOB_MAX_AGE_MS) or 0
Access.JOB_MAX_AGE_MS = JOB_MAX_AGE_MS

--- Horizontal distance, squared, or nil when the elevator has no usable X and Y.
--- Z never enters it: an elevator is callable from every floor of its own shaft.
---@param key string
---@param x number  already a coordinate: the caller validates its own reading once
---@param y number
---@return number|nil
function Access.flatDistanceSquared(key, x, y)
  local at = POSITIONS[key]
  if at == nil then return nil end
  local dx, dy = x - at.x, y - at.y
  return dx * dx + dy * dy
end

-- ---------------------------------------------------------------------------
-- Reading the configuration
-- ---------------------------------------------------------------------------

---@param key any
---@return table|nil
function Access.elevator(key)
  if type(key) ~= "string" then return nil end
  local elevator = ELEVATORS[key]
  if type(elevator) ~= "table" then return nil end
  return elevator
end

--- One configured floor by its NATIVE index, never its position in FLOORS.
---@param key string
---@param index integer
---@return table|nil
function Access.floor(key, index)
  local elevator = Access.elevator(key)
  index = finiteNumber(index)
  if elevator == nil or index == nil then return nil end
  local floors = elevator.FLOORS
  if type(floors) ~= "table" then return nil end
  for position = 1, #floors do
    local floor = floors[position]
    -- type-checked, not assumed: `FLOORS = { 0, 1 }` is a config a person writes
    if type(floor) == "table" and floor.INDEX == index then return floor end
  end
  return nil
end

--- Which configured elevator a native lift at (x, y, z) is, matched across the ground.
--- A declared ENTITY pins which one; X and Y must still agree, and Z never decides.
---@param entity string|nil
---@return string|nil key, table|nil elevator
function Access.locate(x, y, z, entity)
  -- z is validated and then ignored: a report with a broken axis is a broken report
  x, y = coordinate(x), coordinate(y)
  if x == nil or y == nil or coordinate(z) == nil then return nil, nil end
  local hash = type(entity) == "string" and entity:lower() or nil
  local radius = Access.MATCH_RADIUS_SQ
  local bestKey, bestDistance
  for key, at in pairs(POSITIONS) do
    local dx, dy = x - at.x, y - at.y
    local flat = dx * dx + dy * dy
    if flat <= radius then
      local declared = ENTITY_HASHES[key]
      if declared ~= nil and hash ~= nil and declared == hash then
        return key, ELEVATORS[key]
      end
      -- the key breaks a tie: `pairs` order must not decide between two shafts in one lobby
      if declared == nil and (bestDistance == nil or flat < bestDistance or
        (flat == bestDistance and key < bestKey)) then
        bestKey, bestDistance = key, flat
      end
    end
  end
  if bestKey == nil then return nil, nil end
  return bestKey, ELEVATORS[bestKey]
end

-- ---------------------------------------------------------------------------
-- The gate
-- ---------------------------------------------------------------------------

--- What grade of `name` this character holds, or nil for none.
---@param snapshot table
---@param name string
---@return integer|nil
local function heldGrade(snapshot, name)
  local job = snapshot.job
  if type(job) == "table" and job.name == name then
    return type(job.grade) == "table" and finiteNumber(job.grade.level) or 0
  end
  if Config.MEMBERSHIP ~= "any" then return nil end
  if type(snapshot.jobs) ~= "table" then return nil end
  return finiteNumber(snapshot.jobs[name])
end

--- May this character select this floor?
---@param floor table|nil
---@param snapshot table|nil  as client/state.lua keeps it, or nil when the core never answered
---@param nowMs integer
---@return boolean ok, string|nil error
function Access.evaluate(floor, snapshot, nowMs)
  if type(floor) ~= "table" then return false, "no_such_floor" end
  local required = floor.JOBS
  -- a public floor stays open with no snapshot: a core outage must not trap a lobby
  if type(required) ~= "table" or next(required) == nil then return true, nil end

  -- `finiteNumber`, never `coordinate`: a millisecond clock outgrows BOUND mid-session
  local atMs = type(snapshot) == "table" and finiteNumber(snapshot.atMs) or nil
  if atMs == nil then return false, "no_character" end
  if nowMs - atMs > JOB_MAX_AGE_MS then return false, "job_stale" end
  if type(snapshot.job) ~= "table" then return false, "no_character" end

  local worst, worstRank = "job_required", RANK.job_required
  for name, minimum in pairs(required) do
    local held = heldGrade(snapshot, name)
    if held ~= nil then
      if held < (finiteNumber(minimum) or 0) then
        if RANK.grade_too_low > worstRank then
          worst, worstRank = "grade_too_low", RANK.grade_too_low
        end
      -- duty lives on the primary job only: the membership map holds grades, not a clock
      elseif floor.ON_DUTY == true and
        not (snapshot.job.name == name and snapshot.job.onDuty == true) then
        if RANK.off_duty > worstRank then worst, worstRank = "off_duty", RANK.off_duty end
      else
        return true, nil
      end
    end
  end
  return false, worst
end

--- Every floor to draw for this character, in configured order.
---@param key string
---@param snapshot table|nil
---@param nowMs integer
---@return table rows  `{ index, label, ok, error, reason }`
function Access.list(key, snapshot, nowMs)
  local elevator = Access.elevator(key)
  if elevator == nil then return {} end
  local floors = elevator.FLOORS
  if type(floors) ~= "table" then return {} end
  local hide = Config.DENIED_FLOORS == "hidden"
  local rows = {}
  for position = 1, #floors do
    local floor = floors[position]
    -- a malformed entry is skipped, not drawn: `problems()` is where it is reported
    if type(floor) == "table" then
      local ok, failure = Access.evaluate(floor, snapshot, nowMs)
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

--- The axes, in report order; hoisted, so no table is built per elevator per call.
local AXES = { "X", "Y", "Z" }

--- The config keys a distance or a timer does arithmetic on. All must be above zero.
local NUMBERS = { "MATCH_RADIUS", "USE_RADIUS", "SCAN_RADIUS", "SCAN_MS", "POLL_MS",
                  "JOB_MAX_AGE_MS", "TRAVEL_MS", "REQUEST_WINDOW_MS", "REQUESTS_PER_WINDOW" }

--- Everything wrong with the configuration that can be seen without a world.
--- It cannot check a job NAME: those live in opx77_core, which this VM cannot ask.
---@return string[]
function Access.problems()
  local lines = {}
  if type(Config.ELEVATORS) ~= "table" then
    lines[#lines + 1] = "ELEVATORS must be a table of elevator key -> definition"
  end
  for position = 1, #NUMBERS do
    local name = NUMBERS[position]
    local value = finiteNumber(Config[name])
    if value == nil or value <= 0 then
      lines[#lines + 1] = name .. " must be a finite number above zero"
    end
  end

  for key, elevator in pairs(ELEVATORS) do
    if type(elevator) ~= "table" then
      lines[#lines + 1] = tostring(key) .. ": every ELEVATORS entry must be a table"
    else
      -- the axes come first: every distance and every `%.2f` below them raises on a string
      for _, axis in ipairs(AXES) do
        if coordinate(elevator[axis]) == nil then
          lines[#lines + 1] = ("%s: %s must be a finite number inside %d"):format(key, axis,
            BOUND)
        end
      end

      local floors = elevator.FLOORS
      if type(floors) ~= "table" or #floors == 0 then
        lines[#lines + 1] = key .. ": no FLOORS, so its panel would be empty"
      else
        -- FLOOR_COUNT gets its own test: `%d` raises on a number with no integer form
        local count = integer(elevator.FLOOR_COUNT)
        if elevator.FLOOR_COUNT ~= nil and (count == nil or count < 1) then
          lines[#lines + 1] = key .. ": FLOOR_COUNT must be a whole number, 1 or more"
          count = nil
        end

        local seen = {}
        for position = 1, #floors do
          local floor = floors[position]
          local where = ("%s floor #%d"):format(key, position)
          -- type-checked before any field read: a hole in FLOORS lands here as nil
          if type(floor) ~= "table" then
            lines[#lines + 1] = where .. ": every FLOORS entry must be a table"
          else
            local index = integer(floor.INDEX)
            if index == nil or index < 0 then
              lines[#lines + 1] = where .. ": INDEX must be a whole number, 0 or more"
              -- nothing below may use it: `seen[nil]` raises, on the value just diagnosed
              index = nil
            elseif count ~= nil and index >= count then
              lines[#lines + 1] = ("%s: INDEX %d is outside FLOOR_COUNT %d"):format(where,
                index, count)
            elseif seen[index] then
              lines[#lines + 1] = ("%s: INDEX %d is declared twice"):format(where, index)
            end
            if index ~= nil then seen[index] = true end
            if type(floor.LABEL) ~= "string" or floor.LABEL == "" then
              lines[#lines + 1] = where .. ": no LABEL"
            end
            if floor.JOBS ~= nil then
              if type(floor.JOBS) ~= "table" then
                lines[#lines + 1] = where .. ": JOBS must be a table of name -> minimum grade"
              else
                for name, minimum in pairs(floor.JOBS) do
                  if type(name) ~= "string" or finiteNumber(minimum) == nil then
                    lines[#lines + 1] = where ..
                      ": JOBS entries are job name -> minimum grade level, e.g. { ncpd = 0 }"
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
