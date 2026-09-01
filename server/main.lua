--- opx77_elevators -- the server half: ownership, and everything a server can prove.
---
--- It cannot learn a player's job. The job lives in opx77_core and the server runtime
--- installs no cross-resource event bus, so there is no message to send and no promise to
--- await. What a client says about a job is a claim; this file does not pretend otherwise.
---
--- It checks, from its own authority, every other clause: the elevator is one THIS resource
--- adopted, the floor is one config.lua declares and is inside the native device's count, the
--- player is standing at the cabin per a replicated snapshot, in the elevator's routing
--- bucket, and not spamming.

local Config = OPX_ELEVATORS_CONFIG
local Access = OpxElevators.access

local Server = {}
OpxElevators.server = Server

--- key -> { id, entity, bucket, floorCount }. What this resource adopted; the host's `all()`
--- is the authority and this is the index.
local owned = {}

--- key -> { [player] = true }. Who has been told an id, so a removal can reach them.
local told = {}

local sightWindows, requestWindows, logWindows = {}, {}, {}

--- key -> true once the floor-count mismatch has been said. It is a config mistake, and
--- saying it twelve times a second does not make it more true.
local warnedCount = {}

--- Sightings per second, per player: a client streaming through a lobby can legitimately see
--- several lifts at once, and no client needs more.
local SIGHTS_PER_SECOND = 12

--- Failure ranking, so a floor listing three jobs reports the closest near-miss rather than
--- whichever `pairs` reached first.
local RANK = { off_duty = 3, grade_too_low = 2, job_required = 1 }

---@return integer
local function nowMs()
  return math.floor(Open77.time.monotonic() * 1000)
end

---@param value any
---@return number|nil
local function finite(value)
  value = tonumber(value)
  if value == nil or value ~= value or value == math.huge or value == -math.huge or
    math.abs(value) > 1000000 then
    return nil
  end
  return value
end

---@param value any
---@return integer|nil
local function integer(value)
  local parsed = finite(value)
  if parsed == nil or parsed % 1 ~= 0 then return nil end
  return math.floor(parsed)
end

--- Engine identifiers are opaque: compared as lower-cased strings, never through `tonumber`,
--- which a 64-bit hash does not survive.
---@return boolean
local function sameEntity(left, right)
  return tostring(left or ""):lower() == tostring(right or ""):lower()
end

--- Truncate and strip control characters: a key comes off the wire and reaches a format
--- string, where a newline forges a whole log line.
---@param value any
---@return string
local function safe(value)
  local text = tostring(value or ""):gsub("[%c]", " ")
  if #text > 64 then text = text:sub(1, 64) .. "..." end
  return text
end

---@return boolean
local function within(windows, player, limit, spanMs)
  local at = nowMs()
  local window = windows[player]
  if window == nil or at - window.started >= spanMs then
    window = { started = at, count = 0 }
    windows[player] = window
  end
  -- stops AT the limit rather than climbing for the window's life
  if window.count >= limit then return false end
  window.count = window.count + 1
  return true
end

-- ---------------------------------------------------------------------------
-- Adoption
-- ---------------------------------------------------------------------------

--- Lock or unlock player requests on one lift.
---
--- `flags.locked` is the host's own switch for "refuse requests coming from a client", which
--- is what makes this file the only way the cabin moves. `powered` is left exactly as the
--- host set it: an operator who cut the power did it on purpose.
---@param id integer
---@return boolean
local function applyLock(id)
  local lift = Open77.elevators.get(id)
  if lift == nil then return false end
  local flags = (lift.flags or 0) | Open77.elevators.flags.locked
  if flags == lift.flags then return true end
  return Open77.elevators.setFlags(id, flags) == true
end

--- Whether a lift the host reported stands at a configured elevator. Horizontal only: a shaft
--- does not move on the floor plan and the cabin does not stay on it.
---@return boolean
local function atElevator(elevator, lift)
  local position = lift.position or lift
  local x, y = finite(position.x), finite(position.y)
  if x == nil or y == nil then return false end
  local dx, dy = x - elevator.X, y - elevator.Y
  return dx * dx + dy * dy <= Config.MATCH_RADIUS * Config.MATCH_RADIUS
end

--- Take ownership of a native lift a client has just reported. Answers a value, never raises.
---@return table
function Server.adopt(key, entity, x, y, z, bucket, floorCount, activeFloor)
  local configured = Access.elevator(key)
  -- Type-checked rather than trusted: `all()` is a host call, and this runs off a net event
  -- where a raise is swallowed with no adoption and no answer.
  local adopted = Open77.elevators.all(bucket)
  local adoptedCount = type(adopted) == "table" and #adopted or 0
  for index = 1, adoptedCount do
    local existing = adopted[index]
    if sameEntity(existing.engineEntity, entity) then
      -- The hash came off the wire and `all()` lists every adopted lift in the bucket. Naming
      -- another elevator's hash from here would point this key at that other cabin.
      if configured == nil or not atElevator(configured, existing) then
        return { ok = false, error = "wrong_place" }
      end
      for otherKey, record in pairs(owned) do
        if otherKey ~= key and record.id == existing.id then
          return { ok = false, error = "already_owned", reason = otherKey }
        end
      end
      owned[key] = { id = existing.id, entity = existing.engineEntity, bucket = bucket,
                     floorCount = existing.floorCount }
      -- locked again: the flag did not survive our restart, and adopt never reruns here
      if not applyLock(existing.id) then
        Open77.log.warn(("%s re-claimed as %s but could not be locked"):format(key,
          tostring(existing.id)))
      end
      return { ok = true, id = existing.id, already = true }
    end
  end

  -- wrapped because the shipped reference resource wraps it, which is the only evidence
  -- available about whether it can throw
  local ok, id, reason = pcall(Open77.elevators.adopt, {
    engineEntity = entity,
    position = { x = x, y = y, z = z },
    bucket = bucket,
    floorCount = floorCount,
    initialFloor = activeFloor,
  })
  if not ok then return { ok = false, error = "adopt_raised", reason = tostring(id) } end
  if id == nil then return { ok = false, error = "adopt_refused", reason = tostring(reason) } end

  owned[key] = { id = id, entity = entity, bucket = bucket, floorCount = floorCount,
                 atMs = nowMs() }
  if not applyLock(id) then
    -- worth a line rather than a rollback: an unlocked lift still answers this file, it just
    -- also answers a client directly, and running that way unnoticed is the real failure
    Open77.log.warn(("%s adopted as %s but could not be locked"):format(key, tostring(id)))
  end
  return { ok = true, id = id }
end

--- A client says it is looking at an unmanaged lift.
---
--- Discovery only proposes immutable topology. The server picks the elevator, the bucket and
--- the floor count itself; the client's report is a set of coordinates and a hash.
RegisterNetEvent("opx77_elevators:sighted", function(entity, x, y, z, floorCount, activeFloor)
  local player = tonumber(source) or 0
  if player <= 0 then return end
  if not within(sightWindows, player, SIGHTS_PER_SECOND, 1000) then return end

  if type(entity) ~= "string" or
    entity:match("^0[xX]%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") == nil then
    return
  end
  x, y, z = finite(x), finite(y), finite(z)
  floorCount, activeFloor = integer(floorCount), integer(activeFloor)
  if x == nil or y == nil or z == nil or floorCount == nil or activeFloor == nil then return end
  if floorCount < 1 or floorCount > 1025 or activeFloor < 0 or activeFloor >= floorCount then
    return
  end

  local position = Open77.players.position(player)
  if position == nil then return end
  local dx, dy, dz = x - position.x, y - position.y, z - position.z
  if dx * dx + dy * dy + dz * dz > Config.SCAN_RADIUS * Config.SCAN_RADIUS then return end

  local key, elevator = Access.locate(x, y, z, entity)
  if key == nil then return end

  -- The bucket is the ELEVATOR's, never the reporter's: adopting into a player's bucket lets
  -- the first person to walk past a lift fix it to theirs, and one doing it from a private
  -- instance leaves everyone else answered `wrong_bucket` for the life of the process.
  local bucket = integer(elevator.BUCKET) or 0
  if position.bucket ~= bucket then return end

  -- Same for the floor count: it becomes the ceiling every index is checked against.
  local declared = integer(elevator.FLOOR_COUNT)
  if declared ~= nil and declared >= 1 then
    -- once per elevator, not once per sighting: a client reports up to twelve a second and
    -- this is a config mistake, which does not become truer by being said again
    if declared ~= floorCount and not warnedCount[key] then
      warnedCount[key] = true
      Open77.log.warn(("%s reported %d floors, config declares %d; using the config"):format(
        key, floorCount, declared))
    end
    floorCount = declared
    if activeFloor >= floorCount then activeFloor = 0 end
  end

  local existing = owned[key]
  if existing ~= nil then
    told[key] = told[key] or {}
    told[key][player] = true
    TriggerClientEvent("opx77_elevators:bound", player, key, existing.id)
    return
  end

  local result = Server.adopt(key, entity, x, y, z, bucket, floorCount, activeFloor)
  if not result.ok then
    Open77.log.warn(("%s not adopted: %s (%s)"):format(key, result.error, tostring(result.reason)))
    return
  end
  told[key] = told[key] or {}
  told[key][player] = true
  Open77.log.info(("%s adopted as elevator %s in bucket %s"):format(key, tostring(result.id),
    tostring(bucket)))
  TriggerClientEvent("opx77_elevators:bound", player, key, result.id)
end)

-- ---------------------------------------------------------------------------
-- Requests
-- ---------------------------------------------------------------------------

--- Where a player is standing, if that is at a configured elevator they may reach.
---@param player integer
---@return string|nil key, table|nil elevator, string|nil error
local function standingAt(player)
  local position = Open77.players.position(player)
  if position == nil then return nil, nil, "no_position" end
  local best, bestElevator, bestDistance
  for key, elevator in pairs(Config.ELEVATORS) do
    if (integer(elevator.BUCKET) or 0) == position.bucket then
      local distance = Access.distanceSquared(elevator, position.x, position.y, position.z)
      if distance <= Config.USE_RADIUS * Config.USE_RADIUS and
        (bestDistance == nil or distance < bestDistance) then
        best, bestElevator, bestDistance = key, elevator, distance
      end
    end
  end
  if best == nil then return nil, nil, "no_elevator_nearby" end
  return best, bestElevator, nil
end

--- Everything the server can prove about one floor request -- including the job, which is
--- the whole reason this file is here.
---@return table
function Server.request(player, key, index)
  if not within(requestWindows, player, Config.REQUESTS_PER_WINDOW,
    Config.REQUEST_WINDOW_MS) then
    return { ok = false, error = "rate_limited" }
  end

  local elevator = Access.elevator(key)
  if elevator == nil then return { ok = false, error = "no_such_elevator" } end
  index = integer(index)
  local floor = index ~= nil and Access.floor(key, index) or nil
  if floor == nil then return { ok = false, error = "no_such_floor" } end

  local record = owned[key]
  if record == nil then return { ok = false, error = "not_adopted" } end
  local lift = Open77.elevators.get(record.id)
  if lift == nil then
    -- removed under us; forget it so the next sighting adopts it again
    owned[key] = nil
    return { ok = false, error = "not_adopted" }
  end
  if index >= lift.floorCount then return { ok = false, error = "floor_out_of_range" } end

  local position = Open77.players.position(player)
  if position == nil then return { ok = false, error = "no_position" } end
  if position.bucket ~= lift.bucket then return { ok = false, error = "wrong_bucket" } end
  -- measured against the DECLARED position, not the cabin's: a cabin at the top of the shaft
  -- is thirty metres from the player at the ground-floor panel, who is exactly who may call it
  if Access.distanceSquared(elevator, position.x, position.y, position.z) >
    Config.USE_RADIUS * Config.USE_RADIUS then
    return { ok = false, error = "too_far" }
  end

  -- No job clause, and there cannot be one: see the header. `floor` is read above only to
  -- prove the index is one config.lua declares.

  local moved = Open77.elevators.goTo(record.id, index, { travelMs = Config.TRAVEL_MS })
  if not moved then return { ok = false, error = "move_rejected" } end
  -- the adoption has served: the sweep below leaves it alone from here on
  record.usedAtMs = nowMs()
  return { ok = true, id = record.id, floor = index }
end

RegisterNetEvent("opx77_elevators:request", function(key, index)
  local player = tonumber(source) or 0
  if player <= 0 then return end
  local result = Server.request(player, key, index)
  -- The rate limit governs the cabin, not this answer: a refused packet still costs one
  -- outbound event echoing whatever the client sent. Bounded, and dropped entirely once the
  -- limit is the reason -- a client that is being told to slow down does not need telling
  -- more often than it is allowed to ask.
  if result.error ~= "rate_limited" then
    TriggerClientEvent("opx77_elevators:answer", player, safe(key), integer(index),
      result.ok, result.error)
  end
  -- one line per player per second: the refusal path is the cheap one for an attacker, and
  -- it is the path that writes to disk
  if not result.ok and within(logWindows, player, 1, 1000) then
    Open77.log.info(("player %d refused %s floor %s: %s"):format(player, safe(key), safe(index),
      tostring(result.error)))
  end
end)

--- The floor list for wherever the player is standing.
---
--- The client sends no key and holds no config: it asks where it is, and is told what it may
--- see. A row it is not allowed is either greyed with the operator's wording or absent.
RegisterNetEvent("opx77_elevators:floors", function()
  local player = tonumber(source) or 0
  if player <= 0 then return end
  if not within(requestWindows, player, Config.REQUESTS_PER_WINDOW,
    Config.REQUEST_WINDOW_MS) then
    return
  end

  local key, elevator, failure = standingAt(player)
  if key == nil then
    TriggerClientEvent("opx77_elevators:list", player, false, failure)
    return
  end
  TriggerClientEvent("opx77_elevators:list", player, true, nil, {
    elevator = key,
    label = elevator.LABEL,
    adopted = owned[key] ~= nil,
  })
end)

-- ---------------------------------------------------------------------------
-- Keeping the index honest
-- ---------------------------------------------------------------------------

--- Drop an adoption and tell everyone who was handed its id. Both callers -- the host
--- removing a lift, and the unused-adoption sweep -- have to do exactly this, and doing it
--- twice by hand is how two copies of one rule drift apart. The logging is the caller's:
--- one of them is routine and the other is a warning.
---@param key string
local function release(key)
  owned[key] = nil
  local audience = told[key]
  if audience == nil then return end
  for player in pairs(audience) do
    TriggerClientEvent("opx77_elevators:released", player, key)
  end
  told[key] = nil
end

AddEventHandler("onElevatorRemoved", function(id, _, reason)
  for key, record in pairs(owned) do
    if record.id == tonumber(id) then
      release(key)
      Open77.log.info(("%s released: %s"):format(key, tostring(reason)))
      return
    end
  end
end)

--- Both departure events, because the platform raises two and documents neither.
---@param playerId any
function Server.forget(playerId)
  local player = tonumber(playerId) or tonumber(source) or 0
  if player <= 0 then return end
  sightWindows[player] = nil
  requestWindows[player] = nil
  logWindows[player] = nil
  for _, players in pairs(told) do players[player] = nil end
end

--- Release an adoption that has never moved a cabin.
---
--- The hash in a sighting cannot be verified: `Open77.elevators.all()` lists only lifts that
--- are already adopted, so a lift nobody has taken yet is invisible to this VM. One packet
--- with a well-formed hash therefore binds a key to a lift that may not exist, and every
--- later sighting short-circuits on it -- the real cabin can then never be adopted, because
--- the host refuses a second adopt for the same bucket.
---
--- It cannot be prevented here, so it is made to heal: an adoption that has not moved a cabin
--- within UNUSED_MS goes back, and the next honest sighting takes the slot.
local UNUSED_MS = 600000

CreateThread(function()
  while true do
    Wait(60000)
    local at = nowMs()
    for key, record in pairs(owned) do
      if record.usedAtMs == nil and at - (record.atMs or at) > UNUSED_MS then
        release(key)
        Open77.log.warn(("%s released: adopted %d minutes ago and never used")
          :format(key, math.floor(UNUSED_MS / 60000)))
      end
    end
  end
end)

AddEventHandler("onPlayerDisconnected", Server.forget)
AddEventHandler("playerDropped", Server.forget)

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------

if type(Config.COMMAND) == "string" and Config.COMMAND ~= "" then
  --- Restricted: it prints world positions and adoption state, which is operator information.
  RegisterCommand(Config.COMMAND, function(commandSource, args, raw)
    local lines = {}
    local problems = Access.problems()
    for index = 1, #problems do lines[index] = "config: " .. problems[index] end
    local filter = args and args[1]
    local report = {}
    for key, elevator in pairs(Config.ELEVATORS) do
      if filter == nil or filter == key then
        local record = owned[key]
        local lift = record and Open77.elevators.get(record.id) or nil
        report[#report + 1] = ("%s %s pos=%.2f,%.2f,%.2f floors=%d/%d id=%s %s"):format(
          key, tostring(elevator.LABEL), elevator.X, elevator.Y, elevator.Z,
          #(elevator.FLOORS or {}), integer(elevator.FLOOR_COUNT) or 0,
          record and tostring(record.id) or "-",
          lift and ("phase=%s floor=%s flags=%s"):format(tostring(lift.phase),
            tostring(lift.activeFloor), tostring(lift.flags)) or "not adopted")
      end
    end
    -- sorted: `pairs` order would reshuffle the report between two runs, and comparing two
    -- dumps is the whole use for it
    table.sort(report)
    for index = 1, #report do lines[#lines + 1] = report[index] end
    lines[#lines + 1] = ("denied=%s membership=%s"):format(Config.DENIED_FLOORS,
      Config.MEMBERSHIP)
    local player = tonumber(commandSource) or 0
    for index = 1, #lines do
      local line = lines[index]
      print(line)
      if player > 0 then
        TriggerClientEvent("open77:command:result", player, raw or "", true, line)
      end
    end
  end, true)
end

if type(Open77.elevators) ~= "table" then
  Open77.log.error("native elevator API unavailable; no elevator will be adopted")
else
  local problems = Access.problems()
  for index = 1, #problems do
    -- said at boot as well as on demand: every one produces the same symptom, a button that
    -- does nothing, and an operator standing in a lift cannot tell which mistake it was
    Open77.log.warn("config: " .. problems[index])
  end
  Open77.log.info("ready")
end
