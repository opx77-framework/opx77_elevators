---@meta

OpxElevators.State = {}

--- The character's job snapshot, or nil when the core has never answered or said there is no
--- character.
---@type JobSnapshot|nil
OpxElevators.State.snapshot = nil

--- Elevator key -> `{ id, floorCount, atMs }`, filled by the server's `bound` event.
---@type table<ElevatorKey, table>
OpxElevators.State.bound = {}

--- Elevator key -> what the last scan saw of its lift (`reach`, `distance`, `id`, `managed`,
--- `atMs` are read).
---@type table<ElevatorKey, table>
OpxElevators.State.seen = {}

--- Keeps the job fields of an opx77_core PlayerData snapshot, stamped with `nowMs`.
---@param playerData table|nil
---@param nowMs integer
function OpxElevators.State.Adopt(playerData, nowMs) end

--- Drops the snapshot: the core answered that there is no character.
function OpxElevators.State.Forget() end

--- Records what one scan saw of a configured lift.
---@param key ElevatorKey
---@param lift NativeLift
---@param nowMs integer
---@param playerX number|nil the player's own X, nil when the host would not answer
---@param playerY number|nil
function OpxElevators.State.Sighted(key, lift, nowMs, playerX, playerY) end

--- The elevator the player is standing at: the nearest current sighting within `USE_RADIUS`,
--- ranked across the ground, falling back to the host's 3D distance.
---@param nowMs integer
---@return ElevatorKey|nil
function OpxElevators.State.Nearest(nowMs) end

--- The floor rows for this player at one elevator.
---@param key ElevatorKey
---@param nowMs integer
---@return FloorRow[]
function OpxElevators.State.Rows(key, nowMs) end

--- What the `state` export publishes, without `ok`.
---@param nowMs integer
---@return ElevatorClientState
function OpxElevators.State.Report(nowMs) end
