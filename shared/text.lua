--- Text helpers for both halves. Lua patterns are byte-oriented, so everything here that
--- measures or slices text says which unit it works in.

OpxElevators = OpxElevators or {}

local Text = {}
OpxElevators.Text = Text

--- The byte length of the first `maximum` characters, or the whole text when it is shorter.
---@param text string
---@param maximum integer
---@return integer
function Text.span(text, maximum)
  local characters, index, size = 0, 1, #text
  while index <= size do
    local byte = text:byte(index)
    -- 0x80..0xBF is a UTF-8 continuation byte, so it starts no character of its own
    if byte < 0x80 or byte > 0xBF then
      if characters >= maximum then return index - 1 end
      characters = characters + 1
    end
    index = index + 1
  end
  return size
end

--- Display text, cleaned rather than refused: control characters out, cut to `maximum`
--- characters. Answers nil for a value that is neither a string nor a number.
---@param value any
---@param maximum integer
---@param ellipsis? string appended when the text was cut
---@return string|nil
function Text.clean(value, maximum, ellipsis)
  if value == nil then return nil end
  if type(value) == "number" then value = tostring(value) end
  if type(value) ~= "string" then return nil end
  value = value:gsub("[%c]", " ")
  -- `#value` counts bytes and `maximum` counts characters: fewer bytes needs no measuring
  if #value <= maximum then return value end
  local cut = Text.span(value, maximum)
  if cut >= #value then return value end
  return value:sub(1, cut) .. (ellipsis or "")
end
