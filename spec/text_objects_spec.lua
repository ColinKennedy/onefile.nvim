local indent_text_objects = require("modules.plugins.indent_text_objects")
local line_text_object = require("modules.plugins.line_text_object")
local subvariable_text_object = require("modules.plugins.subvariable_text_object")
local argument_text_object = require("modules.plugins.argument_text_object")

---@class _my.test.ObjectCase
---@field after string
---@field before string
---@field cursor integer
---@field keys string?

--- Create a scratch buffer with `lines`.
---
---@param lines string[] Initial buffer lines.
---@param cursor_line integer The 1-or-more cursor line.
---@param cursor_column integer? The 0-or-more cursor column.
---@return integer # The created buffer.
local function make_buffer(lines, cursor_line, cursor_column)
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { cursor_line, cursor_column or 0 })

    return buffer
end

--- Press normal-mode keys.
---
---@param keys string The normal-mode keys to press.
local function press(keys)
    local report = vim.o.report

    vim.o.report = 9999
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
    vim.o.report = report
end

--- Get all buffer lines.
---
---@return string[] # The current buffer lines.
local function get_lines()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

describe("indent text objects", function()
    after_each(function()
        vim.cmd.enew({ bang = true })
    end)

    it("gets same indentation until blank or different indentation lines", function()
        local buffer = make_buffer({
            "root",
            "    first",
            "    second",
            "",
            "    third",
        }, 2)

        local range = indent_text_objects.get_range(buffer, 2, "strict")

        assert.are.same({
            start_line = 2,
            start_column = 4,
            end_line = 3,
            end_column = 9,
        }, range)
    end)

    it("gets same indentation across blank lines until different indentation lines", function()
        local buffer = make_buffer({
            "root",
            "    first",
            "",
            "    second",
            "        child",
            "    third",
            "root again",
        }, 4)

        local range = indent_text_objects.get_range(buffer, 4, "ignore_blank")

        assert.are.same({
            start_line = 2,
            start_column = 4,
            end_line = 4,
            end_column = 9,
        }, range)
    end)

    it("gets ignore-blank indentation ranges both upward and downward", function()
        local buffer = make_buffer({
            "some line",
            "    foo",
            "    bar",
            "    more lines",
            "",
            "    something",
            "    text",
            "    here",
            "",
            "    more lines",
            "aaaaa",
        }, 7)

        local range = indent_text_objects.get_range(buffer, 7, "ignore_blank")

        assert.are.same({
            start_line = 2,
            start_column = 4,
            end_line = 10,
            end_column = 13,
        }, range)
    end)

    it("deletes strict same-indentation text object", function()
        make_buffer({
            "root",
            "    first",
            "    second",
            "",
            "    third",
        }, 2)

        press("dii")

        assert.are.same({
            "root",
            "    ",
            "",
            "    third",
        }, get_lines())
    end)

    it("deletes ignore-blank same-indentation text object", function()
        make_buffer({
            "root",
            "    first",
            "",
            "    second",
            "root again",
        }, 4)

        press("diI")

        assert.are.same({
            "root",
            "    ",
            "root again",
        }, get_lines())
    end)

    it("deletes ignore-blank text above and below the cursor", function()
        make_buffer({
            "some line",
            "    foo",
            "    bar",
            "    more lines",
            "",
            "    something",
            "    text",
            "    here",
            "",
            "    more lines",
            "aaaaa",
        }, 7)

        press("diI")

        assert.are.same({
            "some line",
            "    ",
            "aaaaa",
        }, get_lines())
    end)
end)

describe("argument text object", function()
    after_each(function()
        vim.cmd.enew({ bang = true })
    end)

    it("deletes first, middle, and final single-line arguments", function()
        ---@type _my.test.ObjectCase[]
        local cases = {
            { before = "(foo, bar, fizz)", cursor = 2, after = "(bar, fizz)" },
            { before = "(foo, bar, fizz)", cursor = 7, after = "(foo, fizz)" },
            { before = "(foo, bar, fizz)", cursor = 13, after = "(foo, bar)" },
        }

        for _, case in ipairs(cases) do
            make_buffer({ case.before }, 1, case.cursor)
            press("daa")
            assert.are.same({ case.after }, get_lines())
            vim.cmd.enew({ bang = true })
        end
    end)

    it("deletes multiline middle arguments", function()
        make_buffer({
            "some.function_call(",
            "    foo,",
            "       bar,",
            "    fizz)",
        }, 3, 8)

        press("daa")

        assert.are.same({
            "some.function_call(",
            "    foo,",
            "    fizz)",
        }, get_lines())
    end)

    it("deletes multiline final arguments while keeping the caller indentation", function()
        make_buffer({
            "some.function_call(",
            "    foo,",
            "       bar,",
            "    fizz)",
        }, 4, 7)

        press("daa")

        assert.are.same({
            "some.function_call(",
            "    foo,",
            "       bar,",
            ")",
        }, get_lines())
    end)

    it("ignores nested parentheses when finding the current argument", function()
        make_buffer({ "(foo, buzz=(something, here), more)" }, 1, 8)

        press("daa")

        assert.are.same({ "(foo, more)" }, get_lines())
    end)

    it("gets argument ranges with nested parentheses", function()
        local buffer = make_buffer({ "(foo, buzz=(something, here), more)" }, 1, 8)

        local range = argument_text_object.get_range(buffer, { line = 1, column = 8 })

        assert.are.same({
            start_line = 1,
            start_column = 5,
            end_line = 1,
            end_column = 28,
            replacement = "",
        }, range)
    end)
end)

describe("subvariable text object", function()
    after_each(function()
        vim.cmd.enew({ bang = true })
    end)

    it("gets underscore inner ranges", function()
        assert.are.same({
            start_column = 4,
            end_column = 6,
        }, subvariable_text_object.get_range("foo_bar_fizz", 5, "inner"))
    end)

    it("deletes underscore inner and around ranges", function()
        ---@type _my.test.ObjectCase[]
        local cases = {
            { before = "foo_bar", cursor = 6, keys = "div", after = "foo_" },
            { before = "foo_bar", cursor = 5, keys = "div", after = "foo_" },
            { before = "foo_bar", cursor = 5, keys = "dav", after = "foo" },
            { before = "foo_bar_fizz", cursor = 5, keys = "div", after = "foo__fizz" },
            { before = "foo_bar_fizz", cursor = 5, keys = "dav", after = "foo_fizz" },
            { before = "bar_fizz", cursor = 1, keys = "div", after = "_fizz" },
            { before = "bar_fizz", cursor = 1, keys = "dav", after = "fizz" },
        }

        for _, case in ipairs(cases) do
            make_buffer({ case.before }, 1, case.cursor)
            press(case.keys)
            assert.are.same({ case.after }, get_lines())
            vim.cmd.enew({ bang = true })
        end
    end)

    it("deletes camelCase inner and around ranges", function()
        ---@type _my.test.ObjectCase[]
        local cases = {
            { before = "fooBar", cursor = 5, keys = "div", after = "foo" },
            { before = "fooBar", cursor = 5, keys = "dav", after = "foo" },
            { before = "fooBarFizz", cursor = 5, keys = "div", after = "fooFizz" },
            { before = "fooBarFizz", cursor = 5, keys = "dav", after = "fooFizz" },
            { before = "barFizzBuzz", cursor = 1, keys = "div", after = "FizzBuzz" },
            { before = "barFizzBuzz", cursor = 1, keys = "dav", after = "fizzBuzz" },
        }

        for _, case in ipairs(cases) do
            make_buffer({ case.before }, 1, case.cursor)
            press(case.keys)
            assert.are.same({ case.after }, get_lines())
            vim.cmd.enew({ bang = true })
        end
    end)
end)

describe("line text object", function()
    after_each(function()
        vim.cmd.enew({ bang = true })
    end)

    it("gets the current line without its newline", function()
        local buffer = make_buffer({ "alpha", "beta", "gamma" }, 2)

        local range = line_text_object.get_range(buffer, 2)

        assert.are.same({
            start_line = 2,
            start_column = 0,
            end_line = 2,
            end_column = 3,
        }, range)
    end)

    it("deletes line contents without deleting the line", function()
        make_buffer({ "alpha", "    beta", "gamma" }, 2)

        press("dil")

        assert.are.same({ "alpha", "", "gamma" }, get_lines())
    end)

    it("visually selects the current line contents", function()
        make_buffer({ "alpha", "beta", "gamma" }, 2)

        press("vil")

        local cursor = vim.api.nvim_win_get_cursor(0)
        local visual_start = vim.fn.getpos("v")

        assert.equal("v", vim.api.nvim_get_mode().mode)
        assert.equal(2, visual_start[2])
        assert.equal(1, visual_start[3])
        assert.equal(2, cursor[1])
        assert.equal(3, cursor[2])
    end)
end)
