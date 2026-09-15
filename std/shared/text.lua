---@meta

OpxElevators = {}
OpxElevators.Text = {}

--- Display text, cleaned rather than refused: control characters become spaces and the text is
--- cut to `maximum` UTF-8 characters, measuring no more than `maximum * 4` bytes. Answers nil for a value that is neither a string nor a number.
---@param value any
---@param maximum integer characters
---@param ellipsis? string appended when the text was cut
---@return string|nil
function OpxElevators.Text.Clean(value, maximum, ellipsis) end
