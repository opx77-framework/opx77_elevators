--- opx77_elevators -- the client half: the link to opx77_core, and the panel's
--- decisions.
--- WHY THE JOB CHECK IS HERE, AND WHAT IT IS WORTH
--- The job lives in opx77_core. The server runtime installs no `exports` and no
--- cross-resource event bus, so this resource's SERVER half cannot ask the core anything --
--- not the job, not the grade, not whether a character is loaded. The CLIENT runtime can, and
--- does, right here.
---
--- That makes the check a HINT, and the platform's conventions say so: "re-derive client
--- conditions on the server: they are hints". A modified client skips everything in this
--- file. Every adopted elevator is locked, so the host refuses a request sent straight off a
--- client and our server half is the only way the cabin moves -- and it checks everything a
--- server CAN: our elevator, a floor this config lists, the player standing there, the right
--- bucket, the rate. Not the job. So a modified client reaches the configured floors of an
--- elevator it is standing at, and not the whole shaft.
--- Neither is a security boundary for the JOB. Do not build anything on this
--- gate that money or a body count depends on -- README, "What the job check is
--- worth", says what to do instead.
--- HOW A SATELLITE REACHES THE CORE
--- `Open77.exports.call` is asynchronous, always: it answers a promise, and
--- `await` only works inside a `CreateThread`. Failure has TWO levels --
--- `nil, reason` when the call cannot be dispatched, then `result, callError`
--- when it was dispatched and failed. They mean opposite things. A call the
--- core ANSWERED and refused is authoritative: there is no character, and the
--- job goes. A call that never landed says nothing -- the core is restarting --
--- so the snapshot is left alone to AGE OUT under JOB_MAX_AGE_MS instead of
--- being thrown away on our own problem, and instead of being trusted forever.

OpxElevators = OpxElevators or {}

local Config = OPX_ELEVATORS_CONFIG
local Access = OpxElevators.access
local State = OpxElevators.state

local Runtime = {}
OpxElevators.runtime = Runtime

local RESOURCE = GetCurrentResourceName()
local CORE = "opx77_core"

--- Milliseconds between two reports of the same unadopted lift.
--- The server ignores a lift it has already adopted, but a client that has just
--- streamed in sends before it has been told, and five seconds is what the
--- shipped reference resource waits for the same reason.
local SIGHT_RETRY_MS = 5000

local sighted = {}
local running = false

---@return integer
local function nowMs()
  -- SECONDS. Every shipped client resource treats `monotonic` as seconds, and
  -- the platform's own API reference says milliseconds; the shipped code wins,
  -- because it runs. Mixing the two gives a timer that fires a thousand times
  -- too early, which is the kind of bug only production finds.
  return math.floor(Open77.time.monotonic() * 1000)
end

--- Tell anything that is listening what just happened.
---@param payload table
local function publish(payload)
  TriggerEvent(Config.EVENT, payload)
end

-- ---------------------------------------------------------------------------
-- The core
-- ---------------------------------------------------------------------------

--- One call to another resource's client export, with both failure levels kept apart.
--- The third return is the one that matters: ANSWERED means the target ran the export and
--- refused, which is authoritative. Not answered means the call never got there.
---
--- Published on Runtime because client/panel.lua asks opx77_menu in exactly this shape, and
--- two copies of a two-level failure contract is two places for one of them to drift.
--- Coroutine only: `await` has no synchronous form.
---@param resource string
---@param name string
---@return table|nil, string|nil, boolean
function Runtime.call(resource, name, ...)
  if GetResourceState(resource) ~= "running" then return nil, "not_running", false end
  local promise, reason = Open77.exports.call(resource, name, ...)
  if not promise then return nil, tostring(reason or "not_dispatched"), false end
  local result, callError = promise:await()
  if callError then return nil, tostring(callError), false end
  if type(result) ~= "table" then return nil, "malformed_answer", true end
  if result.ok == false then return nil, tostring(result.error or "refused"), true end
  return result, nil, true
end

--- Re-read the character. Coroutine only.
---@return boolean, string|nil
local function pull()
  local result, reason, answered = Runtime.call(CORE, "GetPlayerData")
  if result == nil then
    -- Answered and refused: no character. The gate closes now rather than in a
    -- minute, because we have been told rather than left guessing.
    if answered then State.forget() end
    return false, reason
  end
  State.adopt(result.data, nowMs())
  return true
end

AddEventHandler("opx77:client:playerLoaded", function(playerData)
  State.adopt(playerData, nowMs())
end)

AddEventHandler("opx77:client:playerDataChanged", function(playerData)
  -- Every change, including the one that matters: a promotion, a demotion, a
  -- job swapped at a terminal. The gate reads the snapshot on every press, so
  -- there is nothing to invalidate -- the next press is already using this.
  State.adopt(playerData, nowMs())
end)

AddEventHandler("opx77:client:playerUnloaded", function()
  State.forget()
end)

-- ---------------------------------------------------------------------------
-- Finding the lifts
-- ---------------------------------------------------------------------------

--- One scan: what is streamed, which of it is ours, and what the server has not
--- adopted yet.
--- Only lifts that match a CONFIGURED position are reported. The shipped
--- reference resource adopts every native lift it sees, which is the right
--- behaviour for a reference and the wrong one here: this resource is a door
--- policy, and adopting a lift nobody wrote a policy for would take ownership
--- of a cabin it has nothing to say about.
local function scan()
  local at = nowMs()
  -- Type-checked rather than trusted: this thread has no pcall around it, so a host call
  -- answering something other than a list would end scanning for the whole session.
  local nearby = Open77.elevators.nearby(Config.SCAN_RADIUS)
  if type(nearby) ~= "table" then return end
  for index = 1, #nearby do
    local lift = nearby[index]
    local position = lift.position or {}
    local key = Access.locate(position.x, position.y, position.z, lift.engineEntity)
    if key ~= nil then
      State.sighted(key, lift, at)
      -- Topology arrives asynchronously from the native LiftDevice. Never
      -- invent a floor count: a lift whose inspect has not answered yet is
      -- reported on the next scan instead.
      local ready = lift.floorCount ~= nil and lift.floorCount > 0 and
        lift.activeFloor ~= nil and lift.activeFloor >= 0
      local due = sighted[key] == nil or at - sighted[key] >= SIGHT_RETRY_MS
      if ready and not lift.managed and State.bound[key] == nil and due then
        sighted[key] = at
        local accepted, reason = TriggerServerEvent("opx77_elevators:sighted", key,
          lift.engineEntity, position.x, position.y, position.z,
          lift.floorCount, lift.activeFloor)
        if not accepted then
          Open77.log.warn(("sighting of %s was not sent: %s"):format(key, tostring(reason)))
        end
      end
    end
  end
end

--- The server has adopted one, and this is the id it got.
--- Ids are assigned at adoption and change on every restart, which is why the
--- durable name of an elevator is its config KEY and never its id.
RegisterNetEvent("opx77_elevators:bound", function(key, id, floorCount)
  if type(key) ~= "string" or Access.elevator(key) == nil then return end
  State.bound[key] = { id = id, floorCount = floorCount, atMs = nowMs() }
  sighted[key] = nil
end)

--- The server refused, or accepted, a floor request.
RegisterNetEvent("opx77_elevators:answer", function(key, index, ok, failure)
  publish({
    elevator = key,
    floor = index,
    ok = ok == true,
    error = ok ~= true and tostring(failure or "refused") or nil,
    source = "server",
  })
  if ok ~= true then
    Open77.log.info(("%s floor %s refused: %s"):format(
      tostring(key), tostring(index), tostring(failure)))
  end
end)

--- An elevator this resource owns has gone -- the server released it, or the
--- host removed it. The binding goes with it, so the next scan re-reports the
--- lift rather than sending requests for an id nobody owns.
RegisterNetEvent("opx77_elevators:released", function(key)
  if type(key) ~= "string" then return end
  State.bound[key] = nil
  sighted[key] = nil
end)

-- ---------------------------------------------------------------------------
-- The runtime API, called by client/exports.lua and client/panel.lua
-- ---------------------------------------------------------------------------

--- The Open77 id of a configured elevator, or nil.
--- The binding from our own server half is preferred over what a scan saw:
--- both come from the host, but the binding says "we own this one", and
--- `nearby` would happily report a lift some other resource adopted.
---@param key string
---@return integer|nil
function Runtime.elevatorId(key)
  local bound = State.bound[key]
  if bound ~= nil then return bound.id end
  local seen = State.seen[key]
  if seen ~= nil and seen.managed then return seen.id end
  return nil
end

--- Which elevator the player is standing at, or nil.
---@return string|nil
function Runtime.nearest()
  return State.nearest(nowMs())
end

--- The floor list to draw, for this player, at this elevator.
---@param key string|nil  defaults to the nearest
---@return table
function Runtime.floors(key)
  key = key or Runtime.nearest()
  if key == nil then return { ok = false, error = "no_elevator_nearby" } end
  if Access.elevator(key) == nil then return { ok = false, error = "no_such_elevator" } end
  return { ok = true, elevator = key, floors = State.rows(key, nowMs()) }
end

--- Select a floor.
--- Answers what is known NOW, which is "asked": the
--- server has still to agree, and its answer arrives as `opx77_elevators:answer`
--- and on Config.EVENT. `ok = true` never means the cabin moved -- an export
--- handler is not a coroutine, so there is nothing here that could wait for it.
---@param key string|nil
---@param index integer
---@param origin string|nil  "panel" | "export", for the published event
---@return table
function Runtime.use(key, index, origin)
  key = key or Runtime.nearest()
  local result = Runtime.check(key, index)
  result.source = origin or "export"
  if not result.ok then
    publish(result)
    return result
  end

  local id = Runtime.elevatorId(key)
  if id == nil then
    -- Sighted but not adopted yet, or adopted by nobody. Nothing to press.
    result = { ok = false, error = "not_adopted", elevator = key, floor = index,
                source = result.source }
    publish(result)
    return result
  end

  local accepted, reason = TriggerServerEvent("opx77_elevators:request", key, index)
  if not accepted then
    result = { ok = false, error = tostring(reason or "not_sent"), elevator = key,
                floor = index, source = result.source }
    publish(result)
    return result
  end
  result.queued = true
  return result
end

--- Would this player be allowed on this floor? Decides nothing and sends
--- nothing -- it is the same call `use` makes, exposed so a caller can grey a
--- row of its own UI the way the panel does.
---@param key string|nil
---@param index integer
---@return table
function Runtime.check(key, index)
  key = key or Runtime.nearest()
  if key == nil then return { ok = false, error = "no_elevator_nearby" } end
  local elevator = Access.elevator(key)
  if elevator == nil then return { ok = false, error = "no_such_elevator", elevator = key } end
  local floor = Access.floor(key, index)
  if floor == nil then
    return { ok = false, error = "no_such_floor", elevator = key, floor = index }
  end
  local ok, failure = Access.evaluate(floor, State.snapshot, nowMs())
  return {
    ok = ok,
    error = failure,
    elevator = key,
    floor = index,
    label = floor.LABEL,
    reason = (not ok) and floor.REASON or nil,
  }
end

---@return table
function Runtime.report()
  return State.report(nowMs())
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
AddEventHandler("onClientResourceStart", function(name)
  if name ~= RESOURCE then return end

  -- The native table is absent on a client that has not loaded the world yet,
  -- and on one whose game build predates the elevator API. Saying so once beats
  -- a stack trace per scan.
  if type(Open77.elevators) ~= "table" then
    Open77.log.error("native elevator API unavailable; nothing will be scanned")
    return
  end

  running = true
  CreateThread(function()
    -- The core may still be starting. "Not running yet" is not an error, so the
    -- loop simply keeps asking: manifest order ACROSS resources is not ours to
    -- decide.
    local nextPullAtMs = 0
    while running do
      local at = nowMs()
      if at >= nextPullAtMs then
        nextPullAtMs = at + Config.POLL_MS
        pull()
      end
      scan()
      Wait(Config.SCAN_MS)
    end
  end)
end)

AddEventHandler("onClientResourceStop", function(name)
  if name ~= RESOURCE then return end
  running = false
  State.bound, State.seen, sighted = {}, {}, {}
end)
