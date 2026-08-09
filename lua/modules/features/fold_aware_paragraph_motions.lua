--- Fold-aware paragraph motions for `{` and `}`.
---
--- These behave like the built-in `{` and `}` paragraph motions, except that a
--- closed fold counts as a single line of text. Blank lines hidden inside a
--- closed fold do not count as paragraph boundaries, so pressing `{` or `}`
--- jumps over the entire fold in one step without opening it.

---@class _my.fold_aware_paragraph_motions
local M = {}

---@class _my.fold_aware_paragraph_motions._P
local _P = {}

---@alias _my.fold_paragraph_motion.Direction "previous" | "next"

---@type table<_my.fold_paragraph_motion.Direction, integer>
local _DIRECTION_STEPS = {
    next = 1,
    previous = -1,
}

--- Get the next line to inspect, treating a closed fold as a single line.
---
--- When `line` is inside a closed fold, the whole fold is skipped in one step so
--- that its hidden contents are never scanned.
---
---@param line integer The current 1-or-more line.
---@param step integer 1 to move down the buffer, -1 to move up the buffer.
---@return integer # The next 1-or-more line to inspect.
local function _step_over_folds(line, step)
    if step > 0 then
        local fold_end = vim.fn.foldclosedend(line)

        if fold_end ~= -1 then
            return fold_end + 1
        end

        return line + 1
    end

    local fold_start = vim.fn.foldclosed(line)

    if fold_start ~= -1 then
        return fold_start - 1
    end

    return line - 1
end

--- Check whether `line` is a paragraph boundary for fold-aware motion.
---
--- A boundary is an empty line that is not hidden inside a closed fold.
---
---@param line integer The 1-or-more line to inspect.
---@return boolean # Whether the line ends a paragraph.
local function _is_paragraph_boundary(line)
    if vim.fn.foldclosed(line) ~= -1 then
        return false
    end

    local text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1] or ""

    return text == ""
end

--- Find the next fold-aware paragraph boundary from `start_line`.
---
---@param start_line integer The 1-or-more line to search from.
---@param step integer 1 to move down the buffer, -1 to move up the buffer.
---@return integer # The 1-or-more boundary line, clamped to the buffer range.
local function _find_boundary(start_line, step)
    local line_count = vim.api.nvim_buf_line_count(0)
    local line = _step_over_folds(start_line, step)

    while line >= 1 and line <= line_count do
        if _is_paragraph_boundary(line) then
            break
        end

        line = _step_over_folds(line, step)
    end

    return math.min(math.max(line, 1), line_count)
end

--- Move the cursor over fold-aware paragraphs, treating folds as single lines.
---
---@param direction _my.fold_paragraph_motion.Direction The direction to move.
---@param count integer? How many paragraphs to move. Defaults to `v:count1`.
function _P.move(direction, count)
    local step = _DIRECTION_STEPS[direction]
    local line = vim.api.nvim_win_get_cursor(0)[1]

    for _ = 1, count or vim.v.count1 do
        line = _find_boundary(line, step)
    end

    local fold_start = vim.fn.foldclosed(line)

    if fold_start ~= -1 then
        line = fold_start
    end

    vim.api.nvim_win_set_cursor(0, { line, 0 })
end

vim.keymap.set({ "n", "x" }, "}", function()
    _P.move("next")
end, { desc = "Move to the next paragraph, treating a closed fold as one line." })

vim.keymap.set({ "n", "x" }, "{", function()
    _P.move("previous")
end, { desc = "Move to the previous paragraph, treating a closed fold as one line." })

--- Expose the private namespace so the specs can reach it.
---@type _my.fold_aware_paragraph_motions._P
M._P = _P

return M
