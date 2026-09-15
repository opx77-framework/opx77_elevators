---@meta

OpxElevators.Runtime = {}

--- One call to another resource's client export; coroutine only. Checks the three levels
--- (not dispatched, call error, refusal: any answer whose `ok` is not `true`). The third return
--- says whether the target answered at all: a refusal is authoritative, a call that never
--- landed is not.
---@param resource string
---@param name string
---@param ... any
---@return table|nil result
---@return string|nil error
---@return boolean answered
function OpxElevators.Runtime.Call(resource, name, ...) end

--- The Open77 id of a configured elevator: this resource's binding first, then a managed
--- sighting. Nil when neither exists.
---@param key ElevatorKey
---@return integer|nil
function OpxElevators.Runtime.ElevatorId(key) end

--- Which configured elevator the player is standing at, or nil.
---@return ElevatorKey|nil
function OpxElevators.Runtime.Nearest() end

--- The floor list to draw for this player; defaults to the nearest elevator.
---@param key ElevatorKey|nil
---@return FloorListing
function OpxElevators.Runtime.Floors(key) end

--- Selects a floor: checks it locally, then sends `opx77_elevators:request`. `ok = true` means
--- asked; the server's verdict arrives on `OPX_ELEVATORS_CONFIG.EVENT`. A local refusal is
--- published on that event too.
---@param key ElevatorKey|nil
---@param index integer
---@param origin string|nil "panel", or the invoking resource's name
---@return FloorDecision
function OpxElevators.Runtime.Use(key, index, origin) end

--- Would this player be allowed on this floor? Decides nothing and sends nothing.
---@param key ElevatorKey|nil
---@param index integer
---@return FloorDecision
function OpxElevators.Runtime.Check(key, index) end

--- What this client knows, at the current time.
---@return ElevatorClientState
function OpxElevators.Runtime.Report() end
