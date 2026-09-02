--- The gate, and the only file that reads a job.
---
--- Pure: no runtime, no network, no elevator API. Both halves load it, for different halves
--- of the question -- the client asks "may this player press this button", the server asks
--- only "is this a button this file declared", because the server HAS no character to ask
--- about. See README, "Where the job check happens".
---
--- Fails closed in four directions: no character, a job matching nothing, a snapshot older
--- than JOB_MAX_AGE_MS, and no snapshot at all. A PUBLIC floor is unaffected by all four: a
--- lobby that stops working while the core restarts is worse than anything the gate protects.

OpxElevators = OpxElevators or {}

local Access = {}
OpxElevators.access = Access

local Config = OPX_ELEVATORS_CONFIG

--- Failure ranking, so a floor listing three jobs reports the closest near-miss rather than
--- whichever `pairs` reached first.
local RANK = { off_duty = 3, grade_too_low = 2, job_required = 1 }

--- key -> its declared ENTITY, lower-cased once. `locate` runs for every lift a client sees
--- on every scan, and lower-casing each declared hash there allocated one string per
--- elevator per scan for a value config.lua fixes at load.
local ENTITY_HASHES = {}
for key, elevator in pairs(Config.ELEVATORS) do
  if type(elevator.ENTITY) == "string" then ENTITY_HASHES[key] = elevator.ENTITY:lower() end
end

--- The same predicate as `finite` elsewhere in this framework, coercing first and answering
--- with the number: anything `tonumber` accepts, so long as it is neither NaN nor either
--- infinity. It carries no range of its own -- a caller that needs one applies it to the
--- answer -- so that "finite" means exactly one thing everywhere and a bound stays visible
--- where it bites.
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

--- The world box every coordinate this resource accepts has to fit inside, and the ceiling on
--- any whole number it will later hand to `%d`.
local BOUND = 1000000

--- A world coordinate: finite, and inside the box above.
---
--- This bound used to sit inside the finiteness helper itself, which made a function called
--- `finite` mean "finite and small" -- and the two are not the same question. A millisecond
--- clock went through the same helper, so after BOUND milliseconds of uptime -- under
--- seventeen minutes -- `Access.evaluate` stopped recognising a snapshot and every job-gated
--- floor answered `no_character` for the rest of the session. A range belongs beside the
--- values it describes.
---@param value any
---@return number|nil
local function coordinate(value)
  local parsed = finiteNumber(value)
  if parsed == nil or parsed > BOUND or parsed < -BOUND then return nil end
  return parsed
end

--- A whole number inside the same box. The bound is not decoration here: `%d` RAISES on a
--- float with no integer representation, and both files format these.
---@param value any
---@return integer|nil
local function integer(value)
  local parsed = coordinate(value)
  if parsed == nil or parsed % 1 ~= 0 then return nil end
  return math.floor(parsed)
end

---@param elevator table
---@return number
function Access.distanceSquared(elevator, x, y, z)
  local dx, dy, dz = x - elevator.X, y - elevator.Y, z - elevator.Z
  return dx * dx + dy * dy + dz * dz
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

--- One configured floor by its NATIVE index, never its position in FLOORS: the panel's order
--- is a presentation choice and the shaft's is not.
---@param key string
---@param index integer
---@return table|nil
function Access.floor(key, index)
  local elevator = Access.elevator(key)
  if elevator == nil or finiteNumber(index) == nil then return nil end
  local floors = elevator.FLOORS
  if type(floors) ~= "table" then return nil end
  for position = 1, #floors do
    local floor = floors[position]
    if floor.INDEX == index then return floor end
  end
  return nil
end

--- Which configured elevator a native lift at (x, y, z) is.
---
--- A declared ENTITY pins WHICH elevator among those the coordinates could be; X and Y must
--- still agree. Z is free -- that is what the hash is for, since the cabin is wherever it
--- last stopped and a tower's cabin is nowhere near its shaft's declared Z.
---@param entity string|nil
---@return string|nil key, table|nil elevator
function Access.locate(x, y, z, entity)
  if coordinate(x) == nil or coordinate(y) == nil or coordinate(z) == nil then
    return nil, nil
  end
  local hash = type(entity) == "string" and entity:lower() or nil
  local radius = Config.MATCH_RADIUS * Config.MATCH_RADIUS
  local bestKey, bestElevator, bestDistance
  for key, elevator in pairs(Config.ELEVATORS) do
    local declared = ENTITY_HASHES[key]
    local dx, dy, dz = x - elevator.X, y - elevator.Y, z - elevator.Z
    -- the flat distance is the entity branch's test and half the full one: computed once
    local flat = dx * dx + dy * dy
    local distance = flat + dz * dz
    if declared ~= nil and hash ~= nil and declared == hash and flat <= radius then
      return key, elevator
    end
    if declared == nil and distance <= radius and
      (bestDistance == nil or distance < bestDistance) then
      bestKey, bestElevator, bestDistance = key, elevator, distance
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
    return type(job.grade) == "table" and job.grade.level or 0
  end
  if Config.MEMBERSHIP ~= "any" then return nil end
  if type(snapshot.jobs) ~= "table" then return nil end
  return finiteNumber(snapshot.jobs[name])
end

--- May this character select this floor?
---
--- `nowMs` is an argument rather than a read, so this file stays pure and staleness testable.
---@param floor table|nil
---@param snapshot table|nil  as client/state.lua keeps it, or nil when the core never answered
---@param nowMs integer
---@return boolean ok, string|nil error
function Access.evaluate(floor, snapshot, nowMs)
  if type(floor) ~= "table" then return false, "no_such_floor" end
  local required = floor.JOBS
  -- a public floor stays open with no snapshot: a core outage must not trap a lobby
  if type(required) ~= "table" or next(required) == nil then return true, nil end

  -- `finiteNumber`, never a bounded helper: this is a millisecond clock, and a ceiling on
  -- it silently expires every snapshot once the session has run long enough.
  if type(snapshot) ~= "table" or finiteNumber(snapshot.atMs) == nil then
    return false, "no_character"
  end
  if nowMs - snapshot.atMs > Config.JOB_MAX_AGE_MS then return false, "job_stale" end
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
---
--- It cannot check a job NAME: those live in opx77_core, which this VM cannot ask.
---@return string[]
function Access.problems()
  local lines = {}
  for key, elevator in pairs(Config.ELEVATORS) do
    local floors = elevator.FLOORS
    if type(floors) ~= "table" or #floors == 0 then
      lines[#lines + 1] = key .. ": no FLOORS, so its panel would be empty"
    else
      -- FLOOR_COUNT gets its own test: `%d` raises on a number with no integer
      -- representation, and a fractional one whose floors are all in range passed silently
      local count = elevator.FLOOR_COUNT
      if count ~= nil and (integer(count) == nil or count < 1) then
        lines[#lines + 1] = key .. ": FLOOR_COUNT must be a whole number, 1 or more"
        count = nil
      end

      local seen = {}
      for position = 1, #floors do
        local floor = floors[position]
        local where = ("%s floor #%d"):format(key, position)
        local index = floor.INDEX
        if integer(index) == nil or index < 0 then
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

