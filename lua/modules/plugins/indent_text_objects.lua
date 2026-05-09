--- Define indentation-aware text objects.

local M = {}

---@alias _my.indent_text_object.Mode "strict" | "ignore_blank"

---@class _my.text_object.Range
---@field start_line integer The first 1-or-more line in the text object.
---@field start_column integer The 0-or-more start column.
---@field end_line integer The last 1-or-more line in the text object.
---@field end_column integer The inclusive 0-or-more end column.

--- Check whether `line` is empty or all whitespace.
---
---@param line string The line to inspect.
---@return boolean # Whether the line is blank.
local function _is_blank(line)
    return line:match("^%s*$") ~= nil
end

--- Get the first non-whitespace column in `line`.
---
---@param line string The line to inspect.
---@return integer # The 0-or-more column.
local function _get_first_text_column(line)
    local column = line:find("%S")

    if column == nil then
        return 0
    end

    return column - 1
end

--- Get the final non-whitespace column in `line`.
---
---@param line string The line to inspect.
---@return integer # The inclusive 0-or-more column.
local function _get_last_text_column(line)
    local trimmed = line:gsub("%s+$", "")

    return math.max(#trimmed - 1, 0)
end

--- Get a buffer line.
---
---@param buffer integer The buffer to read from.
---@param line_number integer The 1-or-more line number.
---@return string # The line text, or an empty string.
local function _get_line(buffer, line_number)
    return vim.api.nvim_buf_get_lines(buffer, line_number - 1, line_number, false)[1] or ""
end

--- Get a line's indentation column.
---
---@param line string The line to inspect.
---@return integer # The 0-or-more indentation width.
local function _get_indent(line)
    return _get_first_text_column(line)
end

--- Check whether `line` should be part of the requested indent range.
---
---@param line string The candidate line.
---@param indent integer The target indentation.
---@param mode _my.indent_text_object.Mode The selection behavior.
---@return boolean # Whether the line belongs in the range.
local function _is_matching_line(line, indent, mode)
    if _is_blank(line) then
        return mode == "ignore_blank"
    end

    return _get_indent(line) == indent
end

--- Find the start line for an indent text object.
---
---@param buffer integer The buffer to inspect.
---@param cursor_line integer The 1-or-more cursor line.
---@param indent integer The target indentation.
---@param mode _my.indent_text_object.Mode The selection behavior.
---@return integer # The first 1-or-more selected line.
local function _find_start_line(buffer, cursor_line, indent, mode)
    local line_number = cursor_line

    while line_number > 1 do
        local previous_line = _get_line(buffer, line_number - 1)

        if not _is_matching_line(previous_line, indent, mode) then
            break
        end

        line_number = line_number - 1
    end

    return line_number
end

--- Find the end line for an indent text object.
---
---@param buffer integer The buffer to inspect.
---@param cursor_line integer The 1-or-more cursor line.
---@param indent integer The target indentation.
---@param mode _my.indent_text_object.Mode The selection behavior.
---@return integer # The last 1-or-more selected line.
local function _find_end_line(buffer, cursor_line, indent, mode)
    local line_number = cursor_line
    local line_count = vim.api.nvim_buf_line_count(buffer)

    while line_number < line_count do
        local next_line = _get_line(buffer, line_number + 1)

        if not _is_matching_line(next_line, indent, mode) then
            break
        end

        line_number = line_number + 1
    end

    return line_number
end

--- Trim blank boundary lines from an indent range.
---
---@param buffer integer The buffer to inspect.
---@param start_line integer The first selected line.
---@param end_line integer The last selected line.
---@return integer # The first nonblank selected line.
---@return integer # The last nonblank selected line.
local function _trim_blank_edges(buffer, start_line, end_line)
    while start_line < end_line and _is_blank(_get_line(buffer, start_line)) do
        start_line = start_line + 1
    end

    while end_line > start_line and _is_blank(_get_line(buffer, end_line)) do
        end_line = end_line - 1
    end

    return start_line, end_line
end

--- Get the range for the indentation text object under `cursor_line`.
---
---@param buffer integer The buffer to inspect.
---@param cursor_line integer The 1-or-more cursor line.
---@param mode _my.indent_text_object.Mode The selection behavior.
---@return _my.text_object.Range # The text object range.
function M.get_range(buffer, cursor_line, mode)
    local cursor_text = _get_line(buffer, cursor_line)
    local indent = _get_indent(cursor_text)
    local start_line = _find_start_line(buffer, cursor_line, indent, mode)
    local end_line = _find_end_line(buffer, cursor_line, indent, mode)

    start_line, end_line = _trim_blank_edges(buffer, start_line, end_line)

    local start_text = _get_line(buffer, start_line)
    local end_text = _get_line(buffer, end_line)

    return {
        start_line = start_line,
        start_column = _get_first_text_column(start_text),
        end_line = end_line,
        end_column = _get_last_text_column(end_text),
    }
end

--- Select the indentation text object under the cursor.
---
---@param mode _my.indent_text_object.Mode The selection behavior.
function M.select(mode)
    local buffer = vim.api.nvim_get_current_buf()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local range = M.get_range(buffer, cursor_line, mode)

    require("modules.features.core_editor_setup").set_text_object_marks(
        range.start_line,
        range.start_column,
        range.end_line,
        range.end_column
    )
end

vim.keymap.set({ "o", "x" }, "ii", function()
    M.select("strict")
end, { desc = "Select same-indentation text until blank or different indentation lines." })

vim.keymap.set({ "o", "x" }, "iI", function()
    M.select("ignore_blank")
end, { desc = "Select same-indentation text across blank lines." })

return M
