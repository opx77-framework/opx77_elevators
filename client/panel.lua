--- @author DemiAutomatic
--- @file client/panel.lua
--- @description The floor list drawn through opx77_menu, which is optional.

OpxElevators = OpxElevators or {}

local Config = OPX_ELEVATORS_CONFIG
local Runtime = OpxElevators.Runtime

OpxElevators.Panel = {}
local Panel = OpxElevators.Panel

--- @author DemiAutomatic
--- @type {string}
--- @description The resource that draws the floor list.
local MENU = 'opx77_menu'

--- @author DemiAutomatic
--- @type {string}
--- @description Local event opx77_menu raises when a row is selected.
local EVENT = 'opx77_elevators:floor'

--- @author DemiAutomatic
--- @type {string|nil}
--- @description Elevator whose panel this file last opened, until answered.
local openFor = nil

--- @author DemiAutomatic
--- @type {table<string, string>}
--- @description Catalogue key a player reads for each refusal code.
local REFUSAL = {
	no_elevator_nearby = 'elevators.noElevatorNearby',
	no_such_elevator = 'elevators.noSuchElevator',
	no_such_floor = 'elevators.noSuchFloor',
	not_adopted = 'elevators.notAdopted',
	floor_out_of_range = 'elevators.floorOutOfRange',
	move_rejected = 'elevators.moveRejected',
	not_sent = 'elevators.notSent',
	no_character = 'elevators.noCharacter',
	job_stale = 'elevators.jobStale',
	job_required = 'elevators.jobRequired',
	grade_too_low = 'elevators.gradeTooLow',
	off_duty = 'elevators.offDuty',
	no_position = 'elevators.noPosition',
	wrong_bucket = 'elevators.wrongBucket',
	too_far = 'elevators.tooFar',
}

--- @author DemiAutomatic
--- @method refusal
--- @description Answers the operator's REASON, or this resource's wording for the code.
--- @param payload {table}
--- @returns {string}
local function refusal(payload)
	local reason = payload.reason
	if type(reason) == 'string' and reason ~= '' then return reason end
	return locale(REFUSAL[payload.error] or 'elevators.refused')
end

--- @author DemiAutomatic
--- @method available
--- @description Whether opx77_menu is running to draw the panel.
--- @returns {boolean, string|nil}
local function available()
	if GetResourceState(MENU) ~= 'running' then return false, 'menu_not_running' end
	return true
end

--- @author DemiAutomatic
--- @method menu
--- @description Calls one opx77_menu export.
--- @param name {string}
--- @returns {table|nil, string|nil}
local function menu(name, ...)
	return Runtime.Call(MENU, name, ...)
end

--- @author DemiAutomatic
--- @method OpxElevators.Panel.Open
--- @description Opens an elevator's floor list through opx77_menu on a thread.
--- @param key {string|nil}
--- @returns {table}
function OpxElevators.Panel.Open(key)
	local ready, why = available()
	if not ready then return { ok = false, error = why } end

	local listing = Runtime.Floors(key)
	if not listing.ok then return listing end
	local elevator = OpxElevators.Access.Elevator(listing.elevator)
	if #listing.floors == 0 then
		return { ok = false, error = 'no_floors_available', elevator = listing.elevator }
	end

	local rows = listing.floors
	local items = {}
	for index = 1, #rows do
		local row = rows[index]
		items[index] = {
			id = 'floor_' .. tostring(row.index),
			label = row.label,
			value = (not row.ok) and (row.reason or locale('elevators.locked')) or nil,
			disabled = not row.ok,
			data = { elevator = listing.elevator, floor = row.index },
		}
	end

	openFor = listing.elevator
	CreateThread(function()
		local _, failure = menu('open', {
			id = 'elevators.' .. listing.elevator,
			title = elevator.LABEL or listing.elevator,
			event = EVENT,
			closeOnSelect = true,
			items = items,
		})
		if failure ~= nil then
			openFor = nil
			Open77.log.warn(('panel for %s did not open: %s'):format(listing.elevator, failure))
		end
	end)
	return { ok = true, queued = true, elevator = listing.elevator, floors = #items }
end

--- @author DemiAutomatic
--- @event opx77_elevators:floor
--- @description Requests the floor of a row selected in the panel.
--- @param payload {table}
AddEventHandler(EVENT, function(payload)
	if type(payload) ~= 'table' or payload.action ~= 'select' then return end
	local data = payload.data
	if type(data) ~= 'table' then return end
	Runtime.Use(data.elevator, data.floor, 'panel')
end)

--- @author DemiAutomatic
--- @event opx77:elevators
--- @description Shows a refusal under the panel this file opened, once.
--- @param payload {table}
AddEventHandler(Config.EVENT, function(payload)
	if type(payload) ~= 'table' or payload.ok == true then return end
	if openFor == nil then return end
	if not available() then return end
	openFor = nil
	CreateThread(function()
		menu('setStatus', refusal(payload), false)
	end)
end)
