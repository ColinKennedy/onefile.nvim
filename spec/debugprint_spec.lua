local debugprint = require("modules.plugins.debugprint")

--- Create a scratch buffer for debugprint tests.
---
---@param lines string[] The lines to place in the buffer.
---@param cursor_line integer The 1-or-more cursor line.
---@param filetype string The filetype to assign to the buffer.
local function prepare_buffer(lines, cursor_line, filetype)
    local buffer = vim.api.nvim_create_buf(false, true)
    local eventignore = vim.o.eventignore

    vim.api.nvim_set_current_buf(buffer)
    vim.opt.eventignore:append("FileType")
    vim.bo[buffer].filetype = filetype
    vim.o.eventignore = eventignore
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })
end

--- Press normal-mode `keys`.
---
---@param keys string The keys to press.
local function press_keys(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

describe("debugprint", function()
    after_each(function()
        vim.cmd.enew({ bang = true })
    end)

    it("inserts below at the same indentation as the cursor line", function()
        prepare_buffer({
            "if value then",
            "        target = value",
            "    end",
        }, 2, "lua")

        debugprint.print_word_under_cursor("below")

        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

        assert.matches("^        print%(", lines[3])
        assert.matches("DEBUGPRINT", lines[3])
    end)

    it("inserts above at the same indentation as the cursor line", function()
        prepare_buffer({
            "if value then",
            "        target = value",
            "    end",
        }, 2, "python")

        debugprint.print_word_under_cursor("above")

        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

        assert.matches("^        print%(", lines[2])
        assert.matches("DEBUGPRINT", lines[2])
    end)

    it("returns to normal mode after inserting from a visual mapping", function()
        prepare_buffer({
            "if value then",
            "        target = value",
            "    end",
        }, 2, "lua")

        press_keys("viw,iv")

        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

        assert.matches("^        print%(", lines[3])
        assert.equal("n", vim.api.nvim_get_mode().mode)
    end)
end)
