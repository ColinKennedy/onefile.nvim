--- Define text objects for function-call arguments inside parentheses.

local M = {}

---@class _my.argument_text_object.Position
---@field line integer The 1-or-more line number.
---@field column integer The 0-or-more column.

---@class _my.argument_text_object.Range
---@field start_line integer The first 1-or-more line in the range.
---@field start_column integer The inclusive 0-or-more start column.
---@field end_line integer The last 1-or-more line in the range.
---@field end_column integer The inclusive 0-or-more end column.
---@field replacement string The replacement text.
---@field delete_linewise boolean? Whether to delete whole buffer lines.

--- Compare two positions.
---
---@param left _my.argument_text_object.Position The left position.
---@param right _my.argument_text_object.Position The right position.
---@return integer # -1 if left is before right, 0 if equal, 1 if after.
local function _compare_positions(left, right)
    if left.line < right.line then
        return -1
    end

    if left.line > right.line then
        return 1
    end

    if left.column < right.column then
        return -1
    end

    if left.column > right.column then
        return 1
    end

    return 0
end

--- Check whether `position` is inside `range`.
---
---@param position _my.argument_text_object.Position The position to inspect.
---@param range _my.argument_text_object.Range The range to compare against.
---@return boolean # Whether the position is in the range.
local function _contains_position(position, range)
    return _compare_positions(position, { line = range.start_line, column = range.start_column }) >= 0
        and _compare_positions(position, { line = range.end_line, column = range.end_column }) <= 0
end

--- Get all buffer lines.
---
---@param buffer integer The buffer to inspect.
---@return string[] # The buffer contents.
local function _get_lines(buffer)
    return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

--- Get a line's text.
---
---@param lines string[] Buffer lines.
---@param line_number integer The 1-or-more line number.
---@return string # The line text.
local function _get_line(lines, line_number)
    return lines[line_number] or ""
end

--- Find the opening parenthesis that contains `cursor`.
---
---@param lines string[] Buffer lines.
---@param cursor _my.argument_text_object.Position The cursor position.
---@return _my.argument_text_object.Position? # The opening parenthesis position.
local function _find_open_paren(lines, cursor)
    local depth = 0

    for line_number = cursor.line, 1, -1 do
        local line = _get_line(lines, line_number)
        local start_column = line_number == cursor.line and cursor.column + 1 or #line

        for column = start_column, 1, -1 do
            local character = line:sub(column, column)

            if character == ")" then
                depth = depth + 1
            elseif character == "(" then
                if depth == 0 then
                    return { line = line_number, column = column - 1 }
                end

                depth = depth - 1
            end
        end
    end

    return nil
end

--- Find the closing parenthesis for `open`.
---
---@param lines string[] Buffer lines.
---@param open _my.argument_text_object.Position The opening parenthesis position.
---@return _my.argument_text_object.Position? # The closing parenthesis position.
local function _find_close_paren(lines, open)
    local depth = 0

    for line_number = open.line, #lines do
        local line = _get_line(lines, line_number)
        local start_column = line_number == open.line and open.column + 2 or 1

        for column = start_column, #line do
            local character = line:sub(column, column)

            if character == "(" then
                depth = depth + 1
            elseif character == ")" then
                if depth == 0 then
                    return { line = line_number, column = column - 1 }
                end

                depth = depth - 1
            end
        end
    end

    return nil
end

--- Return a position advanced by one column.
---
---@param position _my.argument_text_object.Position The original position.
---@return _my.argument_text_object.Position # The next position.
local function _next_column(position)
    return { line = position.line, column = position.column + 1 }
end

--- Build an argument range from two positions.
---
---@param start_position _my.argument_text_object.Position The start position.
---@param end_position _my.argument_text_object.Position The end position.
---@return _my.argument_text_object.Range # The argument range.
local function _make_range(start_position, end_position)
    return {
        start_line = start_position.line,
        start_column = start_position.column,
        end_line = end_position.line,
        end_column = end_position.column,
        replacement = "",
    }
end

--- Split the contents of a parenthesized expression into top-level arguments.
---
---@param lines string[] Buffer lines.
---@param open _my.argument_text_object.Position The opening parenthesis.
---@param close _my.argument_text_object.Position The closing parenthesis.
---@return _my.argument_text_object.Range[] # Top-level argument ranges.
local function _get_argument_ranges(lines, open, close)
    ---@type _my.argument_text_object.Range[]
    local ranges = {}
    local depth = 0
    local argument_start = _next_column(open)

    for line_number = open.line, close.line do
        local line = _get_line(lines, line_number)
        local start_column = line_number == open.line and open.column + 2 or 1
        local end_column = line_number == close.line and close.column or #line

        for column = start_column, end_column do
            local character = line:sub(column, column)

            if character == "(" then
                depth = depth + 1
            elseif character == ")" then
                depth = depth - 1
            elseif character == "," and depth == 0 then
                table.insert(ranges, _make_range(argument_start, { line = line_number, column = column - 2 }))
                argument_start = { line = line_number, column = column }
            end
        end
    end

    if _compare_positions(argument_start, { line = close.line, column = close.column - 1 }) <= 0 then
        table.insert(ranges, _make_range(argument_start, { line = close.line, column = close.column - 1 }))
    end

    return ranges
end

--- Trim spaces around an argument's inner range.
---
---@param lines string[] Buffer lines.
---@param range _my.argument_text_object.Range The range to trim.
---@return _my.argument_text_object.Range # The trimmed range.
local function _trim_argument_range(lines, range)
    while range.start_line <= range.end_line do
        local line = _get_line(lines, range.start_line)

        if range.start_column >= #line then
            range.start_line = range.start_line + 1
            range.start_column = 0
        else
            local character = line:sub(range.start_column + 1, range.start_column + 1)

            if character ~= " " and character ~= "\t" then
                break
            end

            range.start_column = range.start_column + 1
        end
    end

    while range.end_line >= range.start_line do
        local line = _get_line(lines, range.end_line)

        if range.end_column < 0 then
            range.end_line = range.end_line - 1
            range.end_column = #_get_line(lines, range.end_line) - 1
        else
            local character = line:sub(range.end_column + 1, range.end_column + 1)

            if character ~= " " and character ~= "\t" then
                break
            end

            range.end_column = range.end_column - 1
        end
    end

    return range
end

--- Find the argument range that contains `cursor`.
---
---@param ranges _my.argument_text_object.Range[] Candidate argument ranges.
---@param cursor _my.argument_text_object.Position The cursor position.
---@return _my.argument_text_object.Range? # The matching argument range.
local function _find_cursor_argument(ranges, cursor)
    for _, range in ipairs(ranges) do
        if _contains_position(cursor, range) then
            return range
        end
    end

    return nil
end

--- Find the previous comma before `column`.
---
---@param line string The line to inspect.
---@param column integer The 0-or-more column to search before.
---@return integer? # The previous comma column, if found.
local function _find_previous_comma(line, column)
    for index = column, 1, -1 do
        if line:sub(index, index) == "," then
            return index - 1
        end
    end

    return nil
end

--- Include the correct comma and whitespace for a single-line argument.
---
---@param lines string[] Buffer lines.
---@param raw_range _my.argument_text_object.Range The untrimmed argument range.
---@param range _my.argument_text_object.Range The trimmed argument range.
---@param index integer The 1-or-more argument index.
---@param count integer The argument count.
local function _expand_single_line_range(lines, raw_range, range, index, count)
    local line = _get_line(lines, range.start_line)

    if index == 1 then
        if line:sub(range.end_column + 2, range.end_column + 2) == "," then
            range.end_column = range.end_column + 1

            while line:sub(range.end_column + 2, range.end_column + 2):match("^[ \t]$") do
                range.end_column = range.end_column + 1
            end
        end
    elseif index < count then
        range.start_column = raw_range.start_column

        if line:sub(range.end_column + 2, range.end_column + 2) == "," then
            range.end_column = range.end_column + 1
        end
    else
        range.start_column = _find_previous_comma(line, range.start_column) or raw_range.start_column
    end
end

--- Include the correct lines for a multiline argument.
---
---@param range _my.argument_text_object.Range The trimmed argument range.
---@param index integer The 1-or-more argument index.
---@param count integer The argument count.
---@param close _my.argument_text_object.Position The closing parenthesis.
local function _expand_multiline_range(range, index, count, close)
    if index < count then
        range.start_column = 0
        range.delete_linewise = true
    elseif range.end_line == close.line then
        range.start_column = 0
        range.end_column = close.column - 1
    end
end

--- Get the range for the argument text object under the cursor.
---
---@param buffer integer The buffer to inspect.
---@param cursor _my.argument_text_object.Position The cursor position.
---@return _my.argument_text_object.Range? # The argument range, if found.
function M.get_range(buffer, cursor)
    local lines = _get_lines(buffer)
    local open = _find_open_paren(lines, cursor)

    if open == nil then
        return nil
    end

    local close = _find_close_paren(lines, open)

    if close == nil then
        return nil
    end

    local ranges = _get_argument_ranges(lines, open, close)
    local range = _find_cursor_argument(ranges, cursor)
    local range_index = 0

    if range == nil then
        return nil
    end

    for index, candidate in ipairs(ranges) do
        if candidate == range then
            range_index = index
            break
        end
    end

    local raw_range = vim.deepcopy(range)
    range = _trim_argument_range(lines, vim.deepcopy(range))

    if open.line ~= close.line then
        _expand_multiline_range(range, range_index, #ranges, close)
    elseif range.end_line == range.start_line then
        _expand_single_line_range(lines, raw_range, range, range_index, #ranges)
    else
        _expand_multiline_range(range, range_index, #ranges, close)
    end

    return range
end

--- Replace `range` in the current buffer.
---
---@param range _my.argument_text_object.Range The range to replace.
local function _replace_range(range)
    if range.delete_linewise then
        vim.api.nvim_buf_set_lines(0, range.start_line - 1, range.end_line, false, {})
        return
    end

    local replacement_lines = vim.split(range.replacement, "\n", { plain = true })

    vim.api.nvim_buf_set_text(
        0,
        range.start_line - 1,
        range.start_column,
        range.end_line - 1,
        range.end_column + 1,
        replacement_lines
    )
end

--- Delete the argument under the cursor.
function M.delete()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local range = M.get_range(0, { line = cursor[1], column = cursor[2] })

    if range == nil then
        vim.notify("No argument text object found.", vim.log.levels.WARN)
        return
    end

    _replace_range(range)
end

--- Select the argument under the cursor.
function M.select()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local range = M.get_range(0, { line = cursor[1], column = cursor[2] })

    if range == nil then
        vim.notify("No argument text object found.", vim.log.levels.WARN)
        return
    end

    require("modules.features.core_editor_setup").set_text_object_marks(
        range.start_line,
        range.start_column,
        range.end_line,
        range.end_column
    )
end

vim.keymap.set({ "o", "x" }, "aa", M.select, {
    desc = "Select around the argument under the cursor.",
})

vim.keymap.set("n", "daa", M.delete, {
    desc = "Delete around the argument under the cursor.",
})

return M
