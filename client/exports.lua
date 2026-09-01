--- opx77_elevators -- the public surface.
--- Client-side, because that is the only side exports exist on: the server
--- runtime installs none. A server resource that wants to open an elevator
--- panel sends a net event to its OWN client half, and that half calls this.
--- Every call answers a table carrying `ok` and never raises, which is the
--- platform's convention and opx77_core's. `error` is a stable snake_case code
--- meant for branching, and the codes are the ones in types.lua:
---   export_call_required called from inside this resource, or without the
---                        export machinery -- there is no invoking resource
---   no_elevator_nearby   the player is not standing at a configured elevator
---   no_such_elevator     that key is not in config.lua
---   no_such_floor        that index is not a floor this elevator declares
---   not_adopted          sighted, but the server has not taken ownership yet
---   no_character         opx77_core has no character, or has never answered
---   job_stale            the last snapshot is older than JOB_MAX_AGE_MS
---   job_required         the character holds none of the floor's jobs
---   grade_too_low        it holds one, below the minimum grade
---   off_duty             it holds one, at grade, and is not clocked in
---   menu_not_running     opx77_menu is not running
---   no_floors_available  every floor is gated and DENIED_FLOORS is "hidden"
--- The three job codes and `job_stale` are HINTS. They say what this client
--- believes, which is what the player sees; they are not what a server would
--- swear to. See README, "What the job check is worth".

local Runtime = OpxElevators.runtime
local Panel = OpxElevators.panel

---@param ok boolean
---@param values table|nil
---@return table
local function response(ok, values)
  values = values or {}
  values.ok = ok == true
  return values
end

--- Who is calling.
--- From the host, never from an argument: a caller cannot claim to be another
--- resource. Two things hang on it. Nothing inside this VM should be reaching
--- the public surface -- `Runtime` and `Panel` are right there -- so a call
--- with no invoking resource is a call that went somewhere it did not mean to.
--- And `use` carries the name into the answer event, where a listener that
--- draws its own panel needs to know whether the press it is seeing was its
--- own.
---@return string|nil
local function caller()
  local owner = GetInvokingResource()
  if type(owner) ~= "string" or owner == "" or #owner > 64 or
    owner:match("^[%w_%-%.]+$") == nil then
    return nil
  end
  return owner
end

--- The refusal every export starts with.
---@return table|nil
local function nobody()
  if caller() == nil then return response(false, { error = "export_call_required" }) end
  return nil
end

--- The floor list for a player standing at an elevator: every floor they may
--- select, plus -- under DENIED_FLOORS = "shown" -- the ones they may not, each
--- carrying its reason.
---@param elevator string|nil  defaults to the nearest
---@return table
exports("floors", function(elevator)
  return nobody() or Runtime.floors(elevator)
end)

--- Would this floor be allowed? Sends nothing and moves nothing.
--- For a caller drawing its own panel: this is the same call the built-in one
--- makes, so a row greyed here is greyed for the same reason.
---@param elevator string|nil
---@param floor integer
---@return table
exports("check", function(elevator, floor)
  return nobody() or Runtime.check(elevator, floor)
end)

--- Select a floor.
--- `ok = true` means ASKED: the server has still
--- to agree, and its verdict arrives on `OPX_ELEVATORS_CONFIG.EVENT`. An export
--- handler is not a coroutine, so nothing here could wait for it.
---@param elevator string|nil
---@param floor integer
---@return table
exports("use", function(elevator, floor)
  local owner = caller()
  if owner == nil then return response(false, { error = "export_call_required" }) end
  return Runtime.use(elevator, floor, owner)
end)

--- Open the floor list through opx77_menu.
--- The one call an interaction resource needs: bind it to a prompt on the
--- elevator's call button and this resource does the rest.
---@param elevator string|nil
---@return table
exports("panel", function(elevator)
  return nobody() or Panel.open(elevator)
end)

--- Which configured elevator the player is standing at, or `ok = false`.
---@return table
exports("nearest", function()
  local gone = nobody()
  if gone then return gone end
  local key = Runtime.nearest()
  if key == nil then return response(false, { error = "no_elevator_nearby" }) end
  return response(true, { elevator = key, id = Runtime.elevatorId(key) })
end)

--- What this client knows: the job it read, how old that reading is, whether
--- the gate still trusts it, how many lifts are in range and how many are
--- bound.
--- `fresh = false` with a job present is the state worth recognising -- the
--- core has been unreachable for longer than JOB_MAX_AGE_MS, so every gated
--- floor is closed even though a job is on screen.
---@return table
exports("state", function()
  local gone = nobody()
  if gone then return gone end
  local report = Runtime.report()
  report.ok = true
  return report
end)
