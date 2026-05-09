local git_status = require("modules.utilities.git_status")

--- Run a Git command for a test repository.
---
---@param root string The repository root to run from.
---@param arguments string[] The Git arguments to pass.
---@return string # The command stdout.
local function run_git(root, arguments)
    local command = { "git", "-C", root }

    vim.list_extend(command, arguments)

    local result = vim.system(command, { text = true }):wait()

    assert.equal(0, result.code, result.stderr)

    return result.stdout or ""
end

--- Write a file for a test repository.
---
---@param path string The path to write.
---@param text string The file contents.
local function write_file(path, text)
    local file = assert(vim.uv.fs_open(path, "w", 438))

    assert(vim.uv.fs_write(file, text, 0))
    assert(vim.uv.fs_close(file))
end

--- Make a temporary Git repository.
---
---@return string # The created repository root.
local function make_repository()
    local root = vim.fn.tempname()

    assert.equal(1, vim.fn.mkdir(root, "p"))

    run_git(root, { "init" })
    run_git(root, { "config", "user.email", "test@example.com" })
    run_git(root, { "config", "user.name", "Test User" })

    write_file(vim.fs.joinpath(root, "file.txt"), "one\n")
    run_git(root, { "add", "file.txt" })
    run_git(root, { "commit", "-m", "init" })

    return root
end

--- Wait for the Git statusline to contain `text`.
---
---@param root string The repository root to refresh.
---@param text string The text to wait for.
---@return string # The latest statusline text.
local function wait_for_statusline(root, text)
    local statusline = ""

    git_status.refresh(root)

    local found = vim.wait(1000, function()
        statusline = git_status.get_statusline(root)

        return statusline:find(text, 1, true) ~= nil
    end, 20)

    assert.True(found)

    return statusline
end

describe("modules.utilities.git_status", function()
    it("labels rebase-apply applying state as git am", function()
        local root = make_repository()
        local rebase_apply = vim.fs.joinpath(root, ".git", "rebase-apply")

        assert.equal(1, vim.fn.mkdir(rebase_apply, "p"))
        write_file(vim.fs.joinpath(rebase_apply, "applying"), "")
        write_file(vim.fs.joinpath(rebase_apply, "next"), "1\n")
        write_file(vim.fs.joinpath(rebase_apply, "last"), "1\n")

        local statusline = wait_for_statusline(root, "am 1/1")

        assert.is_nil(statusline:find("rebase", 1, true))
    end)
end)
