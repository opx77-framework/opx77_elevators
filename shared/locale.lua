--- @author DemiAutomatic
--- @file shared/locale.lua
--- @description Locale catalogues, lookup with fallback and the global locale shorthand.

OpxElevators = OpxElevators or {}

--- @author DemiAutomatic
--- @type {table<string, table<string, string>>}
--- @description Registered catalogues, keyed by language code then key.
local catalogs = {}

--- @author DemiAutomatic
--- @type {string}
--- @description The language player-facing text is currently read from.
local active = 'en'

--- @author DemiAutomatic
--- @type {string}
--- @description The language every lookup falls back to.
local FALLBACK = 'en'

OpxElevators.Locale = {}
local Locale = OpxElevators.Locale

--- @author DemiAutomatic
--- @method interpolate
--- @description Fills named placeholders, leaving placeholders without a value as written.
--- @param text {string}
--- @param params {table<string, string|number>|nil}
--- @returns {string}
local function interpolate(text, params)
	if not params then return text end
	return (text:gsub('{(%w+)}', function(name)
		local value = params[name]
		return value ~= nil and tostring(value) or ('{' .. name .. '}')
	end))
end

--- @author DemiAutomatic
--- @method OpxElevators.Locale.register
--- @description Merges a language's strings into its catalogue.
--- @param code {string}
--- @param strings {table<string, string>}
function OpxElevators.Locale.register(code, strings)
	local catalog = catalogs[code]
	if not catalog then
		catalog = {}
		catalogs[code] = catalog
	end
	for key, text in pairs(strings) do catalog[key] = text end
end

--- @author DemiAutomatic
--- @method OpxElevators.Locale.Set
--- @description Selects the catalogue player-facing text is read from.
--- @param code {string}
--- @returns {boolean}
function OpxElevators.Locale.Set(code)
	if type(code) ~= 'string' or code == '' then return false end
	active = code
	return true
end

--- @author DemiAutomatic
--- @method OpxElevators.Locale.Current
--- @description Answers the language code currently selected.
--- @returns {string}
function OpxElevators.Locale.Current()
	return active
end

--- @author DemiAutomatic
--- @method OpxElevators.Locale.Exists
--- @description Whether the active or fallback catalogue defines a key.
--- @param key {string}
--- @returns {boolean}
function OpxElevators.Locale.Exists(key)
	return (catalogs[active] and catalogs[active][key] ~= nil)
		or (catalogs[FALLBACK] and catalogs[FALLBACK][key] ~= nil)
end

--- @author DemiAutomatic
--- @method OpxElevators.Locale.Get
--- @description Resolves a key through the active catalogue, the fallback, then itself.
--- @param key {string}
--- @param params {table<string, string|number>|nil}
--- @returns {string}
function OpxElevators.Locale.Get(key, params)
	local catalog = catalogs[active]
	local text = (catalog and catalog[key])
		or (catalogs[FALLBACK] and catalogs[FALLBACK][key])
		or key
	return interpolate(text, params)
end

--- @author DemiAutomatic
--- @type {fun(key: string, params: table|nil): string}
--- @description Global shorthand every file below the catalogues calls.
locale = OpxElevators.Locale.Get

Locale.Set(OPX_ELEVATORS_CONFIG and OPX_ELEVATORS_CONFIG.LOCALE)
