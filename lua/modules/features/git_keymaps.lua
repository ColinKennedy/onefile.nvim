local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
--- git-related keymaps
--- Run `git add` on the current Vim buffer.
function _P.git_add_current_buffer()
    local buffer = 0
    local path = vim.api.nvim_buf_get_name(buffer)
    local directory = vim.fs.dirname(path)

    _P.run_git_command({ "add", "--force", path }, directory)
end

--- Run `git commit` on the repository of the current working directory.
function _P.git_commit_current_repository()
    local message = vim.fn.input("Enter a commit message: ")

    if message == "" then
        vim.notify(string.format("User cancelled the git commit", vim.log.levels.INFO))

        return
    end

    _P.run_git_command({ "commit", "-m", message }, vim.fn.getcwd())
end

--- Run `git reset` on all hunks on the current buffer.
function _P.git_reset_current_buffer()
    local buffer = 0
    local path = vim.api.nvim_buf_get_name(buffer)
    local directory = vim.fs.dirname(path)

    _P.run_git_command({ "reset", path }, directory)
end

--- Run git sub-`command` on `directory`.
---
---@param command string[]
---    Some git command. e.g. `{"add", "-u"}`, from a "git add -u" command.
---@param directory string
---    The path on-disk that is on or underneath a git repository.
---
function _P.run_git_command(command, directory)
    --- Print `object` to the user.
    ---
    ---@param object any Some object to inspect and print.
    ---
    local function _on_fail(object)
        vim.notify(string.format('Command failed: Got "%s" error.', vim.inspect(object)), vim.log.levels.ERROR)
    end

    ---@type string[]
    local full_command = {}
    vim.list_extend(full_command, { _GIT_EXECUTABLE, "-C", directory })
    vim.list_extend(full_command, command)

    vim.system(full_command, { text = true }, function(object)
        if object.code ~= 0 then
            vim.schedule(function()
                _on_fail(object)
            end)

            return
        end
    end)
end

vim.keymap.set(
    "n",
    "<leader>gac",
    _P.git_add_current_buffer,
    { desc = "Run `git add` for all hunks in the current buffer." }
)

vim.keymap.set(
    "n",
    "<leader>gcm",
    _P.git_commit_current_repository,
    { desc = "Run `git commit` for the currently-staged files." }
)

vim.keymap.set(
    "n",
    "<leader>grc",
    _P.git_reset_current_buffer,
    { desc = "Run `git reset` for all hunks in the current buffer." }
)

vim.keymap.set("n", "<leader>gsp", _P.push_stash_by_name, { desc = "Create a new, named git stash." })
vim.keymap.set("n", "<leader>gsa", _P.show_git_stashes, { desc = "Show the git stashes that are available." })
vim.keymap.set(
    "n",
    "<leader>gap",
    _P.run_git_add_p,
    { noremap = true, silent = true, desc = "Create a terminal and run `git add -p` on it." }
)
vim.keymap.set(
    "n",
    "<leader>gph",
    _P.run_git_push,
    { noremap = true, silent = true, desc = "Push the committed to changes to the remote branch." }
)
vim.keymap.set(
    "n",
    "<leader>gpl",
    _P.run_git_pull,
    { noremap = true, silent = true, desc = "Push the latest commits from the remote branch." }
)
end)
