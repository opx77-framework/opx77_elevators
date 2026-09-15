---@meta

OpxElevators = {}
OpxElevators.Text = {}

--- The byte length of the first `maximum` characters, or the whole text when it is shorter.
--- Never more than `maximum * 4`, the widest a UTF-8 character can be.
---@param text string
---@param maximum integer characters
---@return integer bytes
function OpxElevators.Text.Span(text, maximum) end

--- Display text, cleaned rather than refused: control characters become spaces and the text is
--- cut to `maximum` characters. Answers nil for a value that is neither a string nor a number.
---@param value any
---@param maximum integer characters
---@param ellipsis? string appended when the text was cut
---@return string|nil
function OpxElevators.Text.Clean(value, maximum, ellipsis) end
