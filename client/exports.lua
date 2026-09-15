--- @author DemiAutomatic
--- @file client/exports.lua
--- @description The six client exports, each answering a table carrying ok.

local Runtime = OpxElevators.Runtime
local Panel = OpxElevators.Panel

--- @author DemiAutomatic
--- @method response
--- @description Stamps ok on an answer table.
--- @param ok {boolean}
--- @param values {table|nil}
--- @returns {table}
local function response(ok, values)
	values = values or {}
	values.ok = ok == true
	return values
end

--- @author DemiAutomatic
--- @method caller
--- @description Reads the invoking resource from the host, or nil.
--- @returns {string|nil}
local function caller()
	local owner = GetInvokingResource()
	if type(owner) ~= 'string' or owner == '' or #owner > 64 or
		owner:match('^[%w_%-%.]+$') == nil then
		return nil
	end
	return owner
end

--- @author DemiAutomatic
--- @method nobody
--- @description Answers the refusal for a call with no invoking resource.
--- @returns {table|nil}
local function nobody()
	if caller() == nil then return response(false, { error = 'export_call_required' }) end
	return nil
end

--- @author DemiAutomatic
--- @export floors
--- @description Answers every floor at an elevator with the player's access.
--- @param elevator {string|nil}
--- @returns {FloorListing}
exports('floors', function(elevator)
	return nobody() or Runtime.Floors(elevator)
end)

--- @author DemiAutomatic
--- @export isFloorAllowed
--- @description Answers whether a floor would be allowed, sending nothing.
--- @param elevator {string|nil}
--- @param floor {integer}
--- @returns {FloorDecision}
exports('isFloorAllowed', function(elevator, floor)
	return nobody() or Runtime.Check(elevator, floor)
end)

--- @author DemiAutomatic
--- @export requestFloor
--- @description Asks for a floor; the verdict arrives on the configured event.
--- @param elevator {string|nil}
--- @param floor {integer}
--- @returns {FloorDecision}
exports('requestFloor', function(elevator, floor)
	local owner = caller()
	if owner == nil then return response(false, { error = 'export_call_required' }) end
	return Runtime.Use(elevator, floor, owner)
end)

--- @author DemiAutomatic
--- @export openPanel
--- @description Opens the floor list through opx77_menu.
--- @param elevator {string|nil}
--- @returns {FloorDecision}
exports('openPanel', function(elevator)
	return nobody() or Panel.Open(elevator)
end)

--- @author DemiAutomatic
--- @export nearestElevator
--- @description Answers the configured elevator the player is standing at.
--- @returns {ElevatorResponse}
exports('nearestElevator', function()
	local gone = nobody()
	if gone then return gone end
	local key = Runtime.Nearest()
	if key == nil then return response(false, { error = 'no_elevator_nearby' }) end
	return response(true, { elevator = key, id = Runtime.ElevatorId(key) })
end)

--- @author DemiAutomatic
--- @export state
--- @description Answers what this client knows: job, snapshot age, lifts in range.
--- @returns {ElevatorClientState}
exports('state', function()
	local gone = nobody()
	if gone then return gone end
	local report = Runtime.Report()
	report.ok = true
	return report
end)
