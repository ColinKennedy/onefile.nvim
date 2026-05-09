local code_argument_toggle = require("modules.plugins.code_argument_toggle")

--- Create a scratch buffer for toggle tests.
---
---@param lines string[] Buffer contents.
---@param cursor_line integer The 1-or-more cursor line.
---@param cursor_column integer The 0-or-more cursor column.
local function make_buffer(lines, cursor_line, cursor_column)
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { cursor_line, cursor_column })
    vim.bo.expandtab = true
    vim.bo.shiftwidth = 4
end

--- Get all lines from the current buffer.
---
---@return string[] # Buffer contents.
local function get_lines()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

describe("code argument toggle", function()
    after_each(function()
        vim.cmd.enew({ bang = true })
    end)

    it("expands and collapses parenthesized arguments", function()
        make_buffer({ "(foo, bar, fizz)" }, 1, 6)

        code_argument_toggle.toggle()

        assert.are.same({
            "(",
            "    foo,",
            "    bar,",
            "    fizz,",
            ")",
        }, get_lines())

        vim.api.nvim_win_set_cursor(0, { 3, 5 })
        code_argument_toggle.toggle()

        assert.are.same({ "(foo, bar, fizz)" }, get_lines())
    end)

    it("maps leader sa to the toggle", function()
        make_buffer({ "(foo, bar)" }, 1, 6)

        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>sa", true, false, true), "x", false)

        assert.are.same({
            "(",
            "    foo,",
            "    bar,",
            ")",
        }, get_lines())
    end)

    it("expands and collapses bracketed arguments", function()
        make_buffer({ "[foo, bar, fizz]" }, 1, 6)

        code_argument_toggle.toggle()

        assert.are.same({
            "[",
            "    foo,",
            "    bar,",
            "    fizz,",
            "]",
        }, get_lines())

        vim.api.nvim_win_set_cursor(0, { 3, 5 })
        code_argument_toggle.toggle()

        assert.are.same({ "[foo, bar, fizz]" }, get_lines())
    end)

    it("expands and collapses braced arguments", function()
        make_buffer({ "{foo: 1, bar: {baz: 2}, fizz: 3}" }, 1, 9)

        code_argument_toggle.toggle()

        assert.are.same({
            "{",
            "    foo: 1,",
            "    bar: {baz: 2},",
            "    fizz: 3,",
            "}",
        }, get_lines())

        vim.api.nvim_win_set_cursor(0, { 3, 8 })
        code_argument_toggle.toggle()

        assert.are.same({ "{foo: 1, bar: {baz: 2}, fizz: 3}" }, get_lines())
    end)

    it("targets the innermost containing wrapper", function()
        make_buffer({ "outer(foo, inner(bar, fizz), buzz)" }, 1, 18)

        code_argument_toggle.toggle()

        assert.are.same({
            "outer(foo, inner(",
            "    bar,",
            "    fizz,",
            "), buzz)",
        }, get_lines())
    end)

    it("expands with the current line indentation", function()
        make_buffer({ "    call(foo, bar)" }, 1, 12)

        code_argument_toggle.toggle()

        assert.are.same({
            "    call(",
            "        foo,",
            "        bar,",
            "    )",
        }, get_lines())
    end)
end)
