local native_dispatch = require("modules.plugins.native_dispatch")

--- Make a command-args table for calling command callbacks directly.
---
---@param args string Raw command arguments.
---@return vim.api.keyset.create_user_command.command_args # A complete command args table.
local function make_command_args(args)
    return {
        name = "Dispatch",
        args = args,
        fargs = {},
        nargs = "+",
        bang = false,
        line1 = 1,
        line2 = 1,
        range = 0,
        count = -1,
        reg = "",
        mods = "",
        smods = {},
    }
end

describe("native dispatch", function()
    local original_jobstart
    local original_notify
    local original_system
    local original_systemlist
    local original_dispatch_system
    local original_dispatch_systemlist
    local notifications

    before_each(function()
        original_jobstart = vim.fn.jobstart
        original_notify = vim.notify
        original_system = vim.fn.system
        original_systemlist = vim.fn.systemlist
        original_dispatch_system = native_dispatch._P.system
        original_dispatch_systemlist = native_dispatch._P.systemlist
        notifications = {}

        rawset(vim, "notify", function(message, level)
            table.insert(notifications, { message = message, level = level })
        end)
    end)

    after_each(function()
        vim.fn.jobstart = original_jobstart
        vim.fn.system = original_system
        vim.fn.systemlist = original_systemlist
        rawset(native_dispatch._P, "system", original_dispatch_system)
        rawset(native_dispatch._P, "systemlist", original_dispatch_systemlist)
        rawset(vim, "notify", original_notify)
        vim.fn.setqflist({}, "r")
        vim.cmd("silent! cclose")
    end)

    it("parses flags and shell-like command arguments without evaluating pipes", function()
        local options =
            assert(native_dispatch._P.parse_arguments([[--compiler=pytest --display=on_error rg "foo bar" | head]]))

        assert.equal("pytest", options.compiler)
        assert.equal("on_error", options.display)
        assert.are.same({ "rg", "foo bar", "|", "head" }, options.command)
        assert.equal("rg foo bar | head", options.raw_command)
    end)

    it("parses jump-first as a dispatch flag", function()
        local options = assert(native_dispatch._P.parse_arguments("--jump-first rg needle"))

        assert.is_true(options.jump_first)
        assert.are.same({ "rg", "needle" }, options.command)
    end)

    it("loads parsed and unparsed output into quickfix with a dispatch title", function()
        vim.o.errorformat = "%f:%l:%c:%m,%f:%l:%m"

        native_dispatch._P.finish({
            command = { "rg", "needle" },
            raw_command = "rg needle",
            display = "never",
        }, {
            "plain setup log",
            "lua/example.lua:7:3:found needle",
            "plain teardown log",
        })

        local quickfix = vim.fn.getqflist({ title = true, items = true })

        assert.equal("Dispatch: rg needle", quickfix.title)
        assert.equal(3, #quickfix.items)
        assert.equal(0, quickfix.items[1].valid)
        assert.equal("plain setup log", quickfix.items[1].text)
        assert.equal(1, quickfix.items[2].valid)
        assert.equal(7, quickfix.items[2].lnum)
        assert.equal(3, quickfix.items[2].col)
        assert.equal("found needle", quickfix.items[2].text)
        assert.equal(0, quickfix.items[3].valid)
        assert.equal("plain teardown log", quickfix.items[3].text)
    end)

    it("jumps to the first parsed quickfix item when requested", function()
        local path = vim.fn.tempname() .. ".lua"

        vim.fn.writefile({ "first", "second", "third" }, path)
        vim.o.errorformat = "%f:%l:%c:%m,%f:%l:%m"

        native_dispatch._P.finish({
            command = { "rg", "needle" },
            raw_command = "rg needle",
            display = "never",
            jump_first = true,
        }, {
            "plain setup log",
            path .. ":2:1:found needle",
        })

        assert.equal(path, vim.api.nvim_buf_get_name(0))
        assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))

        vim.fn.delete(path)
    end)

    it("does not jump to a source file when jump-first has no parsed quickfix item", function()
        vim.o.errorformat = "%f:%l:%c:%m,%f:%l:%m"

        native_dispatch._P.finish({
            command = { "echo", "hello" },
            raw_command = "echo hello",
            display = "never",
            jump_first = true,
        }, {
            "plain setup log",
        })

        assert.equal("qf", vim.bo.filetype)
    end)

    it("does not open quickfix and notifies when a dispatch command passes", function()
        native_dispatch._P.finish({
            command = { "make", "luacheck" },
            raw_command = "make luacheck",
            display = "on_error",
        }, {
            "Checking lua/modules/example.lua OK",
        }, 0)

        local quickfix = vim.fn.getqflist({ title = true, items = true })

        assert.equal("Dispatch: make luacheck", quickfix.title)
        assert.are.same({}, quickfix.items)
        assert.equal(vim.log.levels.INFO, notifications[1].level)
        assert.equal("Dispatch passed: make luacheck", notifications[1].message)
        assert.Not.equal("qf", vim.bo.filetype)
    end)

    it("uses ad-hoc compilers and restores compiler options afterward", function()
        local original_buffer = vim.api.nvim_get_current_buf()
        local original_errorformat = vim.o.errorformat
        local original_makeprg = vim.o.makeprg
        vim.b[original_buffer].current_compiler = "original"
        vim.o.errorformat = "%m"
        vim.o.makeprg = "original_make"

        native_dispatch._P.finish({
            command = { "rg", "needle" },
            raw_command = "rg needle",
            compiler = "vimgrep",
            display = "never",
        }, {
            "lua/example.lua:9:4:found needle",
        })

        local quickfix = vim.fn.getqflist()

        assert.equal(1, quickfix[1].valid)
        assert.equal(9, quickfix[1].lnum)
        assert.equal(4, quickfix[1].col)
        assert.equal("original", vim.b[original_buffer].current_compiler)
        assert.equal("%m", vim.o.errorformat)
        assert.equal("original_make", vim.o.makeprg)

        vim.o.errorformat = original_errorformat
        vim.o.makeprg = original_makeprg
        vim.b[original_buffer].current_compiler = nil
    end)

    it("runs concurrent argv jobs through jobstart", function()
        local captured = {}

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.jobstart = function(command, options)
            table.insert(captured, { command = command, options = options })
            options.on_stdout(1, { "plain log" })
            options.on_exit(1, 0)

            return #captured
        end

        native_dispatch.run({
            command = { "make", "one" },
            raw_command = "make one",
            display = "never",
        })
        native_dispatch.run({
            command = { "make", "two" },
            raw_command = "make two",
            display = "never",
        })

        vim.wait(100, function()
            return #captured == 2
        end)

        assert.are.same({ "make", "one" }, captured[1].command)
        assert.are.same({ "make", "two" }, captured[2].command)
        assert.is_function(captured[1].options.on_stdout)
        assert.is_function(captured[1].options.on_exit)
    end)

    it("closes job stdin so ripgrep searches files instead of waiting for input", function()
        ---@type table?
        local captured_options = nil

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.jobstart = function(_, options)
            captured_options = options
            options.on_exit(1, 0)

            return 1
        end

        native_dispatch.run({
            command = { "rg", "something" },
            raw_command = "rg something",
            display = "never",
        })

        local options = assert(captured_options)

        assert.equal("null", options.stdin)
    end)

    it("does not open a display pane for on-error dispatch output", function()
        local original_open_display = native_dispatch._P.open_display
        local opened_display = false

        rawset(native_dispatch._P, "open_display", function()
            opened_display = true

            return {
                close = function() end,
                write = function() end,
            }
        end)

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.jobstart = function(_, options)
            options.on_stdout(1, { "lua/example.lua:4:2:error", "" })
            options.on_exit(1, 1)

            return 1
        end

        native_dispatch.run({
            command = { "fake" },
            raw_command = "fake",
            compiler = "vimgrep",
            display = "on_error",
        })

        vim.wait(100, function()
            return #vim.fn.getqflist() > 0
        end)

        rawset(native_dispatch._P, "open_display", original_open_display)

        assert.is_false(opened_display)
        assert.equal("qf", vim.bo.filetype)
    end)

    it("joins partial job output chunks before loading quickfix", function()
        vim.o.errorformat = "%f:%l:%c:%m,%f:%l:%m"

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.jobstart = function(_, options)
            options.on_stdout(1, { "lua/exam" })
            options.on_stdout(1, { "ple.lua:4:2:split diagnostic", "plain" })
            options.on_stdout(1, { " log" })
            options.on_exit(1, 0)

            return 1
        end

        native_dispatch.run({
            command = { "fake" },
            raw_command = "fake",
            display = "never",
        })

        vim.wait(100, function()
            return #vim.fn.getqflist() == 2
        end)

        local quickfix = vim.fn.getqflist()

        assert.equal(1, quickfix[1].valid)
        assert.equal(4, quickfix[1].lnum)
        assert.equal(2, quickfix[1].col)
        assert.equal("split diagnostic", quickfix[1].text)
        assert.equal(0, quickfix[2].valid)
        assert.equal("plain log", quickfix[2].text)
    end)

    it("keeps tmux display panes smaller than the maximum at their natural height", function()
        local resize_commands = {}

        rawset(native_dispatch._P, "systemlist", function()
            return { "10" }
        end)
        rawset(native_dispatch._P, "system", function(command)
            table.insert(resize_commands, command)

            return ""
        end)

        native_dispatch._P.clamp_tmux_display_height("%7")

        assert.are.same({}, resize_commands)
    end)

    it("clamps oversized tmux display panes to forty rows", function()
        local resize_commands = {}

        rawset(native_dispatch._P, "systemlist", function()
            return { "80" }
        end)
        rawset(native_dispatch._P, "system", function(command)
            table.insert(resize_commands, command)

            return ""
        end)

        native_dispatch._P.clamp_tmux_display_height("%7")

        assert.are.same({
            { "tmux", "resize-pane", "-t", "%7", "-y", "15" },
        }, resize_commands)
    end)

    it("reports invalid dispatch flags", function()
        native_dispatch.dispatch(make_command_args("--display=sometimes make test"))

        assert.equal('Invalid Dispatch display mode "sometimes".', notifications[1].message)
    end)
end)
