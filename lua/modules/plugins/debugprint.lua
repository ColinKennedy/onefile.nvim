--- Insert simple debug-print statements for the current word or visual selection.
---
--- (It's https://github.com/andrewferrier/debugprint.nvim, basically)

local _COUNTER = 1
local _P = {}

---@return string? # Get the visual selection, if it is in visual mode.
local function _get_selected_word()
    local mode = vim.api.nvim_get_mode().mode

    if not mode:match("[vV]") then
        return nil
    end

    local characters = vim.fn.getregion(vim.fn.getpos("."), vim.fn.getpos("v"), { type = mode })
    local result = vim.fn.join(characters, "")

    if mode:match("V") then
        result = require("modules.features.core_editor_setup").strip_left(result)
    end

    return result
end

--- Get the indentation text from `line_number`.
---
---@param line_number integer The 1-or-more line number to inspect.
---@return string # The leading whitespace on the line.
local function _get_line_indentation(line_number)
    local line = vim.api.nvim_buf_get_lines(0, line_number - 1, line_number, false)[1] or ""

    return line:match("^%s*") or ""
end

--- Check whether `mode` is visual or select mode.
---
---@param mode string The current Neovim mode.
---@return boolean # Whether the mode represents a visual selection.
local function _is_visual_mode(mode)
    return mode:match("[vV]") ~= nil
end

--- Leave visual mode if the mapping started there.
---
---@param was_visual boolean Whether the debugprint command began in visual mode.
local function _leave_visual_mode(was_visual)
    if not was_visual then
        return
    end

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
end

--- Print the current word to the line above or below.
---
---@param direction "above" | "below"
---    The placement of the inserted print statement.
---
function _P.print_word_under_cursor(direction)
    local was_visual = _is_visual_mode(vim.api.nvim_get_mode().mode)
    local word = _get_selected_word() or vim.fn.expand("<cword>")
    local row = vim.fn.line(".")
    local file_name = vim.fn.expand("%"):gsub("\\", "\\\\")
    local indentation = _get_line_indentation(row)
    _COUNTER = _COUNTER + 1
    ---@type string
    local line

    if vim.o.filetype == "lua" then
        line = string.format(
            'print("DEBUGPRINT[%s]: %s:%s: %s=" .. vim.inspect(%s))',
            _COUNTER,
            file_name,
            row,
            word,
            word
        )
    elseif vim.o.filetype == "python" then
        line = string.format('print(f"DEBUGPRINT[%s]: %s:%s: %s={%s}")', _COUNTER, file_name, row, word, word)
    else
        _COUNTER = _COUNTER - 1
        vim.notify(string.format('Type "%s" is not supported yet.', vim.o.filetype), vim.log.levels.ERROR)

        return
    end

    line = indentation .. line

    if direction == "below" then
        vim.api.nvim_buf_set_lines(0, row, row, true, { line })
    elseif direction == "above" then
        vim.api.nvim_buf_set_lines(0, row - 1, row - 1, true, { line })
    end

    _leave_visual_mode(was_visual)
end

vim.keymap.set({ "n", "v" }, "<leader>iv", function()
    _P.print_word_under_cursor("below")
end, { noremap = true, desc = "Print the current word below the cursor line." })

vim.keymap.set({ "n", "v" }, "<leader>iV", function()
    _P.print_word_under_cursor("above")
end, { noremap = true, desc = "Print the current word above the cursor line." })

return _P
