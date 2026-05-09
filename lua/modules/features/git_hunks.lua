--- Stage and unstage visual selections from unsaved buffer edits.

local git_diff = require("modules.utilities.git_diff")

local M = {}

--- Get the current visual selection line range.
---
---@return integer # The first selected line.
---@return integer # The last selected line.
---
local function _get_visual_line_range()
    local start_position = vim.api.nvim_buf_get_mark(0, "<")
    local end_position = vim.api.nvim_buf_get_mark(0, ">")
    local start_line = start_position[1]
    local end_line = end_position[1]

    if end_line < start_line then
        start_line, end_line = end_line, start_line
    end

    return start_line, end_line
end

--- Notify the user about a git hunk operation failure.
---
---@param message string The failure message to show.
local function _notify_error(message)
    vim.notify(message, vim.log.levels.ERROR)
end

--- Apply the current visual selection to the git index.
---
---@param reverse boolean If `true`, unstage the selected changes.
function M.apply_visual_selection(reverse)
    local buffer = vim.api.nvim_get_current_buf()
    local details, details_error = git_diff.get_file_details(buffer)

    if not details then
        _notify_error(details_error or "Cannot find git details for current buffer.")

        return
    end

    local start_line, end_line = _get_visual_line_range()
    local old_lines, is_new_file = git_diff.get_head_lines(details)
    local new_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    local patch = git_diff.build_selected_patch(
        old_lines,
        new_lines,
        details.relative_path,
        start_line,
        end_line,
        is_new_file
    )
    local success, apply_error = git_diff.apply_cached_patch(details, patch, reverse)

    if not success then
        _notify_error(apply_error or "Could not apply selected git hunk.")

        return
    end

    require("modules.features.git_gutter").update(buffer)
end

vim.keymap.set("x", "<leader>gah", function()
    M.apply_visual_selection(false)
end, { desc = "Stage selected git hunk lines." })

vim.keymap.set("x", "<leader>grh", function()
    M.apply_visual_selection(true)
end, { desc = "Unstage selected git hunk lines." })

return M
