local core_helpers = require("modules.utilities.core_helpers")

--- Make a temporary directory for ripgrep specs.
---
---@return string # The created directory.
local function make_directory()
    local root = vim.fn.tempname()

    assert.equal(1, vim.fn.mkdir(root, "p"))

    return root
end

describe("ripgrep quickfix", function()
    local original_system
    local original_exists_command
    local original_ripgrep_executable

    before_each(function()
        original_system = vim.system
        original_exists_command = core_helpers.exists_command
        original_ripgrep_executable = core_helpers._RIPGREP_EXECUTABLE
        core_helpers._RIPGREP_EXECUTABLE = "rg"
        rawset(core_helpers, "exists_command", function()
            return true
        end)
        vim.fn.setqflist({}, "r")
    end)

    after_each(function()
        vim.system = original_system
        rawset(core_helpers, "exists_command", original_exists_command)
        core_helpers._RIPGREP_EXECUTABLE = original_ripgrep_executable
        vim.fn.setqflist({}, "r")
        vim.cmd("silent! cclose")
    end)

    it("displays ripgrep quickfix paths relative to the requested search root", function()
        local root = make_directory()
        local feature = vim.fs.joinpath(root, "lua", "modules", "features", "core_editor_setup.lua")
        local utility = vim.fs.joinpath(root, "lua", "modules", "utilities", "core_helpers.lua")

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.system = function(_, _, callback)
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

            return { pid = 123 }
        end

        core_helpers.run_ripgrep({ "something", root }, { display_root = root })

        assert.True(vim.wait(1000, function()
            return #vim.fn.getqflist() == 2
        end))

        local quickfix = vim.fn.getqflist()

        assert.equal(feature, quickfix[1].filename)
        assert.equal("lua/modules/features/core_editor_setup.lua", quickfix[1].module)
        assert.equal(utility, quickfix[2].filename)
        assert.equal("lua/modules/utilities/core_helpers.lua", quickfix[2].module)

        local quickfix_window = vim.fn.getqflist({ winid = true }).winid
        local quickfix_buffer = vim.api.nvim_win_get_buf(quickfix_window)
        local lines = vim.api.nvim_buf_get_lines(quickfix_buffer, 0, -1, false)

        assert.matches("^lua/modules/features/core_editor_setup.lua|867 col 62|", lines[1])
        assert.matches("^lua/modules/utilities/core_helpers.lua|1308 col 25|", lines[2])
    end)
end)
