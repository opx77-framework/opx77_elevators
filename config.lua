--- @author DemiAutomatic
--- @file config.lua
--- @description Operator configuration for the gate, the scan and every elevator.
--- @field LOCALE {string} Catalogue code in locales/ player-facing text is read from.
--- @field DENIED_FLOORS {string} shown greys a refused floor, hidden leaves it out.
--- @field MEMBERSHIP {string} primary reads the worked job, any every membership.
--- @field JOB_MAX_AGE_MS {integer} Past this snapshot age every gated floor closes.
--- @field POLL_MS {integer} How often the character is re-read from opx77_core.
--- @field SCAN_MS {integer} How often the client looks for native lifts.
--- @field EVENT {string} Local client event raised after every decision.
--- @field MATCH_RADIUS {number} Metres across the ground between a lift and its elevator.
--- @field USE_RADIUS {number} Metres across the ground a player may work the panel from.
--- @field SCAN_RADIUS {number} Metres a client's sighting report is believed within.
--- @field TRAVEL_MS {integer} How long the cabin takes to travel.
--- @field REQUEST_WINDOW_MS {integer} The per-player rate limit window.
--- @field REQUESTS_PER_WINDOW {integer} Floor requests one player may make per window.
--- @field COMMAND {string|false} ACL-gated diagnostic command; false registers none.
--- @field ELEVATORS {table} Elevator key -> definition; README lists the fields.

OPX_ELEVATORS_CONFIG = {
	LOCALE = 'en',
	DENIED_FLOORS = 'shown',
	MEMBERSHIP = 'primary',
	JOB_MAX_AGE_MS = 60000,
	POLL_MS = 15000,
	SCAN_MS = 2000,
	EVENT = 'opx77:elevators',
	MATCH_RADIUS = 6.0,
	USE_RADIUS = 4.0,
	SCAN_RADIUS = 40.0,
	TRAVEL_MS = 8000,
	REQUEST_WINDOW_MS = 10000,
	REQUESTS_PER_WINDOW = 6,
	COMMAND = 'opx77.elevators.where',

	ELEVATORS = {
		arasaka_tower = {
			LABEL = 'ARASAKA TOWER',
			X = -1521.40, Y = 892.75, Z = 42.10,
			BUCKET = 0,
			FLOOR_COUNT = 12,
			FLOORS = {
				{ INDEX = 0, LABEL = 'Plaza' },
				{ INDEX = 2, LABEL = 'Reception' },
				{ INDEX = 5, LABEL = 'Analytics', JOBS = { arasaka = 0 },
					REASON = 'Arasaka staff only' },
				{ INDEX = 8, LABEL = 'Counterintel', JOBS = { arasaka = 2, militech = 3 },
					REASON = 'Arasaka Counterintel' },
				{ INDEX = 11, LABEL = 'Executive Suite', JOBS = { arasaka = 3 },
					ON_DUTY = true, REASON = 'Arasaka Executive, on duty' },
			},
		},

		ncpd_watson = {
			LABEL = 'NCPD WATSON',
			X = -652.10, Y = 1394.55, Z = 12.40,
			BUCKET = 0,
			FLOOR_COUNT = 5,
			FLOORS = {
				{ INDEX = 0, LABEL = 'Street' },
				{ INDEX = 1, LABEL = 'Front Desk' },
				{ INDEX = 2, LABEL = 'Bullpen', JOBS = { ncpd = 0, maxtac = 0 },
					REASON = 'NCPD only' },
				{ INDEX = 3, LABEL = 'Holding', JOBS = { ncpd = 1, maxtac = 0 },
					ON_DUTY = true, REASON = 'NCPD Officer, on duty' },
				{ INDEX = 4, LABEL = 'Evidence', JOBS = { ncpd = 2 },
					ON_DUTY = true, REASON = 'NCPD Detective, on duty' },
			},
		},

		vik_clinic = {
			LABEL = 'VIKTOR VEKTOR',
			X = -1244.80, Y = 402.35, Z = 8.90,
			FLOOR_COUNT = 3,
			FLOORS = {
				{ INDEX = 0, LABEL = 'Street' },
				{ INDEX = 1, LABEL = 'Clinic' },
				{ INDEX = 2, LABEL = 'Back Room', JOBS = { ripperdoc = 1, trauma = 2 },
					REASON = 'Ripperdoc back room' },
			},
		},

		afterlife = {
			LABEL = 'AFTERLIFE',
			X = -1876.20, Y = 233.05, Z = 6.10,
			FLOOR_COUNT = 3,
			FLOORS = {
				{ INDEX = 0, LABEL = 'Main Floor' },
				{ INDEX = 1, LABEL = 'Booths', JOBS = { fixer = 0, merc = 2 },
					REASON = 'Fixers and Edgerunners' },
				{ INDEX = 2, LABEL = 'Cellar', JOBS = { fixer = 2 },
					REASON = 'Fixer, made' },
			},
		},
	},
}
