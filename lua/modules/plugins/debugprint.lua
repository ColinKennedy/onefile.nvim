--- Print the current word (It's https://github.com/andrewferrier/debugprint.nvim, basically)
local _COUNTER = 1

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

--- Print the current word to the line above or below.
---
---@param direction "above" | "below"
---    The placement of the inserted print statement.
---
local function _print_word_under_cursor(direction)
    local word = _get_selected_word() or vim.fn.expand("<cword>")
    local row = vim.fn.line(".")
    local file_name = vim.fn.expand("%")
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

    if direction == "below" then
        vim.api.nvim_buf_set_lines(0, row, row, true, { line })
        vim.cmd(string.format("%snormal! ==", row + 1))
    elseif direction == "above" then
        vim.api.nvim_buf_set_lines(0, row - 1, row - 1, true, { line })
        vim.cmd(string.format("%snormal! ==", row))
    end
end

vim.keymap.set({ "n", "v" }, "<leader>iv", function()
    _print_word_under_cursor("below")
end, { noremap = true, desc = "Print the current word below the cursor line." })

vim.keymap.set({ "n", "v" }, "<leader>iV", function()
    _print_word_under_cursor("above")
end, { noremap = true, desc = "Print the current word above the cursor line." })
