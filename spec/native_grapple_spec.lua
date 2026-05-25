local core_helpers = require("modules.utilities.core_helpers")
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
---@param root string The storage root.
---@param branch string The branch or fallback namespace.
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
---@param root string The storage root.
---@param branch string The branch or fallback namespace.
---@param relative_path string The storage-root-relative mark path.
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
        native_grapple.teardown()
        native_grapple.delete_all_bookmarks()
    end)

    after_each(function()
        native_grapple.teardown()
        native_grapple.delete_all_bookmarks()
        vim.cmd("silent enew!")
    end)

    it("loads marks from the current branch session file without a Vim session", function()
        local root, branch = make_repository()
        write_marks_file(root, branch, "main.txt", 1)

        with_cwd(root, function()
            native_grapple.sync_branch()
        end)

        assert.same({ "1:main.txt:1" }, get_bookmark_summaries())
        vim.fn.delete(root, "rf")
    end)

    it("clears marks when the new branch has no saved marks", function()
        local root, branch = make_repository()
        write_marks_file(root, branch, "main.txt", 1)

        with_cwd(root, function()
            assert.True(native_grapple.load_branch_marks(root, branch))
            assert.same({ "1:main.txt:1" }, get_bookmark_summaries())

            assert.False(native_grapple.load_branch_marks(root, "feature"))
        end)

        assert.same({}, get_bookmark_summaries())
        vim.fn.delete(root, "rf")
    end)

    it("loads saved marks without loading their buffers", function()
        local root, branch = make_repository()
        local path = vim.fs.joinpath(root, "main.txt")

        write_marks_file(root, branch, "main.txt", 1)

        with_cwd(root, function()
            assert.True(native_grapple.load_branch_marks(root, branch))
        end)

        local _, buffer = native_grapple.iter_bookmarks()()

        assert.is_not_nil(buffer)
        ---@cast buffer integer
        assert.is_true(buffer > 0)
        assert.is_false(vim.api.nvim_buf_is_loaded(buffer))
        assert.equal(path, vim.api.nvim_buf_get_name(buffer))
        assert.same({ "1:main.txt:1" }, get_bookmark_summaries())
        vim.fn.delete(root, "rf")
    end)

    it("serializes lazy marks without buffer loads", function()
        local root, branch = make_repository()

        write_marks_file(root, branch, "main.txt", 1)

        with_cwd(root, function()
            assert.True(native_grapple.load_branch_marks(root, branch))
        end)

        local code = table.concat(native_grapple.serialize_mark_code(root), "\n")

        assert.is_nil(code:find("bufload", 1, true))
        assert.is_not_nil(code:find("setpos", 1, true))
        vim.fn.delete(root, "rf")
    end)

    it("jumps stale out-of-range marks at the top of the file", function()
        local root, branch = make_repository()
        write_marks_file(root, branch, "main.txt", 999)

        with_cwd(root, function()
            assert.True(native_grapple.load_branch_marks(root, branch))
            core_helpers.with_file_messages_suppressed(function()
                native_grapple.mark_current_buffer_as_bookmark("A")
            end)
        end)

        assert.equal("main.txt", vim.fs.basename(vim.api.nvim_buf_get_name(0)))
        assert.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
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
            native_grapple.teardown()
            native_grapple.sync_branch()
        end)

        assert.same({ "1:notes.txt:1" }, get_bookmark_summaries())
        vim.fn.delete(root, "rf")
    end)

    it("redraws the statusline after adding and deleting a bookmark", function()
        local root = vim.fn.tempname()
        local file_path = vim.fs.joinpath(root, "notes.txt")
        local redraw_count = 0
        local original_redraw_statusline = native_grapple._P.redraw_statusline

        assert.equal(1, vim.fn.mkdir(root, "p"))
        write_text(file_path, "notes\n")

        ---@diagnostic disable-next-line: duplicate-set-field
        native_grapple._P.redraw_statusline = function()
            redraw_count = redraw_count + 1
        end

        with_cwd(root, function()
            vim.cmd("silent noautocmd edit " .. vim.fn.fnameescape(file_path))
            native_grapple.mark_current_buffer_as_bookmark("A")
            native_grapple.delete_bookmark(1)
        end)

        native_grapple._P.redraw_statusline = original_redraw_statusline

        assert.equal(2, redraw_count)
        vim.fn.delete(root, "rf")
    end)

    it("redraws the statusline after toggling the current buffer bookmark", function()
        local root = vim.fn.tempname()
        local file_path = vim.fs.joinpath(root, "notes.txt")
        local redraw_count = 0
        local original_redraw_statusline = native_grapple._P.redraw_statusline

        assert.equal(1, vim.fn.mkdir(root, "p"))
        write_text(file_path, "notes\n")

        ---@diagnostic disable-next-line: duplicate-set-field
        native_grapple._P.redraw_statusline = function()
            redraw_count = redraw_count + 1
        end

        with_cwd(root, function()
            vim.cmd("silent noautocmd edit " .. vim.fn.fnameescape(file_path))
            native_grapple.toggle_current_buffer()
            native_grapple.toggle_current_buffer()
        end)

        native_grapple._P.redraw_statusline = original_redraw_statusline

        assert.equal(2, redraw_count)
        vim.fn.delete(root, "rf")
    end)

    it("uses the cwd root even when the current buffer is elsewhere", function()
        local root, branch = make_repository()
        local other_root = vim.fn.tempname()
        local other_file = vim.fs.joinpath(other_root, "elsewhere.txt")

        assert.equal(1, vim.fn.mkdir(other_root, "p"))
        write_text(other_file, "elsewhere\n")
        write_marks_file(root, branch, "main.txt", 1)

        with_cwd(root, function()
            vim.cmd("silent noautocmd edit " .. vim.fn.fnameescape(other_file))
            native_grapple.sync_branch()
        end)

        assert.same({ "1:main.txt:1" }, get_bookmark_summaries())
        vim.fn.delete(root, "rf")
        vim.fn.delete(other_root, "rf")
    end)

    it("reloads marks when the cwd changes to another repository", function()
        local first_root, first_branch = make_repository()
        local second_root, second_branch = make_repository()

        write_marks_file(first_root, first_branch, "main.txt", 1)
        write_marks_file(second_root, second_branch, "feature.txt", 1)

        with_cwd(first_root, function()
            native_grapple.sync_branch()
            assert.same({ "1:main.txt:1" }, get_bookmark_summaries())
        end)

        with_cwd(second_root, function()
            native_grapple.sync_branch()
        end)

        assert.same({ "1:feature.txt:1" }, get_bookmark_summaries())
        vim.fn.delete(first_root, "rf")
        vim.fn.delete(second_root, "rf")
    end)

    it("reloads branch marks when Git HEAD changes", function()
        local root, branch = make_repository()
        write_marks_file(root, branch, "main.txt", 1)
        write_marks_file(root, "feature", "feature.txt", 1)

        with_cwd(root, function()
            native_grapple.sync_branch()
            assert.same({ "1:main.txt:1" }, get_bookmark_summaries())

            run_git(root, { "checkout", "feature" })
            native_grapple.sync_branch(root, { force = true })
        end)

        assert.same({ "1:feature.txt:1" }, get_bookmark_summaries())
        vim.fn.delete(root, "rf")
    end)

    it("watches Git HEAD and refreshes statusline data after external branch changes", function()
        local root, branch = make_repository()
        write_marks_file(root, branch, "main.txt", 1)
        write_marks_file(root, "feature", "feature.txt", 1)

        with_cwd(root, function()
            native_grapple.sync_branch()
            assert.same({ "1:main.txt:1" }, get_bookmark_summaries())
            assert.is_not_nil(native_grapple._HEAD_WATCHERS_BY_ROOT[native_grapple.get_current_root()])

            run_git(root, { "checkout", "feature" })

            assert.True(vim.wait(1500, function()
                return vim.deep_equal({ "1:feature.txt:1" }, get_bookmark_summaries())
            end, 20))
        end)

        vim.fn.delete(root, "rf")
    end)
end)
