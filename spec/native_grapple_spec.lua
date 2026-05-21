local core_helpers = require("modules.utilities.core_helpers")
require("modules.utilities.git_diff")
local native_grapple = require("modules.plugins.native_grapple.core")

--- Run a Git command inside `root`.
---
---@param root string The Git repository root.
---@param arguments string[] The Git arguments to run after `-C root`.
---@return string # The command's standard output.
local function run_git(root, arguments)
    local command = { "git", "-C", root }
    vim.list_extend(command, arguments)

    local result = vim.system(command, { text = true }):wait()

    assert.equal(0, result.code, result.stderr)

    return result.stdout or ""
end

--- Write exact text to `path`.
---
---@param path string The path to write.
---@param text string The file contents.
local function write_text(path, text)
    local file = assert(vim.uv.fs_open(path, "w", 438))
    assert(vim.uv.fs_write(file, text, 0))
    assert(vim.uv.fs_close(file))
end

--- Create a temporary Git repository with two branches.
---
---@return string root The temporary repository root.
---@return string branch The default Git branch name.
local function make_repository()
    local root = vim.fn.tempname()
    assert.equal(1, vim.fn.mkdir(root, "p"))

    run_git(root, { "init" })
    run_git(root, { "config", "user.email", "test@example.com" })
    run_git(root, { "config", "user.name", "Test User" })

    write_text(vim.fs.joinpath(root, "main.txt"), "main\n")
    write_text(vim.fs.joinpath(root, "feature.txt"), "feature\n")

    run_git(root, { "add", "main.txt", "feature.txt" })
    run_git(root, { "commit", "-m", "init" })
    run_git(root, { "branch", "feature" })

    local branch = vim.trim(run_git(root, { "rev-parse", "--abbrev-ref", "HEAD" }))

    return root, branch
end

--- Write one branch's saved grapple mark file.
---
---@param root string The Git repository root.
---@param branch string The Git branch to write underneath `.sessions`.
---@param entries {relative_path: string, line: integer}[] The marks to write.
local function write_marks_entries(root, branch, entries)
    local directory = vim.fs.joinpath(root, core_helpers._SESSIONS_DIRECTORY_NAME, branch)
    local path = vim.fs.joinpath(directory, ".nvim.marks.lua")
    ---@type string[]
    local lines = { "local buffer" }

    assert.equal(1, vim.fn.mkdir(directory, "p"))

    table.insert(lines, 'vim.cmd.delmarks("A-Z")')

    for index, entry in ipairs(entries) do
        local mark = native_grapple.get_mark_from_index(index)

        table.insert(lines, string.format('buffer = vim.fn.bufnr("%s", true)', entry.relative_path))
        table.insert(lines, "vim.fn.bufload(buffer)")
        table.insert(lines, string.format('vim.api.nvim_buf_set_mark(buffer, "%s", %d, 0, {})', mark, entry.line))
        table.insert(lines, "")
    end

    write_text(path, table.concat(lines, "\n"))
end

--- Write one branch's saved grapple mark file.
---
---@param root string The Git repository root.
---@param branch string The Git branch to write underneath `.sessions`.
---@param relative_path string The repository-relative mark path.
---@param line integer The line number to mark.
local function write_marks_file(root, branch, relative_path, line)
    write_marks_entries(root, branch, { { relative_path = relative_path, line = line } })
end

--- Get current grapple marks as `index:path:line` text.
---
---@return string[] # The current bookmark summaries.
local function get_bookmark_summaries()
    ---@type string[]
    local output = {}

    for index, buffer_number, buffer_path in native_grapple.iter_bookmarks() do
        local mark = native_grapple.get_mark_from_index(index)
        local position = vim.api.nvim_buf_get_mark(buffer_number, mark)

        table.insert(output, string.format("%d:%s:%d", index, vim.fs.basename(buffer_path), position[1]))
    end

    return output
end

--- Temporarily change Neovim's current directory while `callback` runs.
---
---@param path string The directory to enter.
---@param callback fun(): nil The test body.
local function with_cwd(path, callback)
    local previous = vim.fn.getcwd()

    vim.cmd("noautocmd silent cd " .. vim.fn.fnameescape(path))

    local ok, message = pcall(callback)

    vim.cmd("noautocmd silent cd " .. vim.fn.fnameescape(previous))

    if not ok then
        error(message)
    end
end

describe("modules.plugins.native_grapple", function()
    before_each(function()
        native_grapple._reset_state_for_tests()
        native_grapple.delete_all_bookmarks()
    end)

    after_each(function()
        native_grapple._reset_state_for_tests()
        native_grapple.delete_all_bookmarks()
        vim.cmd("silent enew!")
    end)

    it("loads marks from the current branch session file", function()
        local root, branch = make_repository()
        write_marks_file(root, branch, "main.txt", 1)

        with_cwd(root, function()
            native_grapple.load_branch_marks(root, branch)
        end)

        assert.same({ "1:main.txt:1" }, get_bookmark_summaries())
        vim.fn.delete(root, "rf")
    end)

    it("clears marks when the new branch has no saved marks", function()
        local root, branch = make_repository()
        write_marks_file(root, branch, "main.txt", 1)

        with_cwd(root, function()
            native_grapple.load_branch_marks(root, branch)
            assert.same({ "1:main.txt:1" }, get_bookmark_summaries())

            native_grapple.load_branch_marks(root, "feature")
        end)

        assert.same({}, get_bookmark_summaries())
        vim.fn.delete(root, "rf")
    end)

    it("loads stale out-of-range marks at the top of the file", function()
        local root, branch = make_repository()
        write_marks_file(root, branch, "main.txt", 999)

        with_cwd(root, function()
            native_grapple.load_branch_marks(root, branch)
        end)

        assert.same({ "1:main.txt:1" }, get_bookmark_summaries())
        vim.fn.delete(root, "rf")
    end)

    it("clears extra marks from the previous branch before loading the new branch", function()
        local root, branch = make_repository()
        write_marks_entries(root, branch, {
            { relative_path = "main.txt", line = 1 },
            { relative_path = "feature.txt", line = 1 },
        })
        write_marks_file(root, "feature", "feature.txt", 1)

        with_cwd(root, function()
            native_grapple.load_branch_marks(root, branch)
            assert.same({ "1:main.txt:1", "2:feature.txt:1" }, get_bookmark_summaries())

            native_grapple.load_branch_marks(root, "feature")
        end)

        assert.same({ "1:feature.txt:1" }, get_bookmark_summaries())
        vim.fn.delete(root, "rf")
    end)

    it("uses the current directory as a storage root outside Git repositories", function()
        local root = vim.fn.tempname()
        local file_path = vim.fs.joinpath(root, "notes.txt")
        local marks_path = vim.fs.joinpath(
            root,
            core_helpers._SESSIONS_DIRECTORY_NAME,
            native_grapple.NO_GIT_BRANCH_NAME,
            ".nvim.marks.lua"
        )

        assert.equal(1, vim.fn.mkdir(root, "p"))
        write_text(file_path, "notes\n")

        with_cwd(root, function()
            vim.cmd("silent noautocmd edit " .. vim.fn.fnameescape(file_path))
            native_grapple.mark_current_buffer_as_bookmark("A")

            assert.equal(1, vim.fn.filereadable(marks_path))
            assert.same({ "1:notes.txt:1" }, get_bookmark_summaries())

            native_grapple.delete_all_bookmarks()
            native_grapple._reset_state_for_tests()
            native_grapple.sync_branch(root)
        end)

        assert.same({ "1:notes.txt:1" }, get_bookmark_summaries())
        vim.fn.delete(root, "rf")
    end)

    it("reloads branch marks when Git HEAD changes", function()
        local root, branch = make_repository()
        write_marks_file(root, branch, "main.txt", 1)
        write_marks_file(root, "feature", "feature.txt", 1)

        with_cwd(root, function()
            native_grapple.sync_branch(root)
            assert.same({ "1:main.txt:1" }, get_bookmark_summaries())

            run_git(root, { "checkout", "feature" })
            native_grapple.sync_branch(root)
            assert.same({ "1:feature.txt:1" }, get_bookmark_summaries())
        end)

        vim.fn.delete(root, "rf")
    end)
end)
