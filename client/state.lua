--- opx77_elevators -- what this client knows, and how old it is.
--- Three things, and every one of them carries the time it was taken:
---   the character's job   from opx77_core, and stale after JOB_MAX_AGE_MS
---   the lifts in range    from `Open77.elevators.nearby`, and stale after two
---                         scans, because a lift that stopped being reported is
---                         a lift the player walked away from
---   the bound ids         which configured elevator got which Open77 id, from
---                         this resource's own server half
--- Nothing here calls the platform, the network or opx77_core: it is handed
--- values and answers questions about them, which is what makes the gate
--- testable without a client.

OpxElevators = OpxElevators or {}

local Config = OPX_ELEVATORS_CONFIG
local Access = OpxElevators.access

local State = {}
OpxElevators.state = State

--- `{ job = PlayerJob|nil, jobs = table|nil, atMs = integer }`, or nil when
--- opx77_core has never answered.
--- nil and "a character with no job" are different answers and both refuse a
--- gated floor, so the difference only shows up in the log -- but it shows up
--- there, and an operator reading "no_character" on a player who is very much
--- logged in has learnt something about their core.
---@type table|nil
State.snapshot = nil

--- key -> { id, floorCount, atMs }. Filled by the server's `bound` event.
State.bound = {}

--- key -> { distance, entity, floorCount, activeFloor, managed, atMs }.
State.seen = {}

--- Adopt a PlayerData snapshot from opx77_core.
--- Only the job travels. This resource has no use for money, metadata or a
--- citizen id, and copying them into a second place would make this file a
--- second answer to a question opx77_core already answers.
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

--- The core said there is no character. Authoritative, and different from a
--- call that never landed -- which leaves the snapshot alone to age out.
function State.forget()
  State.snapshot = nil
end

--- Record what one scan saw. `lift` is a `Open77.elevators.nearby` entry.
---@param key string
---@param lift table
---@param nowMs integer
function State.sighted(key, lift, nowMs)
  local position = lift.position or {}
  State.seen[key] = {
    distance = lift.distance,
    entity = lift.engineEntity,
    -- Present only once the lift is managed, and it is the SERVER's id: an
    -- unadopted lift has none, which is exactly what `managed` is saying.
    id = lift.id,
    controller = lift.controllerEntity,
    floorCount = lift.floorCount,
    activeFloor = lift.activeFloor,
    managed = lift.managed == true,
    x = position.x, y = position.y, z = position.z,
    atMs = nowMs,
  }
end

--- The elevator the player is standing at, or nil.
--- Nearest wins, and only within USE_RADIUS: two shafts in one lobby is a real
--- building, and picking the first match would make which panel opens depend on
--- table order.
---@param nowMs integer
---@return string|nil key
function State.nearest(nowMs)
  local staleMs = Config.SCAN_MS * 2
  local bestKey, bestDistance
  for key, lift in pairs(State.seen) do
    if nowMs - lift.atMs <= staleMs and type(lift.distance) == "number" and
      lift.distance <= Config.USE_RADIUS and
      (bestDistance == nil or lift.distance < bestDistance) then
      bestKey, bestDistance = key, lift.distance
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

--- What `state` publishes: enough to debug a panel that will not open, and
--- nothing a caller could mistake for authority.
---@param nowMs integer
---@return table
function State.report(nowMs)
  local seen, bound = 0, 0
  for _ in pairs(State.seen) do seen = seen + 1 end
  for _ in pairs(State.bound) do bound = bound + 1 end
  local snapshot = State.snapshot
  return {
    job = snapshot and snapshot.job and snapshot.job.name or nil,
    grade = snapshot and snapshot.job and snapshot.job.grade
      and snapshot.job.grade.level or nil,
    onDuty = snapshot and snapshot.job and snapshot.job.onDuty == true or false,
    -- Whether the gate would still trust the snapshot, which is the one
    -- question a "why is this floor greyed out" report needs answered.
    fresh = snapshot ~= nil and (nowMs - snapshot.atMs) <= Config.JOB_MAX_AGE_MS,
    ageMs = snapshot and (nowMs - snapshot.atMs) or nil,
    seen = seen,
    bound = bound,
    nearest = State.nearest(nowMs),
  }
end
