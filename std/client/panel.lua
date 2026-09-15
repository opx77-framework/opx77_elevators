---@meta

OpxElevators.Panel = {}

--- Opens the floor list for one elevator through opx77_menu; defaults to the elevator the
--- player is standing at. `ok = true` means asked: the menu opens on a thread. Refuses
--- `menu_not_running`, `no_floors_available`, or any `Runtime.Floors` refusal.
---@param key ElevatorKey|nil
---@return table
function OpxElevators.Panel.Open(key) end
