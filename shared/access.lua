--- The gate: reads config.lua and decides which floors a character may select.

OpxElevators = OpxElevators or {}

local Access = {}
OpxElevators.access = Access

local Config = OPX_ELEVATORS_CONFIG

--- Failure ranking, so the closest near-miss is reported rather than the first `pairs` found.
local RANK = { off_duty = 3, grade_too_low = 2, job_required = 1 }

--- key -> its declared ENTITY, lower-cased once at load.
local ENTITY_HASHES = {}
for key, elevator in pairs(Config.ELEVATORS) do
  if type(elevator.ENTITY) == "string" then ENTITY_HASHES[key] = elevator.ENTITY:lower() end
end

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

--- The box every accepted coordinate must fit inside, and the ceiling on any `%d` argument.
local BOUND = 1000000

--- A world coordinate: finite, and inside BOUND.
---@param value any
---@return number|nil
local function coordinate(value)
  local parsed = finiteNumber(value)
  if parsed == nil or parsed > BOUND or parsed < -BOUND then return nil end
  return parsed
end

--- A whole number inside BOUND; `%d` raises on a float with no integer representation.
---@param value any
---@return integer|nil
local function integer(value)
  local parsed = coordinate(value)
  if parsed == nil or parsed % 1 ~= 0 then return nil end
  return math.floor(parsed)
end

--- Horizontal distance, squared, or nil when the elevator's X or Y is not a coordinate.
--- Z never enters it: an elevator is callable from every floor of its own shaft.
---@param elevator table
---@param x number
---@param y number
---@return number|nil
function Access.flatDistanceSquared(elevator, x, y)
  local ex, ey = coordinate(elevator.X), coordinate(elevator.Y)
  if ex == nil or ey == nil then return nil end
  local dx, dy = x - ex, y - ey
  return dx * dx + dy * dy
end

-- ---------------------------------------------------------------------------
-- Reading the configuration
-- ---------------------------------------------------------------------------

---@param key any
---@return table|nil
function Access.elevator(key)
  if type(key) ~= "string" then return nil end
  local elevator = Config.ELEVATORS[key]
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
    if floor.INDEX == index then return floor end
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
  local radius = Config.MATCH_RADIUS * Config.MATCH_RADIUS
  local bestKey, bestElevator, bestDistance
  for key, elevator in pairs(Config.ELEVATORS) do
    local declared = ENTITY_HASHES[key]
    local flat = Access.flatDistanceSquared(elevator, x, y)
    if flat ~= nil and flat <= radius then
      if declared ~= nil and hash ~= nil and declared == hash then return key, elevator end
      -- the key breaks a tie: `pairs` order must not decide between two shafts in one lobby
      if declared == nil and (bestDistance == nil or flat < bestDistance or
        (flat == bestDistance and key < bestKey)) then
        bestKey, bestElevator, bestDistance = key, elevator, flat
      end
    end
  end
  return bestKey, bestElevator
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
  if nowMs - atMs > Config.JOB_MAX_AGE_MS then return false, "job_stale" end
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
  return rows
end

--- Everything wrong with ELEVATORS that can be seen without a world.
--- It cannot check a job NAME: those live in opx77_core, which this VM cannot ask.
---@return string[]
function Access.problems()
  local lines = {}
  for key, elevator in pairs(Config.ELEVATORS) do
    -- the axes come first: every distance and every `%.2f` below them raises on a string
    for _, axis in ipairs({ "X", "Y", "Z" }) do
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
        local index = integer(floor.INDEX)
        if index == nil or index < 0 then
          lines[#lines + 1] = where .. ": INDEX must be a whole number, 0 or more"
          -- nothing below may use it: `seen[nil]` raises, on the value just diagnosed
          index = nil
        elseif count ~= nil and index >= count then
          lines[#lines + 1] = ("%s: INDEX %d is outside FLOOR_COUNT %d"):format(where, index,
            count)
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
  table.sort(lines)
  return lines
end
