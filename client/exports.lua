--- The public export surface. Every call answers a table carrying `ok` and never raises;
--- `error` is one of the codes in types.lua.

local Runtime = OpxElevators.Runtime
local Panel = OpxElevators.Panel

---@param ok boolean
---@param values table|nil
---@return table
local function response(ok, values)
	values = values or {}
	values.ok = ok == true
	return values
end

--- Who is calling, asked of the host: a caller cannot claim to be another resource.
---@return string|nil
local function caller()
	local owner = GetInvokingResource()
	if type(owner) ~= 'string' or owner == '' or #owner > 64 or
		owner:match('^[%w_%-%.]+$') == nil then
		return nil
	end
	return owner
end

--- The refusal every export starts with.
---@return table|nil
local function nobody()
	if caller() == nil then return response(false, { error = 'export_call_required' }) end
	return nil
end

--- The floor list at an elevator, each row with whether the player may take it and why not.
---@param elevator string|nil  defaults to the nearest
---@return FloorListing
exports('floors', function(elevator)
	return nobody() or Runtime.Floors(elevator)
end)

--- Would this floor be allowed? Sends nothing and moves nothing.
---@param elevator string|nil
---@param floor integer
---@return FloorDecision
exports('isFloorAllowed', function(elevator, floor)
	return nobody() or Runtime.Check(elevator, floor)
end)

--- Ask for a floor. `ok = true` means asked; the verdict arrives on
--- `OPX_ELEVATORS_CONFIG.EVENT`.
---@param elevator string|nil
---@param floor integer
---@return FloorDecision
exports('requestFloor', function(elevator, floor)
	local owner = caller()
	if owner == nil then return response(false, { error = 'export_call_required' }) end
	return Runtime.Use(elevator, floor, owner)
end)

--- Open the floor list through opx77_menu.
---@param elevator string|nil
---@return FloorDecision
exports('openPanel', function(elevator)
	return nobody() or Panel.Open(elevator)
end)

--- Which configured elevator the player is standing at, or `ok = false`.
---@return ElevatorResponse
exports('nearestElevator', function()
	local gone = nobody()
	if gone then return gone end
	local key = Runtime.Nearest()
	if key == nil then return response(false, { error = 'no_elevator_nearby' }) end
	return response(true, { elevator = key, id = Runtime.ElevatorId(key) })
end)

--- What this client knows: the job, how old the reading is, whether the gate still trusts
--- it, and how many lifts are in range and bound.
---@return ElevatorClientState
exports('state', function()
	local gone = nobody()
	if gone then return gone end
	local report = Runtime.Report()
	report.ok = true
	return report
end)
