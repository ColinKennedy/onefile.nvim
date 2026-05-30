--- Register a :Git command that runs git output in a scratch buffer.

local M = {}

--- Find some (reasonable, not exhaustive) git auto-complete values.
---
---@param _ any Some ignored parameter.
---@param line string The raw command-line text to get auto-complete results for.
---@return string[] # The basic subcommands.
local function _get_git_completion(_, line)
    if line:match(" .+ ") ~= nil then
        -- NOTE: If we've gotten to `:Git foo ` then don't auto-complete any more.
        return {}
    end

    return { "add", "commit", "diff", "log", "pull", "push", "status" }
end

--- Build a shell-free Git command argv list.
---
---@param executable string The Git executable path.
---@param arguments string[] The arguments passed to `:Git`.
---@return string[] # The argv list to pass to `jobstart()`.
function M.build_git_command(executable, arguments)
    ---@type string[]
    local command = { executable }

    for _, argument in ipairs(arguments) do
        table.insert(command, argument)
    end

    return command
end

--- A simple `git` wrapper for Neovim.
---
---@param opts vim.api.keyset.create_user_command.command_args The user-command options to read from.
local function _run_in_git(opts)
    local command = M.build_git_command(require("modules.utilities.core_helpers")._GIT_EXECUTABLE, opts.fargs)

    vim.cmd.split()
    vim.cmd.enew()

    vim.fn.jobstart(command, {
        term = true,
    })

    -- NOTE: Switch to terminal mode so we can immediately begin typing.
    vim.cmd.startinsert()
end

vim.api.nvim_create_user_command("G", _run_in_git, {
    desc = "A basic git wrapper.",
    nargs = "+",
    complete = _get_git_completion,
})

vim.api.nvim_create_user_command("Git", _run_in_git, {
    desc = "A basic git wrapper.",
    nargs = "+",
    complete = _get_git_completion,
})

return M
