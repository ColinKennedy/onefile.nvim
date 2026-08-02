local fold_aware_paragraph_motions = require("modules.features.fold_aware_paragraph_motions")

--- Create a scratch buffer + window for fold-aware paragraph motion tests.
---
---@param lines string[] The lines to place in the buffer.
---@param cursor_line integer The 1-or-more cursor line.
---@return integer # The created buffer.
local function prepare_buffer(lines, cursor_line)
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.wo.foldmethod = "manual"
    vim.wo.foldenable = true
    vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })

    return buffer
end

--- Create and close a manual fold over an inclusive line range.
---
---@param first integer The 1-or-more first folded line.
---@param last integer The 1-or-more last folded line.
local function close_fold(first, last)
    vim.cmd(string.format("%d,%dfold", first, last))
end

--- Get the current 1-or-more cursor line.
---
---@return integer # The current cursor line.
local function get_cursor_line()
    return vim.api.nvim_win_get_cursor(0)[1]
end

describe("fold-aware paragraph motions", function()
    after_each(function()
        vim.cmd.enew({ bang = true })
        vim.wo.foldmethod = "manual"
    end)

    it("moves to the next paragraph like the built-in motion when nothing is folded", function()
        prepare_buffer({
            "alpha",
            "beta",
            "",
            "gamma",
        }, 1)

        fold_aware_paragraph_motions.move("next")

        assert.equal(3, get_cursor_line())
    end)

    it("moves to the previous paragraph like the built-in motion when nothing is folded", function()
        prepare_buffer({
            "alpha",
            "",
            "beta",
            "gamma",
        }, 4)

        fold_aware_paragraph_motions.move("previous")

        assert.equal(2, get_cursor_line())
    end)

    it("jumps over a closed fold that contains blank lines when moving forward", function()
        prepare_buffer({
            "before",
            "",
            "fold line 1",
            "",
            "fold line 2",
            "",
            "after",
        }, 2)
        close_fold(3, 5)

        fold_aware_paragraph_motions.move("next")

        assert.equal(6, get_cursor_line())
    end)

    it("jumps over a closed fold that contains blank lines when moving backward", function()
        prepare_buffer({
            "before",
            "",
            "fold line 1",
            "",
            "fold line 2",
            "",
            "after",
        }, 6)
        close_fold(3, 5)

        fold_aware_paragraph_motions.move("previous")

        assert.equal(2, get_cursor_line())
    end)

    it("does not open the closed fold it jumps across", function()
        prepare_buffer({
            "before",
            "",
            "fold line 1",
            "",
            "fold line 2",
            "",
            "after",
        }, 2)
        close_fold(3, 5)

        fold_aware_paragraph_motions.move("next")

        assert.equal(3, vim.fn.foldclosed(4))
    end)

    it("honors a count when moving forward", function()
        prepare_buffer({
            "alpha",
            "",
            "beta",
            "",
            "gamma",
        }, 1)

        fold_aware_paragraph_motions.move("next", 2)

        assert.equal(4, get_cursor_line())
    end)
end)
