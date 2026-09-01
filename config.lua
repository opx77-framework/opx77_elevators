-- Read by both halves and shipped to every client: nothing here is secret. Job names must
-- exist in opx77_core/data/jobs.lua.
--
-- The job requirements below are a CLIENT-SIDE hint. This resource's server VM cannot ask
-- opx77_core for a job -- the runtime installs no cross-resource event bus -- so it proves
-- the elevator, the floor, the position, the bucket and the rate, and not the job. See README.

OPX_ELEVATORS_CONFIG = {
  DENIED_FLOORS = "shown", -- floors the player cannot reach: "shown" greyed, or "hidden"
  MEMBERSHIP = "primary", -- "primary" reads the job being worked, "any" the whole membership map
  JOB_MAX_AGE_MS = 60000, -- past this age every gated floor closes; public floors never do
  POLL_MS = 15000, -- how often to re-read the character from opx77_core
  SCAN_MS = 2000, -- how often the client looks for native lifts
  EVENT = "opx77:elevators", -- raised on the client after every decision
  MATCH_RADIUS = 6.0, -- how close a native lift must be to a declared position to be it, in metres
  USE_RADIUS = 4.0, -- how close the player must be to use the panel, in metres
  SCAN_RADIUS = 40.0, -- how far a client's sighting report is believed, in metres
  TRAVEL_MS = 8000, -- how long the cabin takes to travel
  REQUEST_WINDOW_MS = 10000, -- the rate limit window, per player
  REQUESTS_PER_WINDOW = 6, -- floor requests one player may make in that window
  COMMAND = "opx77.elevators.where", -- ACL-gated diagnostic command, or false for none

  ELEVATORS = { -- placeholder positions; probe real ones with open77:elevators:nearby
    arasaka_tower = {
      LABEL = "ARASAKA TOWER",
      X = -1521.40, Y = 892.75, Z = 42.10,
      BUCKET = 0, -- an elevator in a bucket is invisible to players outside it
      FLOOR_COUNT = 12, -- the native device's floor count, not the length of FLOORS
      FLOORS = {
        { INDEX = 0, LABEL = "Plaza" }, -- INDEX is the native floor index, 0-based
        { INDEX = 2, LABEL = "Reception" },
        { INDEX = 5, LABEL = "Analytics", JOBS = { arasaka = 0 }, -- name -> minimum grade
          REASON = "Arasaka staff only" }, -- shown beside a refused row
        { INDEX = 8, LABEL = "Counterintel", JOBS = { arasaka = 2, militech = 3 },
          REASON = "Arasaka Counterintel" },
        { INDEX = 11, LABEL = "Executive Suite", JOBS = { arasaka = 3 },
          ON_DUTY = true, REASON = "Arasaka Executive, on duty" },
      },
    },

    ncpd_watson = {
      LABEL = "NCPD WATSON",
      X = -652.10, Y = 1394.55, Z = 12.40,
      BUCKET = 0,
      FLOOR_COUNT = 5,
      FLOORS = {
        { INDEX = 0, LABEL = "Street" },
        { INDEX = 1, LABEL = "Front Desk" },
        { INDEX = 2, LABEL = "Bullpen", JOBS = { ncpd = 0, maxtac = 0 },
          REASON = "NCPD only" },
        { INDEX = 3, LABEL = "Holding", JOBS = { ncpd = 1, maxtac = 0 },
          ON_DUTY = true, REASON = "NCPD Officer, on duty" },
        { INDEX = 4, LABEL = "Evidence", JOBS = { ncpd = 2 },
          ON_DUTY = true, REASON = "NCPD Detective, on duty" },
      },
    },

    vik_clinic = {
      LABEL = "VIKTOR VEKTOR",
      X = -1244.80, Y = 402.35, Z = 8.90,
      FLOOR_COUNT = 3,
      FLOORS = {
        { INDEX = 0, LABEL = "Street" },
        { INDEX = 1, LABEL = "Clinic" },
        { INDEX = 2, LABEL = "Back Room", JOBS = { ripperdoc = 1, trauma = 2 },
          REASON = "Ripperdoc back room" },
      },
    },

    afterlife = {
      LABEL = "AFTERLIFE",
      X = -1876.20, Y = 233.05, Z = 6.10,
      FLOOR_COUNT = 3,
      FLOORS = {
        { INDEX = 0, LABEL = "Main Floor" },
        { INDEX = 1, LABEL = "Booths", JOBS = { fixer = 0, merc = 2 },
          REASON = "Fixers and Edgerunners" },
        { INDEX = 2, LABEL = "Cellar", JOBS = { fixer = 2 },
          REASON = "Fixer, made" },
      },
    },
  },
}
