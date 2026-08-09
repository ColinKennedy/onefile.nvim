local git_command = require("modules.features.git_command")

---@class _my.git_command_spec.JobOptions The `jobstart()` options that `:Git` passes.
---@field term boolean? If `true`, run the job inside a terminal buffer.
---@field on_exit (fun(job: integer, code: integer, event: string): nil)? The job-exit callback.

--- Get the shared core helper module.
---
---@return _my.core_helpers # The core helpers module.
local function get_core_helpers()
    return require("modules.utilities.core_helpers")
end

describe("git command", function()
    ---@type fun(cmd: string | string[], opts: _my.git_command_spec.JobOptions?): integer
    local original_jobstart = nil
    ---@type string
    local original_git_executable = nil

    before_each(function()
        original_jobstart = vim.fn.jobstart
        original_git_executable = get_core_helpers().GIT_EXECUTABLE
    end)

    after_each(function()
        vim.fn.jobstart = original_jobstart
        get_core_helpers().GIT_EXECUTABLE = original_git_executable
        vim.cmd.stopinsert()
        vim.cmd("silent! only!")
        vim.cmd.enew({ bang = true })
    end)

    it("builds shell-free argv commands for Windows Git paths", function()
        local command = git_command._build_git_command("C:\\Program Files\\Git\\cmd\\git.exe", { "branch", "-a" })

        assert.are.same({ "C:\\Program Files\\Git\\cmd\\git.exe", "branch", "-a" }, command)
    end)

    it("runs :Git with argv instead of a shell command string", function()
        ---@type string[]?
        local captured_command = nil
        ---@type _my.git_command_spec.JobOptions?
        local captured_options = nil

        get_core_helpers().GIT_EXECUTABLE = "C:\\Program Files\\Git\\cmd\\git.exe"
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.jobstart = function(command, options)
            captured_command = command
            captured_options = options
            return 1
        end

        vim.cmd("Git branch -a")

        assert.are.same({ "C:\\Program Files\\Git\\cmd\\git.exe", "branch", "-a" }, captured_command)
        assert.is_not_nil(captured_options)
        assert.is_true(captured_options --[[@as _my.git_command_spec.JobOptions]].term)
        assert.is_nil(captured_options --[[@as _my.git_command_spec.JobOptions]].on_exit)
    end)
end)
