---@meta
--- Type annotations for opx77_elevators. Never loaded at runtime.

---@alias ElevatorKey string
---| # the durable name of an elevator, the key in this resource's config.lua ELEVATORS.
---| # NOT the Open77 id: that is assigned at adoption and changes every restart.

---@alias FloorIndex integer  the NATIVE floor index, 0-based

--- Why a floor was refused. The four job codes are decided on the CLIENT and are hints.
---@alias ElevatorError
---| "export_call_required" no invoking resource, so the call came from inside
---| "no_elevator_nearby"   not standing at a configured elevator
---| "no_such_elevator"     no such key in config.lua
---| "no_such_floor"        that index is not a floor this elevator declares
---| "not_adopted"          sighted, but this resource does not own it yet
---| "no_character"         opx77_core has no character, or never answered
---| "job_stale"            the last snapshot is older than JOB_MAX_AGE_MS
---| "job_required"         the character holds none of the floor's jobs
---| "grade_too_low"        it holds one, below the minimum grade
---| "off_duty"             it holds one, at grade, and is not clocked in
---| "menu_not_running"     opx77_menu is not running
---| "no_floors_available"  everything is gated and DENIED_FLOORS is "hidden"
---| "rate_limited"         too many requests in REQUEST_WINDOW_MS   (server)
---| "no_position"          no fresh replicated position snapshot     (server)
---| "wrong_bucket"         the player is in another routing bucket   (server)
---| "too_far"              further than USE_RADIUS from the shaft    (server)
---| "floor_out_of_range"   past the native device's floor count      (server)
---| "move_rejected"        `goTo` refused                            (server)
---| "adopt_refused"        `adopt` answered nil                      (server)
---| "adopt_raised"         `adopt` raised                            (server)
---| "not_sent"             the net event was not accepted            (client)

--- One entry of config.lua's ELEVATORS.
---@class ElevatorSpec
---@field LABEL string
---@field X number
---@field Y number
---@field Z number
---@field BUCKET integer|nil   routing bucket, default 0
---@field ENTITY string|nil    native LiftDevice hash, "0x…16 hex". OPAQUE
---@field FLOOR_COUNT integer  the engine's floor count, not #FLOORS
---@field FLOORS FloorSpec[]

--- One stop this resource offers. A floor with no JOBS is public.
---@class FloorSpec
---@field INDEX FloorIndex
---@field LABEL string
---@field JOBS table<string, integer>|nil  job name -> minimum grade level
---@field ON_DUTY boolean|nil              also require the character be clocked in
---@field REASON string|nil                shown beside a refused row

--- What `client/state.lua` keeps of a character; `atMs` is what makes it expire.
---@class JobSnapshot
---@field job PlayerJob|nil                the primary job, from PlayerData.job
---@field jobs table<string, integer>|nil  every membership, from PlayerData.jobs
---@field atMs integer                     when it was read, from the client clock

--- opx77_core's shape, reproduced only as far as this resource reads it.
---@class PlayerJob
---@field name string
---@field label string
---@field onDuty boolean
---@field grade { name: string, level: integer }

--- One row of a floor list. `ok` is what the panel greys on and nothing more.
---@class FloorRow
---@field index FloorIndex
---@field label string
---@field ok boolean
---@field error ElevatorError|nil
---@field reason string|nil

--- Every export answers a table carrying `ok` and never raises.
---@class ElevatorResponse
---@field ok boolean
---@field error ElevatorError|nil

---@class FloorListing : ElevatorResponse
---@field elevator ElevatorKey|nil
---@field floors FloorRow[]|nil

--- What `use` answers. `ok = true` means asked: the server's verdict arrives on the event.
---@class FloorDecision : ElevatorResponse
---@field elevator ElevatorKey|nil
---@field floor FloorIndex|nil
---@field label string|nil
---@field reason string|nil
---@field queued boolean|nil
---@field source "panel"|"export"|"server"|nil

--- What `OpxElevators.runtime.report` answers.
---@class ElevatorClientState : ElevatorResponse
---@field job string|nil       the primary job's name, or nil
---@field grade integer|nil
---@field onDuty boolean
---@field fresh boolean        whether the gate still trusts the snapshot
---@field ageMs integer|nil    how old it is
---@field seen integer         configured lifts in range
---@field bound integer        of those, ones this resource owns
---@field nearest ElevatorKey|nil

--- One entry of `Open77.elevators.nearby(radius)`, on the CLIENT.
---@class NativeLift
---@field engineEntity string      opaque 64-bit hash as "0x…"
---@field controllerEntity string
---@field position { x: number, y: number, z: number }
---@field distance number
---@field floorCount integer|nil   nil until the native device's inspect answers
---@field activeFloor integer|nil  nil until the native device's inspect answers
---@field managed boolean          already adopted by some resource
---@field id integer|nil           the Open77 id, only when managed

--- One entry of `Open77.elevators.all(bucket)`, on the SERVER. Position is FLAT here,
--- where the client's `nearby` nests it under `position`.
---@class ServerElevator
---@field id integer
---@field engineEntity string
---@field bucket integer
---@field floorCount integer
---@field x number
---@field y number
---@field z number
---@field phase string
---@field activeFloor integer
---@field targetFloor integer
---@field flags integer
---@field revision integer
