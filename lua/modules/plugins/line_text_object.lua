--- Define a text object for the current line's contents.

local M = {}

--- Get the current line content range, excluding the newline.
---
---@param buffer integer The buffer to inspect.
---@param line_number integer The 1-or-more line number.
---@return _my.text_object.Range # The text object range.
function M.get_range(buffer, line_number)
    local line = vim.api.nvim_buf_get_lines(buffer, line_number - 1, line_number, false)[1] or ""

    return {
        start_line = line_number,
        start_column = 0,
        end_line = line_number,
        end_column = math.max(#line - 1, 0),
    }
end

--- Select the current line's contents without selecting its newline.
function M.select()
    local buffer = vim.api.nvim_get_current_buf()
    local line_number = vim.api.nvim_win_get_cursor(0)[1]
    local range = M.get_range(buffer, line_number)

    require("modules.features.core_editor_setup").set_text_object_marks(
        range.start_line,
        range.start_column,
        range.end_line,
        range.end_column
    )
end

vim.keymap.set({ "o", "x" }, "il", M.select, {
    desc = "Select the current line contents without its newline.",
})

return M
