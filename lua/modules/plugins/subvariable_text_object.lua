--- Define text objects for underscore and camelCase sub-variable segments.

local M = {}

---@alias _my.subvariable.Kind "inner" | "around"

---@class _my.subvariable.Range
---@field start_column integer The 0-or-more inclusive start column.
---@field end_column integer The 0-or-more inclusive end column.
---@field replacement string? Replacement text for the removed range.

local _OPERATOR_KIND = "inner"

--- Check whether `character` is a variable-name character.
---
---@param character string The character to inspect.
---@return boolean # Whether it belongs to a variable name.
local function _is_variable_character(character)
    return character:match("^[%w_]$") ~= nil
end

--- Check whether `character` is lowercase.
---
---@param character string The character to inspect.
---@return boolean # Whether it is lowercase ASCII.
local function _is_lower(character)
    return character:match("^%l$") ~= nil
end

--- Check whether `character` is uppercase.
---
---@param character string The character to inspect.
---@return boolean # Whether it is uppercase ASCII.
local function _is_upper(character)
    return character:match("^%u$") ~= nil
end

--- Get the variable token around `cursor_column`.
---
---@param line string The current line.
---@param cursor_column integer The 0-or-more cursor column.
---@return integer # The 0-or-more token start column.
---@return integer # The 0-or-more token end column.
---@return string # The token text.
local function _get_token(line, cursor_column)
    local start_column = cursor_column
    local end_column = cursor_column

    while start_column > 0 and _is_variable_character(line:sub(start_column, start_column)) do
        start_column = start_column - 1
    end

    while end_column < #line and _is_variable_character(line:sub(end_column + 2, end_column + 2)) do
        end_column = end_column + 1
    end

    return start_column, end_column, line:sub(start_column + 1, end_column + 1)
end

--- Split a token into underscore-delimited parts.
---
---@param token string The token to split.
---@return _my.subvariable.Range[] # Ranges relative to `token`.
local function _get_underscore_ranges(token)
    ---@type _my.subvariable.Range[]
    local ranges = {}
    local start_column = 0

    for column = 1, #token + 1 do
        if column == #token + 1 or token:sub(column, column) == "_" then
            if column - 1 > start_column then
                table.insert(ranges, {
                    start_column = start_column,
                    end_column = column - 2,
                })
            end

            start_column = column
        end
    end

    return ranges
end

--- Split a token into camelCase parts.
---
---@param token string The token to split.
---@return _my.subvariable.Range[] # Ranges relative to `token`.
local function _get_camel_ranges(token)
    ---@type _my.subvariable.Range[]
    local ranges = {}
    local start_column = 0

    for column = 2, #token do
        local previous = token:sub(column - 1, column - 1)
        local current = token:sub(column, column)

        if _is_lower(previous) and _is_upper(current) then
            table.insert(ranges, {
                start_column = start_column,
                end_column = column - 2,
            })
            start_column = column - 1
        end
    end

    table.insert(ranges, {
        start_column = start_column,
        end_column = #token - 1,
    })

    return ranges
end

--- Find the segment range containing `token_column`.
---
---@param ranges _my.subvariable.Range[] Candidate ranges.
---@param token_column integer The 0-or-more column within the token.
---@return _my.subvariable.Range # The matching range.
local function _find_range(ranges, token_column)
    for _, range in ipairs(ranges) do
        if token_column >= range.start_column and token_column <= range.end_column then
            return range
        end
    end

    return ranges[1]
end

--- Expand an underscore inner range for the around text object.
---
---@param range _my.subvariable.Range The inner range.
---@param token string The token text.
---@return _my.subvariable.Range # The around range.
local function _get_around_underscore_range(range, token)
    ---@type _my.subvariable.Range
    local around = {
        start_column = range.start_column,
        end_column = range.end_column,
    }

    if around.start_column > 0 and token:sub(around.start_column, around.start_column) == "_" then
        around.start_column = around.start_column - 1
    elseif token:sub(around.end_column + 2, around.end_column + 2) == "_" then
        around.end_column = around.end_column + 1
    end

    return around
end

--- Expand a camelCase range for the around text object.
---
---@param range _my.subvariable.Range The inner range.
---@param token string The token text.
---@return _my.subvariable.Range # The around range.
local function _get_around_camel_range(range, token)
    if range.start_column ~= 0 then
        return range
    end

    local next_character = token:sub(range.end_column + 2, range.end_column + 2)

    if next_character == "" then
        return range
    end

    return {
        start_column = range.start_column,
        end_column = range.end_column + 1,
        replacement = next_character:lower(),
    }
end

--- Get the sub-variable range for a line and cursor.
---
---@param line string The current line.
---@param cursor_column integer The 0-or-more cursor column.
---@param kind _my.subvariable.Kind The text-object variant.
---@return _my.subvariable.Range # The absolute range.
function M.get_range(line, cursor_column, kind)
    local token_start, _, token = _get_token(line, cursor_column)
    local token_column = cursor_column - token_start
    local has_underscore = token:find("_", 1, true) ~= nil
    local ranges = has_underscore and _get_underscore_ranges(token) or _get_camel_ranges(token)
    local range = _find_range(ranges, token_column)

    if kind == "around" then
        if has_underscore then
            range = _get_around_underscore_range(range, token)
        else
            range = _get_around_camel_range(range, token)
        end
    end

    return {
        start_column = token_start + range.start_column,
        end_column = token_start + range.end_column,
        replacement = range.replacement,
    }
end

--- Select the sub-variable text object under the cursor.
---
---@param kind _my.subvariable.Kind The text-object variant.
function M.select(kind)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local range = M.get_range(line, cursor[2], kind)

    require("modules.features.core_editor_setup").set_text_object_marks(
        cursor[1],
        range.start_column,
        cursor[1],
        range.end_column
    )
end

--- Delete the sub-variable under the cursor.
---
---@param kind _my.subvariable.Kind The text-object variant.
function M.delete(kind)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local range = M.get_range(line, cursor[2], kind)
    local replacement = range.replacement or ""
    local updated = line:sub(1, range.start_column) .. replacement .. line:sub(range.end_column + 2)

    vim.api.nvim_set_current_line(updated)
    vim.api.nvim_win_set_cursor(0, { cursor[1], range.start_column })
end

--- Run an operator over the sub-variable under the cursor.
---
---@param _ string The ignored operator type.
function M.operatorfunc(_)
    M.delete(_OPERATOR_KIND)
end

--- Start a sub-variable delete operator.
---
---@param kind _my.subvariable.Kind The text-object variant.
---@return string # The operator-pending key sequence.
function M.start_delete(kind)
    _OPERATOR_KIND = kind
    vim.go.operatorfunc = "v:lua.require'modules.plugins.subvariable_text_object'.operatorfunc"

    return "g@l"
end

vim.keymap.set({ "o", "x" }, "iv", function()
    M.select("inner")
end, { desc = "Select the inner sub-variable under the cursor." })

vim.keymap.set({ "o", "x" }, "av", function()
    M.select("around")
end, { desc = "Select around the sub-variable under the cursor." })

vim.keymap.set("n", "div", function()
    return M.start_delete("inner")
end, { expr = true, desc = "Delete the inner sub-variable under the cursor." })

vim.keymap.set("n", "dav", function()
    return M.start_delete("around")
end, { expr = true, desc = "Delete around the sub-variable under the cursor." })

return M
