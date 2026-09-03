--- The client half: the link to opx77_core, the job gate, and the floor requests.

OpxElevators = OpxElevators or {}

local Config = OPX_ELEVATORS_CONFIG
local Access = OpxElevators.access
local State = OpxElevators.state

local Runtime = {}
OpxElevators.runtime = Runtime

local RESOURCE = GetCurrentResourceName()
local CORE = "opx77_core"

--- Milliseconds between two reports of the same unadopted lift.
local SIGHT_RETRY_MS = 5000

local sighted = {}
local running = false

--- The scheduler clock in milliseconds; `monotonic` answers SECONDS. A non-finite reading is
--- dropped rather than propagated: a NaN would expire nothing, an infinity everything.
---@return integer
local lastMs = 0
local function nowMs()
  local read, seconds = pcall(Open77.time.monotonic)
  if read and type(seconds) == "number" and seconds == seconds and
    seconds >= 0 and seconds < math.huge then
    lastMs = math.floor(seconds * 1000)
  end
  return lastMs
end

--- Tell anything that is listening what just happened.
---@param payload table
local function publish(payload)
  TriggerEvent(Config.EVENT, payload)
end

-- ---------------------------------------------------------------------------
-- The core
-- ---------------------------------------------------------------------------

--- One call to another resource's client export; coroutine only.
--- The third return says whether the target answered at all: a refusal is authoritative.
---@param resource string
---@param name string
---@return table|nil, string|nil, boolean
function Runtime.call(resource, name, ...)
  local reachable, state = pcall(GetResourceState, resource)
  if not reachable or state ~= "running" then return nil, "not_running", false end
  if type(Open77.exports) ~= "table" then return nil, "not_dispatched", false end
  -- the wrapping stops here: `await` below yields, and a yield is not safe under a pcall
  local dispatched, promise, reason = pcall(Open77.exports.call, resource, name, ...)
  if not dispatched then return nil, tostring(promise), false end
  if type(promise) ~= "table" or type(promise.await) ~= "function" then
    return nil, tostring(reason or "not_dispatched"), false
  end
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
    -- answered and refused: no character, so the gate closes now rather than ageing out
    if answered then State.forget() end
    return false, reason
  end
  State.adopt(result.data, nowMs())
  return true
end

AddEventHandler("opx77:client:onPlayerLoaded", function(playerData)
  State.adopt(playerData, nowMs())
end)

AddEventHandler("opx77:client:playerDataChanged", function(playerData)
  State.adopt(playerData, nowMs())
end)

AddEventHandler("opx77:client:onPlayerUnloaded", function()
  State.forget()
end)

-- ---------------------------------------------------------------------------
-- Finding the lifts
-- ---------------------------------------------------------------------------

--- The player's own position on the X/Y plane, or nil: the host answers three numbers, and
--- answers nothing at all before the world is up.
---@return number|nil x, number|nil y
local function playerXY()
  local character = Open77.character
  if type(character) ~= "table" or type(character.position) ~= "function" then
    return nil, nil
  end
  local read, x, y = pcall(character.position)
  -- `x ~= x` is the NaN check: NaN is unequal to itself, and passes every bound below it
  if not read or type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then
    return nil, nil
  end
  return x, y
end

--- One scan: report the configured lifts in range that the server has not adopted yet.
--- Only lifts matching a configured position are reported.
local function scan()
  local at = nowMs()
  local nearby = Open77.elevators.nearby(Config.SCAN_RADIUS)
  if type(nearby) ~= "table" then return end
  local playerX, playerY = playerXY()
  for index = 1, #nearby do
    local lift = nearby[index]
    local position = lift.position or {}
    local key = Access.locate(position.x, position.y, position.z, lift.engineEntity)
    if key ~= nil then
      State.sighted(key, lift, at, playerX, playerY)
      -- topology arrives asynchronously; a lift whose inspect has not answered waits a scan
      local ready = lift.floorCount ~= nil and lift.floorCount > 0 and
        lift.activeFloor ~= nil and lift.activeFloor >= 0
      local due = sighted[key] == nil or at - sighted[key] >= SIGHT_RETRY_MS
      if ready and not lift.managed and State.bound[key] == nil and due then
        sighted[key] = at
        local accepted, reason = TriggerServerEvent("opx77_elevators:sighted",
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
--- Ids change on every restart, which is why an elevator's durable name is its config key.
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

--- An elevator this resource owns has gone; the binding goes with it so the next scan
--- re-reports the lift.
RegisterNetEvent("opx77_elevators:released", function(key)
  if type(key) ~= "string" then return end
  State.bound[key] = nil
  sighted[key] = nil
end)

-- ---------------------------------------------------------------------------
-- The runtime API, called by client/exports.lua and client/panel.lua
-- ---------------------------------------------------------------------------

--- The Open77 id of a configured elevator, or nil.
--- Our server half's binding wins over a scan: `nearby` also reports lifts others adopted.
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

--- Select a floor. `ok = true` means asked: the server's verdict arrives on Config.EVENT.
---@param key string|nil
---@param index integer
---@param origin string|nil  "panel", or the invoking resource's name, for the event
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
    -- sighted but not adopted yet, or adopted by nobody
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

--- Would this player be allowed on this floor? Decides nothing and sends nothing.
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

  -- absent on a client with no world loaded, or a game build predating the elevator API
  if type(Open77.elevators) ~= "table" then
    Open77.log.error("native elevator API unavailable; nothing will be scanned")
    return
  end

  running = true
  CreateThread(function()
    -- the core may still be starting, so the loop simply keeps asking
    local nextPullAtMs = 0
    while running do
      -- pcall: a raise from a host call here would end scanning for the whole session
      local ticked, failure = pcall(function()
        local at = nowMs()
        if at >= nextPullAtMs then
          nextPullAtMs = at + Config.POLL_MS
          -- on a thread of its own: `pull` yields, so it cannot live under this pcall
          CreateThread(pull)
        end
        scan()
      end)
      if not ticked then
        Open77.log.warn("the elevator scan failed: " .. tostring(failure))
      end
      Wait(Config.SCAN_MS)
    end
  end)
end)

AddEventHandler("onClientResourceStop", function(name)
  if name ~= RESOURCE then return end
  running = false
  State.bound, State.seen, sighted = {}, {}, {}
end)
