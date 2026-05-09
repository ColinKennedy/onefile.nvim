local git_command = require("modules.features.git_command")

--- Get the shared core helper module.
---
---@return table # The core helpers module.
local function get_core_helpers()
    return require("modules.utilities.core_helpers")
end

describe("git command", function()
    local original_jobstart = nil
    local original_git_executable = nil

    before_each(function()
        original_jobstart = vim.fn.jobstart
        original_git_executable = get_core_helpers()._GIT_EXECUTABLE
    end)

    after_each(function()
        vim.fn.jobstart = original_jobstart
        get_core_helpers()._GIT_EXECUTABLE = original_git_executable
        vim.cmd.stopinsert()
        vim.cmd("silent! only!")
        vim.cmd.enew({ bang = true })
    end)

    it("builds shell-free argv commands for Windows Git paths", function()
        local command = git_command.build_git_command("C:\\Program Files\\Git\\cmd\\git.exe", { "branch", "-a" })

        assert.are.same({ "C:\\Program Files\\Git\\cmd\\git.exe", "branch", "-a" }, command)
    end)

    it("runs :Git with argv instead of a shell command string", function()
        local captured_command = nil
        ---@type table?
        local captured_options = nil

        get_core_helpers()._GIT_EXECUTABLE = "C:\\Program Files\\Git\\cmd\\git.exe"
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.jobstart = function(command, options)
            captured_command = command
            captured_options = options
            return 1
        end

        vim.cmd("Git branch -a")

        assert.are.same({ "C:\\Program Files\\Git\\cmd\\git.exe", "branch", "-a" }, captured_command)
        assert.is_not_nil(captured_options)
        assert.is_true(captured_options --[[@as table]].term)
        assert.is_nil(captured_options --[[@as table]].on_exit)
    end)
end)
