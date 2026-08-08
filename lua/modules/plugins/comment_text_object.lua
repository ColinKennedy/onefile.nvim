--- Define a linewise text object for contiguous comment blocks.

local M = {}
local _P = {}

---@class _my.comment_text_object.Range
---@field start_line integer The first 1-or-more line in the comment block.
---@field end_line integer The last 1-or-more line in the comment block.

--- Get a buffer line.
---
---@param buffer integer The buffer to read from.
---@param line_number integer The 1-or-more line number.
---@return string # The line text, or an empty string.
local function _get_line(buffer, line_number)
    return vim.api.nvim_buf_get_lines(buffer, line_number - 1, line_number, false)[1] or ""
end

--- Get the single-line comment leader for `buffer`.
---
--- The leader is the text before `%s` in `commentstring`, e.g. `#` for
--- `# %s` or `//` for `// %s`.
---
---@param buffer integer The buffer to inspect.
---@return string? # The comment leader, or nil when none is defined.
local function _get_comment_leader(buffer)
    local commentstring = vim.bo[buffer].commentstring

    if commentstring == nil or commentstring == "" then
        return nil
    end

    local before = commentstring:match("^(.-)%%s")

    if before == nil then
        return nil
    end

    local leader = before:gsub("%s+$", "")

    if leader == "" then
        return nil
    end

    return leader
end

--- Check whether `line` is a full-line comment starting with `leader`.
---
---@param line string The line to inspect.
---@param leader string The comment leader.
---@return boolean # Whether the line is a comment line.
local function _is_comment_line(line, leader)
    local trimmed = line:gsub("^%s*", "")

    return trimmed:sub(1, #leader) == leader
end

--- Find the first line of the comment block containing `cursor_line`.
---
---@param buffer integer The buffer to inspect.
---@param cursor_line integer The 1-or-more cursor line.
---@param leader string The comment leader.
---@return integer # The first 1-or-more comment line.
local function _find_start_line(buffer, cursor_line, leader)
    local line_number = cursor_line

    while line_number > 1 and _is_comment_line(_get_line(buffer, line_number - 1), leader) do
        line_number = line_number - 1
    end

    return line_number
end

--- Find the last line of the comment block containing `cursor_line`.
---
---@param buffer integer The buffer to inspect.
---@param cursor_line integer The 1-or-more cursor line.
---@param leader string The comment leader.
---@return integer # The last 1-or-more comment line.
local function _find_end_line(buffer, cursor_line, leader)
    local line_number = cursor_line
    local line_count = vim.api.nvim_buf_line_count(buffer)

    while line_number < line_count and _is_comment_line(_get_line(buffer, line_number + 1), leader) do
        line_number = line_number + 1
    end

    return line_number
end

--- Get the range for the comment block under `cursor_line`.
---
--- The block is the contiguous run of comment lines around the cursor,
--- extending both above and below it.
---
---@param buffer integer The buffer to inspect.
---@param cursor_line integer The 1-or-more cursor line.
---@return _my.comment_text_object.Range? # The comment block range, if any.
function M._get_range(buffer, cursor_line)
    local leader = _get_comment_leader(buffer)

    if leader == nil then
        return nil
    end

    if not _is_comment_line(_get_line(buffer, cursor_line), leader) then
        return nil
    end

    return {
        start_line = _find_start_line(buffer, cursor_line, leader),
        end_line = _find_end_line(buffer, cursor_line, leader),
    }
end

--- Select the comment block under the cursor as a linewise text object.
function _P.select()
    local buffer = vim.api.nvim_get_current_buf()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local range = M._get_range(buffer, cursor_line)

    if range == nil then
        return
    end

    vim.cmd(string.format("normal! %dGV%dG", range.start_line, range.end_line))
end

vim.keymap.set({ "o", "x" }, "ic", _P.select, {
    desc = "Select the contiguous comment block around the cursor.",
})

return M
