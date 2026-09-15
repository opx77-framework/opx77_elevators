---@meta

OpxElevators.Server = {}

--- Takes ownership of a native lift a client has just reported, or re-claims one the host
--- already holds (after a restart of this resource). Answers a value, never raises:
--- `{ ok = true, id, already? }` or `{ ok = false, error = "wrong_place"|"already_owned"|
--- "adopt_raised"|"adopt_refused", reason? }`.
---@param key ElevatorKey
---@param entity string the engine hash off the wire
---@param x number
---@param y number
---@param z number
---@param bucket integer the elevator's configured bucket
---@param floorCount integer the configured floor count when declared
---@param activeFloor integer
---@return table
function OpxElevators.Server.Adopt(key, entity, x, y, z, bucket, floorCount, activeFloor) end

--- Everything the server can prove about one floor request (rate, elevator, floor, adoption,
--- native floor count, position, bucket, reach), then `goTo`. The job is not checked here.
---@param player integer
---@param key any
---@param index any
---@return table `{ ok = true, id, floor }` or `{ ok = false, error = ElevatorError }`
function OpxElevators.Server.Request(player, key, index) end

--- Forgets a departing player's rate-limit windows and audience membership, and recalls to
--- floor 0 a cabin they left in motion.
---@param playerId any a string, like every host event argument
---@param reason? any `connection_closed`, or the text a disconnect, kick or ban carried
function OpxElevators.Server.Forget(playerId, reason) end
