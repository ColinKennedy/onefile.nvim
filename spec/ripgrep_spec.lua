local core_helpers = require("modules.utilities.core_helpers")

--- Make a temporary directory for ripgrep specs.
---
---@return string # The created directory.
local function make_directory()
    local root = vim.fn.tempname()

    assert.equal(1, vim.fn.mkdir(root, "p"))

    return root
end

--- Run a Git command inside `root`.
---
---@param root string The Git repository root.
---@param arguments string[] The Git command arguments.
local function run_git(root, arguments)
    local command = { "git", "-C", root }
    vim.list_extend(command, arguments)

    local result = vim.system(command, { text = true }):wait()

    assert.equal(0, result.code, result.stderr)
end

describe("ripgrep quickfix", function()
    local original_system
    local original_exists_command
    local original_notify
    local original_ripgrep_executable

    before_each(function()
        original_system = vim.system
        original_exists_command = core_helpers.exists_command
        original_notify = vim.notify
        original_ripgrep_executable = core_helpers.RIPGREP_EXECUTABLE
        core_helpers.RIPGREP_EXECUTABLE = "rg"
        rawset(core_helpers, "exists_command", function()
            return true
        end)
        vim.fn.setqflist({}, "r")
    end)

    after_each(function()
        vim.system = original_system
        vim.notify = original_notify
        rawset(core_helpers, "exists_command", original_exists_command)
        core_helpers.RIPGREP_EXECUTABLE = original_ripgrep_executable
        vim.fn.setqflist({}, "r")
        vim.cmd("silent! cclose")
    end)

    it("displays ripgrep quickfix paths relative to the requested search root", function()
        local root = make_directory()
        local feature = vim.fs.joinpath(root, "lua", "modules", "features", "core_editor_setup.lua")
        local utility = vim.fs.joinpath(root, "lua", "modules", "utilities", "core_helpers.lua")

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.system = function(_, options, callback)
            if type(options) == "function" then
                callback = options
            end

            if not callback then
                return {
                    pid = 123,
                    wait = function()
                        return { code = 0, stdout = "", stderr = "" }
                    end,
                }
            end

            vim.schedule(function()
                callback({
                    code = 0,
                    stdout = table.concat({
                        feature .. ":867:62:local hit",
                        utility .. ":1308:25:root hit",
                    }, "\n"),
                    stderr = "",
                })
            end)

            return {
                pid = 123,
                wait = function()
                    return { code = 0, stdout = "", stderr = "" }
                end,
            }
        end

        core_helpers.run_ripgrep({ "something", root }, { display_root = root })

        assert.True(vim.wait(1000, function()
            return #vim.fn.getqflist() == 2
        end))

        local quickfix = vim.fn.getqflist()

        assert.equal(feature, vim.api.nvim_buf_get_name(quickfix[1].bufnr))
        assert.equal("lua/modules/features/core_editor_setup.lua", quickfix[1].module)
        assert.equal(utility, vim.api.nvim_buf_get_name(quickfix[2].bufnr))
        assert.equal("lua/modules/utilities/core_helpers.lua", quickfix[2].module)

        local quickfix_window = vim.fn.getqflist({ winid = true }).winid
        local quickfix_buffer = vim.api.nvim_win_get_buf(quickfix_window)
        local lines = vim.api.nvim_buf_get_lines(quickfix_buffer, 0, -1, false)

        assert.matches("^lua/modules/features/core_editor_setup.lua|867 col 62|", lines[1])
        assert.matches("^lua/modules/utilities/core_helpers.lua|1308 col 25|", lines[2])
    end)

    it("does not call getcwd from the async ripgrep callback", function()
        local original_cwd = vim.fn.getcwd()
        local root = make_directory()
        local path = vim.fs.joinpath(root, "relative.lua")
        local callback_
        local original_getcwd = vim.fn.getcwd

        vim.cmd.tcd(root)

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.system = function(_, options, callback)
            callback_ = type(options) == "function" and options or callback

            return {
                pid = 123,
                wait = function()
                    return { code = 0, stdout = "", stderr = "" }
                end,
            }
        end

        core_helpers.run_ripgrep({ "needle" }, { display_root = root })

        rawset(vim.fn, "getcwd", function()
            error("getcwd must not run from the ripgrep callback")
        end)
        assert(callback_)({
            code = 0,
            stdout = "relative.lua:1:1:needle",
            stderr = "",
        })
        rawset(vim.fn, "getcwd", original_getcwd)

        assert.True(vim.wait(1000, function()
            return #vim.fn.getqflist() == 1
        end))

        local quickfix = vim.fn.getqflist()

        assert.equal(path, vim.api.nvim_buf_get_name(quickfix[1].bufnr))
        vim.cmd.tcd(original_cwd)
        vim.fn.delete(root, "rf")
    end)

    it("displays Rg quickfix paths relative to the command cwd by default", function()
        local original_cwd = vim.fn.getcwd()
        local root = make_directory()
        local path = vim.fs.joinpath(root, "lua", "modules", "utilities", "core_helpers.lua")

        assert.equal(1, vim.fn.mkdir(vim.fs.dirname(path), "p"))
        vim.cmd.tcd(root)

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.system = function(_, options, callback)
            callback = type(options) == "function" and options or callback

            if callback then
                vim.schedule(function()
                    callback({
                        code = 0,
                        stdout = path .. ":907:65:some hit",
                        stderr = "",
                    })
                end)
            end

            return {
                pid = 123,
                wait = function()
                    return { code = 0, stdout = "", stderr = "" }
                end,
            }
        end

        core_helpers.run_ripgrep_command({ args = "something" })

        assert.True(vim.wait(1000, function()
            return #vim.fn.getqflist() == 1
        end))

        local quickfix = vim.fn.getqflist()
        local quickfix_window = vim.fn.getqflist({ winid = true }).winid
        local quickfix_buffer = vim.api.nvim_win_get_buf(quickfix_window)
        local lines = vim.api.nvim_buf_get_lines(quickfix_buffer, 0, -1, false)

        assert.equal(path, vim.api.nvim_buf_get_name(quickfix[1].bufnr))
        assert.equal("lua/modules/utilities/core_helpers.lua", quickfix[1].module)
        assert.matches("^lua/modules/utilities/core_helpers.lua|907 col 65|", lines[1])

        vim.cmd.tcd(original_cwd)
        vim.fn.delete(root, "rf")
    end)

    it("displays Rg quickfix paths relative to a command cwd with spaces", function()
        local original_cwd = vim.fn.getcwd()
        local root_parent = make_directory()
        local root = vim.fs.joinpath(root_parent, "Benchmark CPU")
        local path = vim.fs.joinpath(root, "vaults", "personal", "note.md")
        local captured_command

        assert.equal(1, vim.fn.mkdir(vim.fs.dirname(path), "p"))
        vim.cmd.tcd(root)

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.system = function(command, options, callback)
            if command[1] == "rg" then
                captured_command = command
            end
            callback = type(options) == "function" and options or callback

            if callback then
                vim.schedule(function()
                    callback({
                        code = 0,
                        stdout = path .. ":1:1:some hit",
                        stderr = "",
                    })
                end)
            end

            return {
                pid = 123,
                wait = function()
                    return { code = 0, stdout = "", stderr = "" }
                end,
            }
        end

        core_helpers.run_ripgrep_command({ args = "something" })

        assert.True(vim.wait(1000, function()
            return #vim.fn.getqflist() == 1
        end))

        local quickfix = vim.fn.getqflist()

        assert.same({ "rg", "--vimgrep", "--smart-case", "--no-messages", "something" }, captured_command)
        assert.equal(path, vim.api.nvim_buf_get_name(quickfix[1].bufnr))
        assert.equal("vaults/personal/note.md", quickfix[1].module)

        vim.cmd.tcd(original_cwd)
        vim.fn.delete(root_parent, "rf")
    end)

    it("displays Rrg quickfix paths relative to the Git repository root", function()
        local original_cwd = vim.fn.getcwd()
        local root = make_directory()
        local nested = vim.fs.joinpath(root, "lua", "modules")
        local path = vim.fs.joinpath(root, "lua", "modules", "utilities", "core_helpers.lua")

        assert.equal(1, vim.fn.mkdir(vim.fs.dirname(path), "p"))
        run_git(root, { "init" })
        vim.cmd.tcd(nested)

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.system = function(command, options, callback)
            if command[1] == "git" then
                return original_system(command, options, callback)
            end

            callback = type(options) == "function" and options or callback

            if callback then
                vim.schedule(function()
                    callback({
                        code = 0,
                        stdout = path .. ":907:65:some hit",
                        stderr = "",
                    })
                end)
            end

            return {
                pid = 123,
                wait = function()
                    return { code = 0, stdout = "", stderr = "" }
                end,
            }
        end

        vim.cmd.Rrg("something")

        assert.True(vim.wait(1000, function()
            return #vim.fn.getqflist() == 1
        end))

        local quickfix = vim.fn.getqflist()
        local quickfix_window = vim.fn.getqflist({ winid = true }).winid
        local quickfix_buffer = vim.api.nvim_win_get_buf(quickfix_window)
        local lines = vim.api.nvim_buf_get_lines(quickfix_buffer, 0, -1, false)

        assert.equal(path, vim.api.nvim_buf_get_name(quickfix[1].bufnr))
        assert.equal("lua/modules/utilities/core_helpers.lua", quickfix[1].module)
        assert.matches("^lua/modules/utilities/core_helpers.lua|907 col 65|", lines[1])

        vim.cmd.tcd(original_cwd)
        vim.fn.delete(root, "rf")
    end)

    it("passes Rrg repository roots with spaces as one ripgrep argument", function()
        local original_cwd = vim.fn.getcwd()
        local root_parent = make_directory()
        local root = vim.fs.joinpath(root_parent, "Benchmark CPU")
        local nested = vim.fs.joinpath(root, "vaults", "personal")
        local path = vim.fs.joinpath(nested, "note.md")
        local captured_command

        assert.equal(1, vim.fn.mkdir(vim.fs.dirname(path), "p"))
        run_git(root, { "init" })
        vim.cmd.tcd(nested)

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.system = function(command, options, callback)
            if command[1] == "git" then
                return original_system(command, options, callback)
            end

            captured_command = command
            callback = type(options) == "function" and options or callback

            if callback then
                vim.schedule(function()
                    callback({
                        code = 0,
                        stdout = path .. ":1:1:some hit",
                        stderr = "",
                    })
                end)
            end

            return {
                pid = 123,
                wait = function()
                    return { code = 0, stdout = "", stderr = "" }
                end,
            }
        end

        vim.cmd.Rrg("something")

        assert.True(vim.wait(1000, function()
            return #vim.fn.getqflist() == 1
        end))

        local quickfix = vim.fn.getqflist()

        assert.equal(root, captured_command[#captured_command])
        assert.same({
            "rg",
            "--vimgrep",
            "--smart-case",
            "--no-messages",
            "something",
            root,
        }, captured_command)
        assert.equal(path, vim.api.nvim_buf_get_name(quickfix[1].bufnr))
        assert.equal("vaults/personal/note.md", quickfix[1].module)

        vim.cmd.tcd(original_cwd)
        vim.fn.delete(root_parent, "rf")
    end)

    it("does not fail ripgrep when stderr only has filesystem warnings", function()
        local root = make_directory()
        local path = vim.fs.joinpath(root, "ok.txt")
        local notifications = {}

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.notify = function(message, level)
            table.insert(notifications, { message = message, level = level })
        end

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.system = function(_, options, callback)
            callback = type(options) == "function" and options or callback

            if callback then
                vim.schedule(function()
                    callback({
                        code = 2,
                        stdout = path .. ":1:1:some hit",
                        stderr = "rg: ./vaults\\personal\\Benchmark CPU : "
                            .. "The system cannot find the file specified. (os error 2)\n",
                    })
                end)
            end

            return {
                pid = 123,
                wait = function()
                    return { code = 0, stdout = "", stderr = "" }
                end,
            }
        end

        core_helpers.run_ripgrep({ "something", root }, { display_root = root })

        assert.True(vim.wait(1000, function()
            return #vim.fn.getqflist() == 1
        end))

        local quickfix = vim.fn.getqflist()

        assert.equal(path, vim.api.nvim_buf_get_name(quickfix[1].bufnr))
        assert.are.same({}, notifications)

        vim.fn.delete(root, "rf")
    end)

    it("keeps ripgrep matches when warnings were hidden from stderr", function()
        local root = make_directory()
        local path = vim.fs.joinpath(root, "ok.txt")
        local notifications = {}

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.notify = function(message, level)
            table.insert(notifications, { message = message, level = level })
        end

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.system = function(_, options, callback)
            callback = type(options) == "function" and options or callback

            if callback then
                vim.schedule(function()
                    callback({
                        code = 2,
                        stdout = path .. ":1:1:some hit",
                        stderr = "",
                    })
                end)
            end

            return {
                pid = 123,
                wait = function()
                    return { code = 0, stdout = "", stderr = "" }
                end,
            }
        end

        core_helpers.run_ripgrep({ "something", root }, { display_root = root })

        assert.True(vim.wait(1000, function()
            return #vim.fn.getqflist() == 1
        end))

        local quickfix = vim.fn.getqflist()

        assert.equal(path, vim.api.nvim_buf_get_name(quickfix[1].bufnr))
        assert.are.same({}, notifications)

        vim.fn.delete(root, "rf")
    end)

    it("treats exit code 1 as no ripgrep matches instead of an error", function()
        local notifications = {}

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.notify = function(message, level)
            table.insert(notifications, { message = message, level = level })
        end

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.system = function(_, options, callback)
            callback = type(options) == "function" and options or callback

            if callback then
                vim.schedule(function()
                    callback({
                        code = 1,
                        stdout = "",
                        stderr = "",
                    })
                end)
            end

            return {
                pid = 123,
                wait = function()
                    return { code = 0, stdout = "", stderr = "" }
                end,
            }
        end

        core_helpers.run_ripgrep({ "no-such-pattern" })

        assert.True(vim.wait(1000, function()
            return #notifications == 1
        end))

        assert.are.same({
            {
                message = "No ripgrep matches found.",
                level = vim.log.levels.INFO,
            },
        }, notifications)
        assert.are.same({}, vim.fn.getqflist())
    end)
end)
