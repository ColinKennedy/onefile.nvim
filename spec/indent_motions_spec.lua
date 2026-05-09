local indent_motions = require("modules.features.indent_motions")

--- Create a scratch buffer for indentation motion tests.
---
---@param lines string[] The lines to place in the buffer.
---@param cursor_line integer The 1-or-more cursor line.
local function prepare_buffer(lines, cursor_line)
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })
end

--- Get the current 1-or-more cursor line.
---
---@return integer # The current cursor line.
local function get_cursor_line()
    return vim.api.nvim_win_get_cursor(0)[1]
end

--- Press normal-mode `keys`.
---
---@param keys string The keys to press.
local function press_normal_keys(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

describe("indent motions", function()
    after_each(function()
        vim.cmd.enew({ bang = true })
    end)

    it("moves to the previous line with lesser indentation", function()
        prepare_buffer({
            "root",
            "    parent",
            "        current",
        }, 3)

        indent_motions.move("previous", "lesser")

        assert.equal(2, get_cursor_line())
    end)

    it("moves to the next line with lesser indentation", function()
        prepare_buffer({
            "        current",
            "",
            "    ",
            "    parent",
            "root",
        }, 1)

        indent_motions.move("next", "lesser")

        assert.equal(4, get_cursor_line())
    end)

    it("moves to the previous line with greater indentation", function()
        prepare_buffer({
            "    child",
            "root",
        }, 2)

        indent_motions.move("previous", "greater")

        assert.equal(1, get_cursor_line())
    end)

    it("moves to the next line with greater indentation", function()
        prepare_buffer({
            "root",
            "    child",
        }, 1)

        indent_motions.move("next", "greater")

        assert.equal(2, get_cursor_line())
    end)

    it("moves to the previous line with equal indentation", function()
        prepare_buffer({
            "    sibling",
            "        child",
            "    current",
        }, 3)

        indent_motions.move("previous", "equal")

        assert.equal(1, get_cursor_line())
    end)

    it("moves to the next line with equal indentation", function()
        prepare_buffer({
            "    current",
            "        child",
            "    sibling",
        }, 1)

        indent_motions.move("next", "equal")

        assert.equal(3, get_cursor_line())
    end)

    it("moves to the previous line whose indentation differs from the current line", function()
        prepare_buffer({
            "    different",
            "current",
            "",
            "same",
        }, 4)

        indent_motions.move_to_indent_change("previous")

        assert.equal(1, get_cursor_line())
    end)

    it("moves to the next line whose indentation increases from the current line", function()
        prepare_buffer({
            "   foo",
            "",
            "   more lines",
            "   etc lines",
            "",
            "       bar",
        }, 1)

        indent_motions.move_to_indent_change("next")

        assert.equal(6, get_cursor_line())
    end)

    it("moves to the next line whose indentation decreases from the current line", function()
        prepare_buffer({
            "   foo",
            "",
            "   more lines",
            "   etc lines",
            "",
            " fizz",
        }, 1)

        indent_motions.move_to_indent_change("next")

        assert.equal(6, get_cursor_line())
    end)

    it("scans upward for the previous line whose indentation differs from the current line", function()
        prepare_buffer({
            "       bar",
            "",
            "   more lines",
            "   etc lines",
            "",
            "   foo",
        }, 6)

        indent_motions.move_to_indent_change("previous")

        assert.equal(1, get_cursor_line())
    end)

    it("maps double bracket keys to indentation changes", function()
        prepare_buffer({
            "   foo",
            "",
            "   more lines",
            "   etc lines",
            "",
            "       bar",
        }, 1)

        press_normal_keys("]]")

        assert.equal(6, get_cursor_line())
    end)

    it("leaves the cursor alone when no matching line exists", function()
        prepare_buffer({
            "root",
            "    child",
        }, 1)

        indent_motions.move("previous", "equal")

        assert.equal(1, get_cursor_line())
    end)
end)
