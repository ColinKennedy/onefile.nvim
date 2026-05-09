local core_editor_setup = require("modules.features.core_editor_setup")

local _SHOWMODE

--- Create a scratch buffer with `text` and set the cursor at the end.
---
---@param text string The one-line buffer text.
---@param filetype string The filetype to assign.
local function prepare_snippet_buffer(text, filetype)
    local buffer = vim.api.nvim_create_buf(false, true)
    local eventignore = vim.o.eventignore

    vim.api.nvim_set_current_buf(buffer)
    vim.opt.eventignore:append("FileType")
    vim.bo[buffer].filetype = filetype
    vim.o.eventignore = eventignore
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { text })
    vim.api.nvim_win_set_cursor(0, { 1, #text })
end

describe("snippet completion", function()
    before_each(function()
        _SHOWMODE = vim.o.showmode
        vim.o.showmode = false
    end)

    after_each(function()
        pcall(vim.cmd.stopinsert)
        vim.o.showmode = _SHOWMODE
        vim.cmd.enew({ bang = true })
    end)

    it("immediately expands when there is only one snippet match", function()
        prepare_snippet_buffer("ii", "python")

        vim.cmd.startinsert({ bang = true })
        core_editor_setup.show_snippet_completion()

        assert.are.same({ "import " }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it("keeps the completion menu when there are multiple snippet matches", function()
        prepare_snippet_buffer("r", "python")
        local complete = vim.fn.complete
        ---@type {start_column: integer, matches: _my.completion.Entry[]}?
        local complete_call

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.complete = function(start_column, matches)
            complete_call = { start_column = start_column, matches = matches }
        end

        local ok, error_message = pcall(core_editor_setup.show_snippet_completion)
        vim.fn.complete = complete

        if not ok then
            error(error_message, 0)
        end

        assert.are.same({ "r" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
        if not complete_call then
            error("Expected snippet completion to open the completion menu.", 0)
        end

        assert.is_true(#complete_call.matches > 1)
    end)
end)
