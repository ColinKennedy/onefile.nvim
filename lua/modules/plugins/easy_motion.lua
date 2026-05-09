local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
--- A native "EasyMotion" snippet
-- Reference: https://antonk52.github.io/webdevandstuff/post/2025-11-30-diy-easymotion.html
_NAMESPACE = vim.api.nvim_create_namespace("my.easymotion")
_CHARACTERS = vim.split("fjdkslgha;rueiwotyqpvbcnxmzFJDKSLGHARUEIWOTYQPVBCNXMZ", "")

--- Gather all visible extmarks data for `buffer` (ignore folded text).
---
---@param buffer integer The location in Vim to get line data from.
---@param window integer The view into the buffer to get cursor data from.
---@return _my.easymotion.ExtmarksData # The found extmarks for the `buffer`.
---
function _get_extmarks(buffer, window)
    local absolute_index = 1
    local first = vim.fn.nr2char(vim.fn.getchar() --[[@as number]])
    local second = vim.fn.nr2char(vim.fn.getchar() --[[@as number]])
    local line_start, line_end = vim.fn.line("w0", window), vim.fn.line("w$", window)

    ---@type table<string, {line: integer, column: integer, id: integer}>
    local output = {}

    local lines = vim.api.nvim_buf_get_lines(buffer, line_start - 1, line_end, false)
    local search_term = first .. second

    local is_case_sensitive = search_term ~= string.lower(search_term)

    for relative_line_index, line_text in ipairs(lines) do
        if not is_case_sensitive then
            line_text = string.lower(line_text)
        end

        local absolute_line_index = relative_line_index + line_start - 1

        -- NOTE: Skip folded lines.
        if vim.fn.foldclosed(absolute_line_index) == -1 then
            for relative_index = 1, #line_text do
                if
                    line_text:sub(relative_index, relative_index + 1) == search_term
                    and absolute_index <= #_CHARACTERS
                then
                    local overlay_character = _CHARACTERS[absolute_index]
                    local absolute_line_number = line_start + relative_line_index - 2
                    local column = relative_index - 1
                    local id = vim.api.nvim_buf_set_extmark(buffer, _NAMESPACE, absolute_line_number, column + 2, {
                        virt_text = { { overlay_character, "CurSearch" } },
                        virt_text_pos = "overlay",
                        hl_mode = "replace",
                    })
                    output[overlay_character] = {
                        line = absolute_line_number,
                        column = column,
                        id = id,
                    }
                    absolute_index = absolute_index + 1

                    if absolute_index > #_CHARACTERS then
                        return output
                    end
                end
            end
        end
    end

    return output
end

--- Jump anywhere on-screen. Just type 2 consecutive characters to where you want to go.
function _run_easy_motion()
    local window = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_get_current_buf()

    vim.api.nvim_buf_clear_namespace(buffer, _NAMESPACE, 0, -1)
    local extmarks = _get_extmarks(buffer, window)

    vim.schedule(function() -- NOTE: Wait for the next character, after extmarks are computed.
        local next_character = vim.fn.nr2char(vim.fn.getchar() --[[@as number]])

        if extmarks[next_character] then
            local position = extmarks[next_character]

            -- NOTE: This line makes `<C-o>` work
            vim.cmd("normal! m'")
            vim.api.nvim_win_set_cursor(window, { position.line + 1, position.column })
        end

        -- NOTE: Clear all extmarks
        vim.api.nvim_buf_clear_namespace(buffer, _NAMESPACE, 0, -1)
    end)
end

vim.keymap.set(
    { "n", "x" },
    "s",
    _run_easy_motion,
    { desc = "Jump anywhere on-screen. Just type 2 consecutive characters to where you want to go." }
)
end)
