local git_hunk_navigation = require("modules.features.git_hunk_navigation")

--- Run a Git command inside `root`.
---
---@param root string The Git repository root.
---@param arguments string[] The Git arguments to run after `-C root`.
---@return string # The command's standard output.
local function run_git(root, arguments)
    ---@type string[]
    local command = { "git", "-C", root }
    vim.list_extend(command, arguments)

    local result = vim.system(command, { text = true }):wait()

    assert.equal(0, result.code, result.stderr)

    return result.stdout or ""
end

--- Write exact text to `path`.
---
---@param path string The path to write.
---@param text string The text contents to write.
local function write_text(path, text)
    local file = assert(vim.uv.fs_open(path, "w", 438))
    assert(vim.uv.fs_write(file, text, 0))
    vim.uv.fs_close(file)
end

--- Create a temporary Git repository for integration tests.
---
--- CAVEAT: `git init` inherits the developer's global configuration, and the
--- diff parser hard-codes the default `a/`/`b/` header prefixes. A machine with
--- `diff.noprefix` or `diff.mnemonicPrefix` set globally therefore fails these
--- tests for reasons unrelated to the code under test.
---
---@return string # The temporary repository root.
local function make_repo()
    local root = vim.fn.tempname()
    assert.equal(1, vim.fn.mkdir(root, "p"))

    local result = vim.system({ "git", "-C", root, "init" }, { text = true }):wait()
    assert.equal(0, result.code, result.stderr)

    run_git(root, { "config", "user.email", "test@example.com" })
    run_git(root, { "config", "user.name", "Test User" })

    return root
end

--- Commit exact file contents in a temporary repository.
---
---@param root string The Git repository root.
---@param relative_path string The repository-relative file path.
---@param text string The file contents to commit.
local function commit_file(root, relative_path, text)
    local path = vim.fs.joinpath(root, relative_path)
    local directory = vim.fn.fnamemodify(path, ":h")

    assert.equal(1, vim.fn.mkdir(directory, "p"))
    write_text(path, text)
    run_git(root, { "add", relative_path })
    run_git(root, { "commit", "-m", "commit " .. relative_path })
end

--- Remove a temporary test directory after leaving its buffer.
---
---@param path string The directory to remove.
local function remove_tree(path)
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)

        if vim.bo[buffer].filetype == "qf" then
            vim.wo[window].winfixbuf = false
            vim.api.nvim_win_close(window, true)
        end
    end

    vim.cmd("silent enew!")
    vim.wait(20)
    vim.fn.delete(path, "rf")
end

--- Check whether a quickfix window is currently open.
---
---@return boolean # If a quickfix window is open, return `true`.
local function has_quickfix_window()
    for _, window in ipairs(vim.fn.getwininfo()) do
        if window.quickfix == 1 then
            return true
        end
    end

    return false
end

--- Change Neovim's current directory while `callback` runs.
---
---@param path string The directory to enter.
---@param callback fun(): nil The work to run.
local function with_cwd(path, callback)
    local previous = vim.fn.getcwd()

    vim.cmd("cd " .. vim.fn.fnameescape(path))

    local ok, err = pcall(callback)
    vim.cmd("cd " .. vim.fn.fnameescape(previous))

    if not ok then
        error(err)
    end
end

--- Capture notifications while `callback` runs and replay them only on failure.
---
---@param callback fun(): nil The test body to run quietly.
local function with_captured_notifications(callback)
    local notify = vim.notify
    ---@type string[]
    local messages = {}

    rawset(vim, "notify", function(message, _level, _options)
        table.insert(messages, tostring(message))

        return nil
    end)

    local ok, err = pcall(callback)
    rawset(vim, "notify", notify)

    if not ok then
        for _, message in ipairs(messages) do
            notify(message)
        end

        error(err)
    end
end

--- Press normal-mode keys and execute their mapping.
---
---@param keys string The key sequence to press.
local function press_normal_keys(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
    vim.wait(400)
end

--- Get the resolved absolute path for a quickfix entry.
---
--- Quickfix entries store a buffer number, and Vim may display that buffer's
--- name relative to the current directory. Tests compare absolute paths so that
--- the current directory cannot change the result.
---
---@param entry table The quickfix entry to inspect.
---@return string # The absolute file path for `entry`.
local function get_quickfix_path(entry)
    return vim.fn.fnamemodify(vim.fn.bufname(entry.bufnr), ":p")
end

--- Run `:LoadGitDiff` from `directory` and wait for the quickfix list.
---
--- The current buffer is emptied first so that the repository is resolved from
--- the current directory instead of a buffer path.
---
---@param root string The repository root, used to wait for the loaded state.
---@param directory string The directory to run `:LoadGitDiff` from.
---@return table[] # The resulting quickfix entries.
local function load_quickfix_from(root, directory)
    ---@type table[]
    local items = {}

    with_cwd(directory, function()
        vim.cmd("silent enew!")
        vim.cmd("LoadGitDiff")
        vim.wait(1000, function()
            return git_hunk_navigation.get_repository_state(root) ~= nil and has_quickfix_window()
        end)

        items = vim.fn.getqflist()
    end)

    return items
end

--- Load repository hunks and wait for async completion.
---
---@return boolean # If hunks loaded, return `true`.
local function load_hunks()
    local loaded

    git_hunk_navigation.load(nil, function(success)
        loaded = success
    end)

    vim.wait(1000, function()
        return loaded ~= nil
    end)

    return loaded == true
end

describe("modules.features.git_hunk_navigation", function()
    it("parses repository-wide hunks sequentially", function()
        local entries = git_hunk_navigation.parse_diff(
            "/tmp/repo",
            [[
diff --git a/a.txt b/a.txt
index 0000000..1111111 100644
--- a/a.txt
+++ b/a.txt
@@ -2 +2 @@
-old
+new
diff --git a/nested/b.txt b/nested/b.txt
index 2222222..3333333 100644
--- a/nested/b.txt
+++ b/nested/b.txt
@@ -1,0 +2 @@
+added
]]
        )

        assert.equal(2, #entries)
        assert.equal("a.txt", entries[1].relative_path)
        assert.equal(2, entries[1].lnum)
        assert.equal("nested/b.txt", entries[2].relative_path)
        assert.equal(2, entries[2].lnum)
    end)

    it("parses renamed file hunks using the target path", function()
        local entries = git_hunk_navigation.parse_diff(
            "/tmp/repo",
            [[
diff --git a/old/file.txt b/new/file.txt
similarity index 75%
rename from old/file.txt
rename to new/file.txt
index 1111111..2222222 100644
--- a/old/file.txt
+++ b/new/file.txt
@@ -2,0 +3 @@ existing line
+new line
]]
        )

        assert.equal(1, #entries)
        assert.equal("new/file.txt", entries[1].relative_path)
        assert.equal("/tmp/repo/new/file.txt", entries[1].absolute_path)
        assert.equal(3, entries[1].lnum)
    end)

    it("skips whole-file deletion hunks because there is no target buffer to open", function()
        local entries = git_hunk_navigation.parse_diff(
            "/tmp/repo",
            [[
diff --git a/deleted.txt b/deleted.txt
deleted file mode 100644
index 1111111..0000000
--- a/deleted.txt
+++ /dev/null
@@ -1,2 +0,0 @@
-one
-two
diff --git a/changed.txt b/changed.txt
index 2222222..3333333 100644
--- a/changed.txt
+++ b/changed.txt
@@ -1 +1 @@
-old
+new
]]
        )

        assert.equal(1, #entries)
        assert.equal("changed.txt", entries[1].relative_path)
    end)

    it("keeps loaded hunk caches per repository", function()
        with_captured_notifications(function()
            local first = make_repo()
            local second = make_repo()

            commit_file(first, "file.txt", "one\ntwo\n")
            commit_file(second, "other.txt", "alpha\nbeta\n")
            write_text(vim.fs.joinpath(first, "file.txt"), "ONE\ntwo\n")
            write_text(vim.fs.joinpath(second, "other.txt"), "alpha\nBETA\n")

            local ok, err = pcall(function()
                with_cwd(first, function()
                    assert.True(load_hunks())
                end)

                with_cwd(second, function()
                    assert.True(load_hunks())
                end)

                local state = git_hunk_navigation.get_state()
                assert.equal(1, #state.repositories[first].entries)
                assert.equal(1, #state.repositories[second].entries)
                assert.equal("file.txt", state.repositories[first].entries[1].relative_path)
                assert.equal("other.txt", state.repositories[second].entries[1].relative_path)
            end)

            remove_tree(first)
            remove_tree(second)

            if not ok then
                error(err)
            end
        end)
    end)

    it("jumps forward and backward from the current cursor location", function()
        with_captured_notifications(function()
            local root = make_repo()

            commit_file(root, "file.txt", "one\ntwo\nthree\nfour\nfive\n")
            write_text(vim.fs.joinpath(root, "file.txt"), "ONE\ntwo\nTHREE\nfour\nFIVE\n")

            local ok, err = pcall(function()
                with_cwd(root, function()
                    vim.cmd("silent edit " .. vim.fn.fnameescape(vim.fs.joinpath(root, "file.txt")))
                    assert.True(load_hunks())

                    vim.api.nvim_win_set_cursor(0, { 2, 0 })
                    press_normal_keys("]g")
                    assert.equal(vim.fs.joinpath(root, "file.txt"), vim.api.nvim_buf_get_name(0))
                    assert.are.same({ 3, 0 }, vim.api.nvim_win_get_cursor(0))

                    vim.api.nvim_win_set_cursor(0, { 5, 0 })
                    press_normal_keys("[g")
                    assert.equal(vim.fs.joinpath(root, "file.txt"), vim.api.nvim_buf_get_name(0))
                    assert.are.same({ 3, 0 }, vim.api.nvim_win_get_cursor(0))
                end)
            end)

            remove_tree(root)

            if not ok then
                error(err)
            end
        end)
    end)

    it("does not replace disk hunks with empty hunks from unloaded named buffers", function()
        with_captured_notifications(function()
            local root = make_repo()

            commit_file(root, "first.txt", "one\ntwo\nthree\nfour\n")
            commit_file(root, "second.txt", "alpha\nbeta\ngamma\n")
            write_text(vim.fs.joinpath(root, "first.txt"), "one\nTWO\nthree\nFOUR\n")
            write_text(vim.fs.joinpath(root, "second.txt"), "alpha\nBETA\ngamma\n")

            local ok, err = pcall(function()
                with_cwd(root, function()
                    vim.cmd("silent edit " .. vim.fn.fnameescape(vim.fs.joinpath(root, "first.txt")))
                    local unloaded = vim.fn.bufadd(vim.fs.joinpath(root, "second.txt"))
                    assert.is_false(vim.api.nvim_buf_is_loaded(unloaded))
                    assert.True(load_hunks())

                    local repository_state = assert(git_hunk_navigation.get_repository_state(root))
                    assert.equal(3, #repository_state.entries)
                    assert.equal("first.txt", repository_state.entries[1].relative_path)
                    assert.equal(2, repository_state.entries[1].lnum)
                    assert.equal("first.txt", repository_state.entries[2].relative_path)
                    assert.equal(4, repository_state.entries[2].lnum)
                    assert.equal("second.txt", repository_state.entries[3].relative_path)
                    assert.equal(2, repository_state.entries[3].lnum)
                end)
            end)

            remove_tree(root)

            if not ok then
                error(err)
            end
        end)
    end)

    it("refreshes stale cached hunks from unsaved buffer edits before jumping", function()
        with_captured_notifications(function()
            local root = make_repo()

            commit_file(root, "file.txt", "one\ntwo\nthree\n")

            local ok, err = pcall(function()
                with_cwd(root, function()
                    vim.cmd("silent edit " .. vim.fn.fnameescape(vim.fs.joinpath(root, "file.txt")))
                    assert.True(load_hunks())

                    vim.api.nvim_buf_set_lines(0, 1, 2, false, { "TWO" })
                    git_hunk_navigation.mark_stale_for_buffer(0)
                    vim.api.nvim_win_set_cursor(0, { 1, 0 })
                    press_normal_keys("]g")

                    assert.equal(vim.fs.joinpath(root, "file.txt"), vim.api.nvim_buf_get_name(0))
                    assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))

                    local repository_state = assert(git_hunk_navigation.get_repository_state(root))
                    assert.equal(1, #repository_state.entries)
                end)
            end)

            remove_tree(root)

            if not ok then
                error(err)
            end
        end)
    end)

    it("jumps to the target path for unstaged renamed file hunks", function()
        with_captured_notifications(function()
            local root = make_repo()

            commit_file(root, "nested/a/b/c/deep.txt", "deep one\ndeep two\ndeep three\ndeep four\ndeep five\n")
            commit_file(root, "old/unstaged_rename.txt", "alpha\nbeta\n")

            local renamed_path = vim.fs.joinpath(root, "src/renamed/unstaged_rename.txt")
            assert.equal(1, vim.fn.mkdir(vim.fs.dirname(renamed_path), "p"))
            run_git(root, { "config", "diff.renames", "true" })
            run_git(root, { "mv", "old/unstaged_rename.txt", "src/renamed/unstaged_rename.txt" })
            run_git(root, { "restore", "--staged", "old/unstaged_rename.txt", "src/renamed/unstaged_rename.txt" })
            write_text(renamed_path, "alpha\nbeta\nrenamed addition\n")
            run_git(root, { "add", "-N", "src/renamed/unstaged_rename.txt" })
            write_text(
                vim.fs.joinpath(root, "nested/a/b/c/deep.txt"),
                "deep one\ndeep TWO modified\ndeep three\ndeep five\n"
            )

            local ok, err = pcall(function()
                with_cwd(root, function()
                    vim.cmd("silent edit " .. vim.fn.fnameescape(vim.fs.joinpath(root, "nested/a/b/c/deep.txt")))
                    assert.True(load_hunks())

                    vim.api.nvim_win_set_cursor(0, { 4, 0 })
                    press_normal_keys("]g")

                    assert.equal(renamed_path, vim.api.nvim_buf_get_name(0))
                    assert.is_true(vim.api.nvim_win_get_cursor(0)[1] >= 1)
                end)
            end)

            remove_tree(root)

            if not ok then
                error(err)
            end
        end)
    end)

    it("loads cached hunks into quickfix with LoadGitDiff", function()
        with_captured_notifications(function()
            local root = make_repo()

            commit_file(root, "file.txt", "one\ntwo\n")
            write_text(vim.fs.joinpath(root, "file.txt"), "one\nTWO\n")

            local ok, err = pcall(function()
                with_cwd(root, function()
                    vim.cmd("LoadGitDiff")
                    vim.wait(1000, function()
                        return git_hunk_navigation.get_repository_state(root) ~= nil and has_quickfix_window()
                    end)

                    local repository_state = assert(git_hunk_navigation.get_repository_state(root))
                    assert.equal(#repository_state.entries, #vim.fn.getqflist())
                    assert.equal("file.txt", repository_state.entries[1].relative_path)
                end)
            end)

            remove_tree(root)

            if not ok then
                error(err)
            end
        end)
    end)

    it("resolves quickfix paths from the repository root when the current directory is a subfolder", function()
        with_captured_notifications(function()
            local root = make_repo()

            commit_file(root, "docs/beta.txt", "a\nb\nc\nd\n")
            commit_file(root, "src/deep/nested/alpha.txt", "one\ntwo\nthree\n")
            write_text(vim.fs.joinpath(root, "docs/beta.txt"), "a\nb\nC\nd\n")
            write_text(vim.fs.joinpath(root, "src/deep/nested/alpha.txt"), "one\nTWO\nthree\n")

            local ok, err = pcall(function()
                local items = load_quickfix_from(root, vim.fs.joinpath(root, "src/deep"))

                assert.equal(2, #items)

                -- NOTE: Git reports diff paths relative to the repository root,
                -- never relative to the current directory. The quickfix entries
                -- must point at the real files even though `src/deep` is neither
                -- the repository root nor a parent of `docs/beta.txt`.
                assert.equal(
                    vim.fn.fnamemodify(vim.fs.joinpath(root, "docs/beta.txt"), ":p"),
                    get_quickfix_path(items[1])
                )
                assert.equal(3, items[1].lnum)
                assert.equal(
                    vim.fn.fnamemodify(vim.fs.joinpath(root, "src/deep/nested/alpha.txt"), ":p"),
                    get_quickfix_path(items[2])
                )
                assert.equal(2, items[2].lnum)

                -- NOTE: The display text stays repository-relative so that hunk
                -- labels do not change when the current directory changes.
                assert.equal("docs/beta.txt:3", items[1].text)
                assert.equal("src/deep/nested/alpha.txt:2", items[2].text)
            end)

            remove_tree(root)

            if not ok then
                error(err)
            end
        end)
    end)

    it("builds the same quickfix entries from the repository root and from a subfolder", function()
        with_captured_notifications(function()
            local root = make_repo()

            commit_file(root, "top.txt", "one\ntwo\n")
            commit_file(root, "src/deep/nested/alpha.txt", "one\ntwo\nthree\n")
            write_text(vim.fs.joinpath(root, "top.txt"), "one\nTWO\n")
            write_text(vim.fs.joinpath(root, "src/deep/nested/alpha.txt"), "one\nTWO\nthree\n")

            local ok, err = pcall(function()
                local from_root = load_quickfix_from(root, root)
                local from_subfolder = load_quickfix_from(root, vim.fs.joinpath(root, "src/deep/nested"))

                assert.equal(2, #from_root)
                assert.equal(#from_root, #from_subfolder)

                for index = 1, #from_root do
                    assert.equal(get_quickfix_path(from_root[index]), get_quickfix_path(from_subfolder[index]))
                    assert.equal(from_root[index].lnum, from_subfolder[index].lnum)
                    assert.equal(from_root[index].text, from_subfolder[index].text)
                end
            end)

            remove_tree(root)

            if not ok then
                error(err)
            end
        end)
    end)

    it("jumps to the correct file and line from a subfolder quickfix entry", function()
        with_captured_notifications(function()
            local root = make_repo()

            commit_file(root, "src/deep/nested/alpha.txt", "one\ntwo\nthree\nfour\nfive\n")
            write_text(vim.fs.joinpath(root, "src/deep/nested/alpha.txt"), "one\ntwo\nthree\nFOUR\nfive\n")

            local ok, err = pcall(function()
                local subfolder = vim.fs.joinpath(root, "src/deep")
                local items = load_quickfix_from(root, subfolder)

                assert.equal(1, #items)

                with_cwd(subfolder, function()
                    vim.cmd("silent cfirst")

                    assert.equal(
                        vim.fn.fnamemodify(vim.fs.joinpath(root, "src/deep/nested/alpha.txt"), ":p"),
                        vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
                    )
                    assert.equal(4, vim.api.nvim_win_get_cursor(0)[1])
                    assert.equal("FOUR", vim.api.nvim_get_current_line())
                end)
            end)

            remove_tree(root)

            if not ok then
                error(err)
            end
        end)
    end)
end)
