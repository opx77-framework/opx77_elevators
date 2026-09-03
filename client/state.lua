--- Client-side state: the character's job snapshot, the lifts in range, and the bound ids.

OpxElevators = OpxElevators or {}

local Config = OPX_ELEVATORS_CONFIG
local Access = OpxElevators.access

--- A sighting is believed for two scans, so one missed pass does not blink a panel shut.
--- Read once: every export below reaches it, and an export answers rather than raising.
local STALE_MS = (Access.finiteNumber(Config.SCAN_MS) or 0) * 2

local State = {}
OpxElevators.state = State

--- `{ job = PlayerJob|nil, jobs = table|nil, atMs = integer }`, or nil when the core has
--- never answered.
---@type table|nil
State.snapshot = nil

--- key -> { id, floorCount, atMs }. Filled by the server's `bound` event.
State.bound = {}

--- key -> what one scan saw of a lift. `reach`, `distance`, `id`, `managed` and `atMs`
--- are read.
State.seen = {}

--- Adopt a PlayerData snapshot from opx77_core; only the job travels.
---@param playerData table|nil
---@param nowMs integer
function State.adopt(playerData, nowMs)
  if type(playerData) ~= "table" then return end
  State.snapshot = {
    job = type(playerData.job) == "table" and playerData.job or nil,
    jobs = type(playerData.jobs) == "table" and playerData.jobs or nil,
    atMs = nowMs,
  }
end

--- The core said there is no character; different from a call that never landed.
function State.forget()
  State.snapshot = nil
end

--- Record what one scan saw. `lift` is a `Open77.elevators.nearby` entry; `playerX` and
--- `playerY` are the player's own, or nil when the host would not answer them.
---@param key string
---@param lift table
---@param nowMs integer
---@param playerX number|nil
---@param playerY number|nil
function State.sighted(key, lift, nowMs, playerX, playerY)
  local position = lift.position or {}
  local flat = nil
  if type(playerX) == "number" and type(playerY) == "number" then
    flat = Access.flatDistanceSquared(key, playerX, playerY)
  end
  State.seen[key] = {
    -- across the ground, to the DECLARED position, which is what the server measures too
    reach = flat ~= nil and math.sqrt(flat) or nil,
    -- the host's own 3D distance to the cabin: the fallback when `reach` is unknown, and
    -- a different measurement, to a different point (see README)
    distance = lift.distance,
    entity = lift.engineEntity,
    -- the SERVER's id, present only once the lift is managed
    id = lift.id,
    controller = lift.controllerEntity,
    floorCount = lift.floorCount,
    activeFloor = lift.activeFloor,
    managed = lift.managed == true,
    x = position.x, y = position.y, z = position.z,
    atMs = nowMs,
  }
end

--- Whether a sighting is recent enough to answer with.
---@param lift table
---@param nowMs integer
---@return boolean
local function current(lift, nowMs)
  return type(lift.atMs) == "number" and nowMs - lift.atMs <= STALE_MS
end

--- The elevator the player is standing at, or nil: the nearest within USE_RADIUS.
--- Ranked across the ground, so every floor of a shaft is in reach of its own panel.
---@param nowMs integer
---@return string|nil key
function State.nearest(nowMs)
  local bestKey, bestDistance
  for key, lift in pairs(State.seen) do
    -- the fallback measures a different thing, to the cabin and in three dimensions
    local reach = lift.reach or lift.distance
    -- the key breaks a tie: `pairs` order must not decide between two shafts in one lobby
    if current(lift, nowMs) and type(reach) == "number" and
      reach <= Access.USE_RADIUS and (bestDistance == nil or reach < bestDistance or
      (reach == bestDistance and key < bestKey)) then
      bestKey, bestDistance = key, reach
    end
  end
  return bestKey
end

--- The floor list for this player, at this elevator.
---@param key string
---@param nowMs integer
---@return table rows
function State.rows(key, nowMs)
  return Access.list(key, State.snapshot, nowMs)
end

--- What `state` publishes: enough to debug a panel that will not open.
---@param nowMs integer
---@return table
function State.report(nowMs)
  local seen, bound = 0, 0
  -- only the current ones: State.seen keeps a lift the player walked away from
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
    -- whether the gate would still trust the snapshot
    fresh = snapshot ~= nil and (nowMs - snapshot.atMs) <= Access.JOB_MAX_AGE_MS,
    ageMs = snapshot and (nowMs - snapshot.atMs) or nil,
    seen = seen,
    bound = bound,
    nearest = State.nearest(nowMs),
  }
end
