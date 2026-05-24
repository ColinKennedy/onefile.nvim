--- Preserve visual-selection intent after reflowing text with `gq` or `gw`.
---
--- After calling either mapping, you can press `gv` and it will select the reflowed text.
--- Seriously, why isn't this Neovim's default behavior?
---

local M = {}
local _P = {}

--- Get the selected line range from the current visual selection.
---
---@return integer # The first selected line.
---@return integer # The last selected line.
function _P.get_visual_line_range()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local visual = vim.fn.getpos("v")
    local start_line = math.min(cursor[1], visual[2])
    local end_line = math.max(cursor[1], visual[2])

    return start_line, end_line
end

--- Check if a line is blank.
---
---@param line string The line to inspect.
---@return boolean # Whether the line is empty or whitespace-only.
function _P.is_blank(line)
    return line:match("^%s*$") ~= nil
end

--- Find the non-blank paragraph around `line`.
---
---@param line integer The 1-or-more line where the paragraph should be found.
---@return integer # The paragraph start line.
---@return integer # The paragraph end line.
function _P.get_paragraph_range(line)
    local line_count = vim.api.nvim_buf_line_count(0)
    local start_line = math.max(1, math.min(line, line_count))
    local end_line = start_line

    while start_line > 1 do
        local previous = vim.api.nvim_buf_get_lines(0, start_line - 2, start_line - 1, false)[1] or ""

        if _P.is_blank(previous) then
            break
        end

        start_line = start_line - 1
    end

    while end_line < line_count do
        local next_line = vim.api.nvim_buf_get_lines(0, end_line, end_line + 1, false)[1] or ""

        if _P.is_blank(next_line) then
            break
        end

        end_line = end_line + 1
    end

    return start_line, end_line
end

--- Set the previous visual selection to `start_line` through `end_line`.
---
---@param start_line integer The first selected line.
---@param end_line integer The last selected line.
function _P.set_previous_visual_line_range(start_line, end_line)
    local end_text = vim.api.nvim_buf_get_lines(0, end_line - 1, end_line, false)[1] or ""

    vim.fn.setpos("'<", { 0, start_line, 1, 0 })
    vim.fn.setpos("'>", { 0, end_line, math.max(#end_text, 1), 0 })
end

--- Reflow the visual selection and make `gv` select the reflowed paragraph.
---
---@param command "gq"|"gw" The visual-mode formatting command to run.
function M.reflow_visual_selection(command)
    local start_line = _P.get_visual_line_range()

    vim.cmd("normal! " .. command)

    local paragraph_start, paragraph_end = _P.get_paragraph_range(start_line)
    _P.set_previous_visual_line_range(paragraph_start, paragraph_end)
end

vim.keymap.set("x", "gq", function()
    M.reflow_visual_selection("gq")
end, {
    desc = "Reflow text and make gv reselect the reflowed paragraph.",
    silent = true,
})

vim.keymap.set("x", "gw", function()
    M.reflow_visual_selection("gw")
end, {
    desc = "Reflow text without moving the cursor and make gv reselect the reflowed paragraph.",
    silent = true,
})

M._P = _P

return M
