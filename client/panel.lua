--- opx77_elevators -- the floor list, borrowed from opx77_menu.
--- This resource owns no WebUI surface. It asks for no UI permission, ships no
--- web files, and draws nothing: the panel is `opx77_menu`'s, opened through
--- its client export, and everything here is the spec handed to it.
--- OPTIONAL, never a dependency. A missing or stopped opx77_menu costs one
--- logged line and leaves the `floors` and `use` exports doing exactly what
--- they did before -- which is what a server with its own interaction UI wants
--- anyway. Set PANEL = "none" to skip this file's behaviour entirely.
--- The return channel is an EVENT, because that is the only channel there is:
--- the client runtime puts every export through a codec, so a callback cannot
--- be handed across a resource boundary. `opx77_menu` echoes each item's `data`
--- back in the payload, and that is where the elevator key and the floor index
--- ride.

OpxElevators = OpxElevators or {}

local Config = OPX_ELEVATORS_CONFIG
local Runtime = OpxElevators.runtime

local Panel = {}
OpxElevators.panel = Panel

local MENU = "opx77_menu"
local EVENT = "opx77_elevators:floor"

--- The elevator whose panel this file last opened, cleared by the answer to it.
--- It is a "we asked for this" marker, not a "the menu is on screen" one: the
--- list closes on select and the server's verdict arrives afterwards, which is
--- the case the status line exists for.
--- It exists because this file LISTENS on `Config.EVENT`, the resource's own
--- public answer channel, and the client runtime has a cross-resource event
--- bus: any resource on the player's machine can raise that name with any
--- payload. Without this, each one spawned a thread -- and a client resource is
--- allowed 1024 tasks, so a loop emptied the budget of this resource's client
--- half. Nothing here is a security boundary; the server re-derives every
--- clause of a request. It is about not being crashable by a peer.
local openFor = nil

--- Whether the panel can be drawn at all right now.
---@return boolean, string|nil
local function available()
  if GetResourceState(MENU) ~= "running" then return false, "menu_not_running" end
  return true
end

--- One call to opx77_menu. `Runtime.call` keeps both failure levels apart for the reason
--- client/main.lua explains -- except that here neither one is worth more than a log line:
--- a menu that did not open is a panel the player will press the button for again.
---@param name string
---@return table|nil, string|nil
local function menu(name, ...)
  return Runtime.call(MENU, name, ...)
end

--- Open the floor list for one elevator.
--- Answers before the menu exists: `await` is coroutine-only and an export
--- handler is not a coroutine, so this queues the work. `ok = true` means
--- "asked".
---@param key string|nil  defaults to the elevator the player is standing at
---@return table
function Panel.open(key)
  local ready, why = available()
  if not ready then return { ok = false, error = why } end

  local listing = Runtime.floors(key)
  if not listing.ok then return listing end
  local elevator = OpxElevators.access.elevator(listing.elevator)
  if #listing.floors == 0 then
    -- Every floor is gated and DENIED_FLOORS is "hidden". An empty menu is
    -- refused by opx77_menu anyway, and "nothing happened" is a worse answer
    -- to the player than a named one.
    return { ok = false, error = "no_floors_available", elevator = listing.elevator }
  end

  local rows = listing.floors
  local items = {}
  for index = 1, #rows do
    local row = rows[index]
    items[index] = {
      id = "floor_" .. tostring(row.index),
      label = row.label,
      -- The refusal is shown as the row's VALUE rather than hidden in a
      -- description: a greyed row with nothing beside it reads as broken, and
      -- "Arasaka Executive, on duty" reads as a door.
      value = (not row.ok) and (row.reason or "locked") or nil,
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

--- A row was selected. The payload is opx77_menu's; `data` is the table this
--- file put on the item, echoed back untouched.
AddEventHandler(EVENT, function(payload)
  if type(payload) ~= "table" or payload.action ~= "select" then return end
  local data = payload.data
  if type(data) ~= "table" then return end
  -- `openFor` is deliberately NOT cleared here. The list closes on select and
  -- the server's answer arrives long after -- writing the refusal under a menu
  -- that has already gone is the best-effort this file is built around. What
  -- clears it is the answer itself, below.
  Runtime.use(data.elevator, data.floor, "panel")
end)

--- Put an outcome under the list. Best-effort: the answer arrives long after the list closed
--- on select, and opx77_menu answers `no_menu_open` or `not_owner` as a value.
AddEventHandler(Config.EVENT, function(payload)
  if type(payload) ~= "table" or payload.ok == true then return end
  -- only for a panel THIS file opened, and only once: any resource on the machine can raise
  -- this name, and a thread per message drains the client's task budget
  if openFor == nil then return end
  if not available() then return end
  openFor = nil
  CreateThread(function()
    menu("status", payload.reason or payload.error or "refused", false)
  end)
end)
