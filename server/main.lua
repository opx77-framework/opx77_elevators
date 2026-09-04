--- The server half: adoption, and everything a server can prove about a floor request.

local Config = OPX_ELEVATORS_CONFIG
local Access = OpxElevators.access
local Text = OpxElevators.Text

local Server = {}
OpxElevators.server = Server

--- key -> { id, entity, bucket, floorCount }. What this resource adopted; the host's `all()`
--- is the authority and this is the index.
local owned = {}

--- key -> { [player] = true }. Who has been told an id, so a removal can reach them.
local told = {}

local sightWindows, requestWindows, logWindows = {}, {}, {}

--- key -> true once the floor-count mismatch has been logged.
local warnedCount = {}

--- True once the "not an engine hash" rejection has been logged.
local warnedEntity = false

--- Sightings per second, per player.
local SIGHTS_PER_SECOND = 12

--- The scheduler clock in milliseconds; `monotonic` answers SECONDS. A non-finite reading is
--- dropped rather than propagated: a NaN would expire nothing, an infinity everything.
--- Holding the last reading is not a safe degradation here: every deadline in this file
--- shares this clock, so a frozen one saturates each rate-limit window for good and stops
--- the adoption sweep. `GetGameTimer` is the same scheduler clock, already in milliseconds.
---@return integer
local lastMs = 0
local clockWarned = false
local function nowMs()
  local read, seconds = pcall(Open77.time.monotonic)
  if read and type(seconds) == "number" and seconds == seconds and
    seconds >= 0 and seconds < math.huge then
    lastMs = math.floor(seconds * 1000)
    return lastMs
  end
  local ticked, ms = pcall(GetGameTimer)
  if ticked and type(ms) == "number" and ms == ms and ms >= 0 and ms < math.huge then
    if not clockWarned then
      clockWarned = true
      Open77.log.warn("Open77.time.monotonic unreadable; falling back to GetGameTimer")
    end
    lastMs = math.floor(ms)
  end
  return lastMs
end

--- The coercions both halves measure with; one implementation, in shared/access.lua.
local coordinate, integer = Access.coordinate, Access.integer

--- Engine identifiers are opaque: compared as lower-cased strings, never through `tonumber`.
---@return boolean
local function sameEntity(left, right)
  return tostring(left or ""):lower() == tostring(right or ""):lower()
end

--- The longest a value off the wire may be once it reaches a log line, in characters.
local MAX_LOGGED = 64

--- Strip control characters and cap the length before a wire value reaches a format string,
--- where a newline would forge a whole log line.
---@param value any
---@return string
local function safe(value)
  return Text.clean(value, MAX_LOGGED, "...") or ""
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

--- Lock player requests on one lift, so this file is the only thing that moves the cabin.
--- `powered` is left exactly as the host set it.
---@param id integer
---@return boolean
local function applyLock(id)
  local lift = Open77.elevators.get(id)
  if lift == nil then return false end
  local flags = (lift.flags or 0) | Open77.elevators.flags.locked
  if flags == lift.flags then return true end
  return Open77.elevators.setFlags(id, flags) == true
end

--- Whether a lift the host reported stands at a configured elevator. Horizontal only.
--- The host nests the position under `position` in one shape and flattens it in the other.
---@param key string
---@param lift table
---@return boolean
local function atElevator(key, lift)
  local position = lift.position or lift
  local x, y = coordinate(position.x), coordinate(position.y)
  if x == nil or y == nil then return false end
  local flat = Access.flatDistanceSquared(key, x, y)
  return flat ~= nil and flat <= Access.MATCH_RADIUS_SQ
end

--- Take ownership of a native lift a client has just reported. Answers a value, never raises.
---@return table
function Server.adopt(key, entity, x, y, z, bucket, floorCount, activeFloor)
  local configured = Access.elevator(key)
  -- type-checked: `all()` is a host call, and a raise off a net event is swallowed silently
  local adopted = Open77.elevators.all(bucket)
  local adoptedCount = type(adopted) == "table" and #adopted or 0
  for index = 1, adoptedCount do
    local existing = adopted[index]
    if sameEntity(existing.engineEntity, entity) then
      -- the hash came off the wire: another elevator's would point this key at that cabin
      if configured == nil or not atElevator(key, existing) then
        return { ok = false, error = "wrong_place" }
      end
      for otherKey, record in pairs(owned) do
        if otherKey ~= key and record.id == existing.id then
          return { ok = false, error = "already_owned", reason = otherKey }
        end
      end
      -- atMs matters: without it the sweep computes `at - at > UNUSED_MS`, which is never
      -- true, so a key re-claimed after a restart could never heal from a bogus sighting
      owned[key] = { id = existing.id, entity = existing.engineEntity, bucket = bucket,
                     floorCount = existing.floorCount, atMs = nowMs() }
      -- locked again: the flag did not survive our restart, and adopt never reruns here
      if not applyLock(existing.id) then
        Open77.log.warn(("%s re-claimed as %s but could not be locked"):format(key,
          tostring(existing.id)))
      end
      return { ok = true, id = existing.id, already = true }
    end
  end

  -- wrapped: whether `adopt` can throw is not documented
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
    -- a line rather than a rollback: an unlocked lift also answers a client directly
    Open77.log.warn(("%s adopted as %s but could not be locked"):format(key, tostring(id)))
  end
  return { ok = true, id = id }
end

--- A client says it is looking at an unmanaged lift.
--- The server picks the elevator, the bucket and the floor count itself.
RegisterNetEvent("opx77_elevators:sighted", function(entity, x, y, z, floorCount, activeFloor)
  local player = tonumber(source) or 0
  if player <= 0 then return end
  if not within(sightWindows, player, SIGHTS_PER_SECOND, 1000) then return end

  if type(entity) ~= "string" or
    entity:match("^0[xX]%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") == nil then
    -- said once: a wire-format disagreement otherwise shows up only as `not_adopted` forever
    if not warnedEntity then
      warnedEntity = true
      Open77.log.warn(("sighting rejected: first argument is not an engine hash (%s); the " ..
        "client and this handler disagree about the wire format"):format(safe(entity)))
    end
    return
  end
  x, y, z = coordinate(x), coordinate(y), coordinate(z)
  floorCount, activeFloor = integer(floorCount), integer(activeFloor)
  if x == nil or y == nil or z == nil or floorCount == nil or activeFloor == nil then return end
  if floorCount < 1 or floorCount > 1025 or activeFloor < 0 or activeFloor >= floorCount then
    return
  end

  local position = Open77.players.position(player)
  if position == nil then return end
  local px, py, pz = coordinate(position.x), coordinate(position.y), coordinate(position.z)
  if px == nil or py == nil or pz == nil then return end
  local dx, dy, dz = x - px, y - py, z - pz
  if dx * dx + dy * dy + dz * dz > Access.SCAN_RADIUS_SQ then return end

  local key, elevator = Access.locate(x, y, z, entity)
  if key == nil then return end

  -- the bucket is the ELEVATOR's, never the reporter's: otherwise the first passer-by fixes
  -- the lift to their own bucket for the life of the process
  local bucket = integer(elevator.BUCKET) or 0
  if position.bucket ~= bucket then return end

  -- same for the floor count: it becomes the ceiling every index is checked against
  local declared = integer(elevator.FLOOR_COUNT)
  if declared ~= nil and declared >= 1 then
    -- once per elevator, not once per sighting
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
    TriggerClientEvent("opx77_elevators:bound", player, key, existing.id, existing.floorCount)
    return
  end

  local result = Server.adopt(key, entity, x, y, z, bucket, floorCount, activeFloor)
  if not result.ok then
    -- throttled with the request refusals: a client sights faster than a disk write
    if within(logWindows, player, 1, 1000) then
      Open77.log.warn(("%s not adopted: %s (%s)"):format(key, result.error,
        tostring(result.reason)))
    end
    return
  end
  told[key] = told[key] or {}
  told[key][player] = true
  Open77.log.info(("%s adopted as elevator %s in bucket %s"):format(key, tostring(result.id),
    tostring(bucket)))
  -- the count is read from the record: `Server.adopt` settled it between config and host
  local record = owned[key]
  TriggerClientEvent("opx77_elevators:bound", player, key, result.id,
    record and record.floorCount or floorCount)
end)

--- Drop an adoption and tell everyone who was handed its id. The logging is the caller's.
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

-- ---------------------------------------------------------------------------
-- Requests
-- ---------------------------------------------------------------------------

--- Everything the server can prove about one floor request.
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
    -- released, not just forgotten: a client keeping the dead id never re-reports the lift
    release(key)
    return { ok = false, error = "not_adopted" }
  end
  local floorCount = integer(lift.floorCount)
  if floorCount == nil or index >= floorCount then
    return { ok = false, error = "floor_out_of_range" }
  end

  local position = Open77.players.position(player)
  if position == nil then return { ok = false, error = "no_position" } end
  if position.bucket ~= lift.bucket then return { ok = false, error = "wrong_bucket" } end
  local px, py = coordinate(position.x), coordinate(position.y)
  if px == nil or py == nil then return { ok = false, error = "no_position" } end
  -- across the ground, and against the DECLARED position: the cabin may be up the shaft,
  -- and an elevator is callable from every floor of its own
  local reach = Access.flatDistanceSquared(key, px, py)
  if reach == nil or reach > Access.USE_RADIUS_SQ then
    return { ok = false, error = "too_far" }
  end

  -- no job clause: this VM cannot ask opx77_core for a job (see README)
  local moved = Open77.elevators.goTo(record.id, index, { travelMs = Config.TRAVEL_MS })
  if not moved then return { ok = false, error = "move_rejected" } end
  -- the adoption has served: the sweep below leaves it alone from here on
  record.usedAtMs = nowMs()
  -- who this cabin is moving for, and until when. A player who leaves mid-travel would
  -- otherwise have the cabin arrive and park itself open on a floor nobody answers for.
  record.rider = player
  record.rideEndsAtMs = record.usedAtMs + (tonumber(Config.TRAVEL_MS) or 0)
  return { ok = true, id = record.id, floor = index }
end

RegisterNetEvent("opx77_elevators:request", function(key, index)
  local player = tonumber(source) or 0
  if player <= 0 then return end
  local result = Server.request(player, key, index)
  -- the rate limit governs the cabin, not this answer; dropped only when it is the reason
  if result.error ~= "rate_limited" then
    TriggerClientEvent("opx77_elevators:answer", player, safe(key), integer(index),
      result.ok, result.error)
  end
  -- one line per player per second: the refusal path is the cheap one for an attacker
  if not result.ok and within(logWindows, player, 1, 1000) then
    Open77.log.info(("player %d refused %s floor %s: %s"):format(player, safe(key), safe(index),
      tostring(result.error)))
  end
end)

-- ---------------------------------------------------------------------------
-- Keeping the index honest
-- ---------------------------------------------------------------------------

AddEventHandler("onElevatorRemoved", function(id, _, reason)
  for key, record in pairs(owned) do
    if record.id == tonumber(id) then
      release(key)
      Open77.log.info(("%s released: %s"):format(key, tostring(reason)))
      return
    end
  end
end)

--- Forget a departing player's rate-limit windows and audience membership, and give back
--- any cabin they left in motion.
---
--- This is the departure of an ADMITTED player. A connection refused at the door raises
--- `onPlayerRejected` instead, which this resource has no reason to listen for.
---@param playerId any  a string, like every host event argument
---@param reason? any  `connection_closed`, or the text a disconnect, kick or ban carried
function Server.forget(playerId, reason)
  local player = tonumber(playerId) or 0
  if player <= 0 then return end
  sightWindows[player] = nil
  requestWindows[player] = nil
  logWindows[player] = nil
  for _, players in pairs(told) do players[player] = nil end

  local at = nowMs()
  for key, record in pairs(owned) do
    if record.rider == player then
      record.rider = nil
      -- still travelling: send it back to the ground floor, which every configured elevator
      -- has and none of them gates, rather than leaving it parked wherever it was going
      if (record.rideEndsAtMs or 0) > at then
        record.rideEndsAtMs = nil
        local sent = pcall(Open77.elevators.goTo, record.id, 0,
          { travelMs = Config.TRAVEL_MS })
        Open77.log.info(("%s: rider %d left mid-travel (%s); recalled to floor 0 (%s)")
          :format(key, player, tostring(reason), tostring(sent)))
      end
    end
  end
end

--- An adoption that has not moved a cabin within this is released, so a key bound by a
--- bogus sighting heals: a sighting's hash cannot be verified before adoption.
local UNUSED_MS = 600000

--- How stale a rate-limit window must be before the sweep collects it. Far longer than the
--- widest window any caller asks for, so a live player's counter is never dropped early.
local WINDOW_GC_MS = 60000

CreateThread(function()
  while true do
    Wait(60000)
    -- pcall: a raise from a host call here would end the sweep for the life of the process
    local swept, failure = pcall(function()
      local at = nowMs()
      for key, record in pairs(owned) do
        if record.usedAtMs == nil and at - (record.atMs or at) > UNUSED_MS then
          release(key)
          Open77.log.warn(("%s released: adopted %d minutes ago and never used")
            :format(key, math.floor(UNUSED_MS / 60000)))
        end
      end
      -- `within` allocates a window lazily, so a packet arriving after a player has gone
      -- recreates the entry `Server.forget` just removed and nothing ever clears it again --
      -- and a recycled player id would inherit that stranded counter. Every window here is
      -- spent long before this runs, so dropping the expired ones costs nothing and bounds
      -- the tables by the number of players actually connected.
      for _, windows in ipairs({ sightWindows, requestWindows, logWindows }) do
        for player, window in pairs(windows) do
          if at - (window.started or at) > WINDOW_GC_MS then windows[player] = nil end
        end
      end
    end)
    if not swept then Open77.log.error("the adoption sweep failed: " .. tostring(failure)) end
  end
end)

AddEventHandler("onPlayerDisconnected", Server.forget)

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
    for key, elevator in pairs(Access.ELEVATORS) do
      if (filter == nil or filter == key) and type(elevator) == "table" then
        local record = owned[key]
        local lift = record and Open77.elevators.get(record.id) or nil
        report[#report + 1] = ("%s %s pos=%.2f,%.2f,%.2f floors=%d/%d id=%s %s"):format(
          key, tostring(elevator.LABEL), coordinate(elevator.X) or 0.0,
          coordinate(elevator.Y) or 0.0, coordinate(elevator.Z) or 0.0,
          type(elevator.FLOORS) == "table" and #elevator.FLOORS or 0,
          integer(elevator.FLOOR_COUNT) or 0,
          record and tostring(record.id) or "-",
          lift and ("phase=%s floor=%s flags=%s"):format(tostring(lift.phase),
            tostring(lift.activeFloor), tostring(lift.flags)) or "not adopted")
      end
    end
    -- sorted: `pairs` order would reshuffle the report between two runs
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
    -- said at boot as well as on demand: every one produces the same symptom, a dead button
    Open77.log.warn("config: " .. problems[index])
  end

  --- Warn once if the official package this one replaces is also running. Deferred to a
  --- thread: at load time a resource listed after this one is still `discovered`.
  CreateThread(function()
    local read, state = pcall(GetResourceState, "open77_elevators")
    local official = read and tostring(state or ""):lower() or ""
    if official ~= "running" and official ~= "starting" then return end
    Open77.log.warn("open77_elevators is running; a lift adopted by one is refused to the other")
    Open77.log.warn("  (the platform rejects a different owner), so whichever starts first owns")
    Open77.log.warn("  the cabin. Drop one from resources.load in server.jsonc.")
  end)

  Open77.log.info("ready")
end
