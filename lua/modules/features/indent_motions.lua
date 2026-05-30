--- Define motions for jumping between lines by relative indentation.

local _P = {}

---@alias _my.indent_motion.Direction "previous" | "next"
---@alias _my.indent_motion.Relation "lesser" | "greater" | "equal"

---@type table<_my.indent_motion.Direction, integer>
local _DIRECTION_STEPS = {
    next = 1,
    previous = -1,
}

--- Check whether `line` is empty or only whitespace.
---
---@param line string The line text to inspect.
---@return boolean # Whether the line has no visible text.
local function _is_blank_line(line)
    return line:match("^%s*$") ~= nil
end

--- Get the first visible column for `line`.
---
---@param line string The line text to inspect.
---@return integer # The 0-or-more cursor column for the first visible character.
local function _get_first_non_whitespace_column(line)
    local column = line:find("%S")

    if not column then
        return 0
    end

    return column - 1
end

--- Check whether `candidate_indent` matches `relation` to `current_indent`.
---
---@param candidate_indent integer The indentation of the candidate line.
---@param current_indent integer The indentation of the current line.
---@param relation _my.indent_motion.Relation The kind of indentation match to find.
---@return boolean # Whether the candidate indentation is a match.
local function _is_matching_indent(candidate_indent, current_indent, relation)
    if relation == "lesser" then
        return candidate_indent < current_indent
    end

    if relation == "greater" then
        return candidate_indent > current_indent
    end

    return candidate_indent == current_indent
end

--- Get `line_number`'s text if it is nonblank.
---
---@param line_number integer The 1-or-more line number to inspect.
---@return string? # The line text, if it is not blank.
local function _get_nonblank_line(line_number)
    local line = vim.api.nvim_buf_get_lines(0, line_number - 1, line_number, false)[1] or ""

    if _is_blank_line(line) then
        return nil
    end

    return line
end

--- Find a nearby nonblank line that matches `relation` to `current_indent`.
---
---@param start_line integer The 1-or-more line to start searching from.
---@param current_indent integer The indentation to compare against.
---@param direction _my.indent_motion.Direction The direction to search.
---@param relation _my.indent_motion.Relation The kind of indentation match to find.
---@return integer? # The found 1-or-more line, if any.
local function _find_matching_indent_line(start_line, current_indent, direction, relation)
    local step = _DIRECTION_STEPS[direction]
    local line_count = vim.api.nvim_buf_line_count(0)
    local line_number = start_line + step

    while line_number >= 1 and line_number <= line_count do
        local line = vim.api.nvim_buf_get_lines(0, line_number - 1, line_number, false)[1] or ""

        if not _is_blank_line(line) and _is_matching_indent(vim.fn.indent(line_number), current_indent, relation) then
            return line_number
        end

        line_number = line_number + step
    end

    return nil
end

--- Move the cursor to `line_number`'s first visible character.
---
---@param line_number integer The 1-or-more line number to move to.
local function _move_to_line(line_number)
    local line = vim.api.nvim_buf_get_lines(0, line_number - 1, line_number, false)[1] or ""
    vim.api.nvim_win_set_cursor(0, { line_number, _get_first_non_whitespace_column(line) })
end

--- Move the cursor to a nearby line with a matching relative indentation.
---
---@param direction _my.indent_motion.Direction The direction to search.
---@param relation _my.indent_motion.Relation The kind of indentation match to find.
function _P.move(direction, relation)
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    local current_indent = vim.fn.indent(current_line)
    local target_line = _find_matching_indent_line(current_line, current_indent, direction, relation)

    if not target_line then
        return
    end

    _move_to_line(target_line)
end

--- Move the cursor to the next line whose indentation differs from the current line.
---
--- Blank lines are ignored while scanning.
---
---@param direction _my.indent_motion.Direction The direction to search.
function _P.move_to_indent_change(direction)
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    local current_indent = vim.fn.indent(current_line)
    local step = _DIRECTION_STEPS[direction]
    local line_count = vim.api.nvim_buf_line_count(0)
    local line_number = current_line + step

    while line_number >= 1 and line_number <= line_count do
        local line = _get_nonblank_line(line_number)

        if line and vim.fn.indent(line_number) ~= current_indent then
            _move_to_line(line_number)

            return
        end

        line_number = line_number + step
    end
end

vim.keymap.set("n", "[-", function()
    _P.move("previous", "lesser")
end, { desc = "Move to the previous line with lesser indentation." })

vim.keymap.set("n", "]-", function()
    _P.move("next", "lesser")
end, { desc = "Move to the next line with lesser indentation." })

vim.keymap.set("n", "[+", function()
    _P.move("previous", "greater")
end, { desc = "Move to the previous line with greater indentation." })

vim.keymap.set("n", "]+", function()
    _P.move("next", "greater")
end, { desc = "Move to the next line with greater indentation." })

vim.keymap.set("n", "[=", function()
    _P.move("previous", "equal")
end, { desc = "Move to the previous line with equal indentation." })

vim.keymap.set("n", "]=", function()
    _P.move("next", "equal")
end, { desc = "Move to the next line with equal indentation." })

vim.keymap.set("n", "[[", function()
    _P.move_to_indent_change("previous")
end, { desc = "Move to the previous line with changed indentation." })

vim.keymap.set("n", "]]", function()
    _P.move_to_indent_change("next")
end, { desc = "Move to the next line with changed indentation." })

return _P
