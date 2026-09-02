--- The floor list, drawn by opx77_menu. Optional: a missing menu costs one log line.

OpxElevators = OpxElevators or {}

local Config = OPX_ELEVATORS_CONFIG
local Runtime = OpxElevators.runtime

local Panel = {}
OpxElevators.panel = Panel

local MENU = "opx77_menu"
local EVENT = "opx77_elevators:floor"

--- The elevator whose panel this file last opened, cleared by the answer to it.
local openFor = nil

--- Refusal code -> catalogue key. A code with no entry reads as `elevators.refused`.
local REFUSAL = {
  no_elevator_nearby = "elevators.noElevatorNearby",
  no_such_elevator = "elevators.noSuchElevator",
  no_such_floor = "elevators.noSuchFloor",
  not_adopted = "elevators.notAdopted",
  floor_out_of_range = "elevators.floorOutOfRange",
  move_rejected = "elevators.moveRejected",
  not_sent = "elevators.notSent",
  no_character = "elevators.noCharacter",
  job_stale = "elevators.jobStale",
  job_required = "elevators.jobRequired",
  grade_too_low = "elevators.gradeTooLow",
  off_duty = "elevators.offDuty",
  no_position = "elevators.noPosition",
  wrong_bucket = "elevators.wrongBucket",
  too_far = "elevators.tooFar",
}

--- What a player is shown for a refusal: the operator's own REASON where there is one,
--- otherwise this resource's own wording for the code.
---@param payload table
---@return string
local function refusal(payload)
  local reason = payload.reason
  if type(reason) == "string" and reason ~= "" then return reason end
  return locale(REFUSAL[payload.error] or "elevators.refused")
end

--- Whether the panel can be drawn at all right now.
---@return boolean, string|nil
local function available()
  if GetResourceState(MENU) ~= "running" then return false, "menu_not_running" end
  return true
end

--- One call to opx77_menu.
---@param name string
---@return table|nil, string|nil
local function menu(name, ...)
  return Runtime.call(MENU, name, ...)
end

--- Open the floor list for one elevator. `ok = true` means asked: the menu opens on a thread.
---@param key string|nil  defaults to the elevator the player is standing at
---@return table
function Panel.open(key)
  local ready, why = available()
  if not ready then return { ok = false, error = why } end

  local listing = Runtime.floors(key)
  if not listing.ok then return listing end
  local elevator = OpxElevators.access.elevator(listing.elevator)
  if #listing.floors == 0 then
    -- every floor is gated and DENIED_FLOORS is "hidden"
    return { ok = false, error = "no_floors_available", elevator = listing.elevator }
  end

  local rows = listing.floors
  local items = {}
  for index = 1, #rows do
    local row = rows[index]
    items[index] = {
      id = "floor_" .. tostring(row.index),
      label = row.label,
      -- the refusal is the row's value: a greyed row with nothing beside it reads as broken
      value = (not row.ok) and (row.reason or locale("elevators.locked")) or nil,
      disabled = not row.ok,
      data = { elevator = listing.elevator, floor = row.index },
    }
  end

  openFor = listing.elevator
  CreateThread(function()
    local _, failure = menu("open", {
      id = "elevators." .. listing.elevator,
      title = elevator.LABEL or listing.elevator,
      event = EVENT,
      closeOnSelect = true,
      items = items,
    })
    if failure ~= nil then
      openFor = nil
      Open77.log.warn(("panel for %s did not open: %s"):format(listing.elevator, failure))
    end
  end)
  return { ok = true, queued = true, elevator = listing.elevator, floors = #items }
end

--- A row was selected; `data` is the table this file put on the item, echoed back untouched.
AddEventHandler(EVENT, function(payload)
  if type(payload) ~= "table" or payload.action ~= "select" then return end
  local data = payload.data
  if type(data) ~= "table" then return end
  -- `openFor` is cleared by the answer below, not here
  Runtime.use(data.elevator, data.floor, "panel")
end)

--- Put an outcome under the list. Best-effort: the list has already closed on select.
AddEventHandler(Config.EVENT, function(payload)
  if type(payload) ~= "table" or payload.ok == true then return end
  -- only for a panel this file opened, and only once: any resource may raise this name
  if openFor == nil then return end
  if not available() then return end
  openFor = nil
  CreateThread(function()
    menu("status", refusal(payload), false)
  end)
end)
