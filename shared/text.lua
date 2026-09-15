--- @author DemiAutomatic
--- @file shared/text.lua
--- @description Character-aware text measuring and cleaning for both halves.

OpxElevators = OpxElevators or {}

OpxElevators.Text = {}
local Text = OpxElevators.Text

--- @author DemiAutomatic
--- @method OpxElevators.Text.Span
--- @description Byte length of the first maximum characters of a text.
--- @param text {string}
--- @param maximum {integer}
--- @returns {integer}
function OpxElevators.Text.Span(text, maximum)
	local size = #text
	local ceiling = maximum * 4
	if size > ceiling then size = ceiling end
	local characters, index = 0, 1
	while index <= size do
		local byte = text:byte(index)
		if byte < 0x80 or byte > 0xBF then
			if characters >= maximum then return index - 1 end
			characters = characters + 1
		end
		index = index + 1
	end
	return size
end

--- @author DemiAutomatic
--- @method OpxElevators.Text.Clean
--- @description Strips control characters and cuts display text to maximum characters.
--- @param value {any}
--- @param maximum {integer}
--- @param ellipsis {string|nil} Appended when the text was cut.
--- @returns {string|nil}
function OpxElevators.Text.Clean(value, maximum, ellipsis)
	if value == nil then return nil end
	if type(value) == 'number' then value = tostring(value) end
	if type(value) ~= 'string' then return nil end
	value = value:gsub('[%c]', ' ')
	if #value <= maximum then return value end
	local cut = Text.Span(value, maximum)
	if cut >= #value then return value end
	return value:sub(1, cut) .. (ellipsis or '')
end
