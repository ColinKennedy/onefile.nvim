local git_add_submode = require("modules.features.git_add_submode")
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

--- Every temporary repository root created by `make_repo`, for teardown.
---
---@type string[]
local _ALL_ROOTS = {}

--- Create a temporary Git repository for integration tests.
---
--- Deleting a repository's directory while a buffer or an in-flight async
--- Git callback from another test still references it produces spurious
--- Neovim/Git errors (E211, "directory does not exist") that have nothing to
--- do with the test under way. Roots are removed once, after every test in
--- this file has finished, instead of immediately after each test.
---
---@return string # The temporary repository root.
local function make_repo()
    local root = vim.fn.tempname()
    assert.equal(1, vim.fn.mkdir(root, "p"))
    root = vim.uv.fs_realpath(root) or root
    table.insert(_ALL_ROOTS, root)

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
    write_text(vim.fs.joinpath(root, relative_path), text)
    run_git(root, { "add", relative_path })
    run_git(root, { "commit", "-m", "commit " .. relative_path })
end

--- Leave a temporary test directory's buffer, without deleting it yet.
---
---@param _path string The directory that was in use (unused; kept for call-site clarity).
local function remove_tree(_path)
    vim.cmd("silent enew!")
    vim.wait(20)
end

--- Delete every repository `make_repo` created during this file's tests.
local function remove_all_repos()
    vim.cmd("silent enew!")
    vim.wait(20)

    for _, root in ipairs(_ALL_ROOTS) do
        vim.fn.delete(root, "rf")
    end

    _ALL_ROOTS = {}
end

--- Edit `path` in the current Neovim session and replace its lines.
---
--- The file on disk is left untouched -- staging from an unsaved buffer is
--- exactly the behavior under test.
---
---@param path string The file path to edit.
---@param lines string[] The buffer lines to set.
local function edit_file(path, lines)
    vim.cmd("silent edit " .. vim.fn.fnameescape(path))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.endofline = true
end

--- Switch to `path` with the cursor on line 1.
---
--- Repository-wide hunk navigation jumps relative to the cursor, so tests that
--- expect to land on the alphabetically first hunk need the cursor parked
--- before every hunk instead of wherever the last edit left it.
---
---@param path string The already-open file path to focus.
local function focus_file(path)
    vim.cmd("silent edit " .. vim.fn.fnameescape(path))
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

--- Press Normal-mode keys and let their mapping run.
---
---@param keys string The key sequence to press.
local function press_keys(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

--- Wait for an async submode step to settle.
---
--- Staging steps chain several sequential Git subprocesses, so this leaves
--- generous headroom for slower CI machines.
---
---@param predicate fun(): boolean The condition to wait for.
local function wait_for(predicate)
    vim.wait(8000, predicate, 20)
end

--- Get the cached hunk count for `root`, or `-1` if nothing is cached.
---
---@param root string The Git repository root.
---@return integer # The cached hunk count.
local function entries_count(root)
    local state = git_hunk_navigation._get_repository_state(root)

    return state and #state.entries or -1
end

--- Get the current buffer's file name, without its directory.
---
---@return string # The current buffer's base name.
local function current_file_name()
    return vim.fs.basename(vim.api.nvim_buf_get_name(0))
end

--- Find the submode's floating legend window, if it is open.
---
---@return integer? # The legend window handle, if found.
local function find_legend_window()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local ok, config = pcall(vim.api.nvim_win_get_config, window)

        if ok and config.relative == "editor" and config.anchor == "NE" then
            local buffer = vim.api.nvim_win_get_buf(window)

            if vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] == "y stage" then
                return window
            end
        end
    end

    return nil
end

--- Run a test body inside a fresh temporary repository.
---
--- Captures notifications (printing them only on failure) and always cleans
--- up the repository, even when `body` raises -- otherwise a single failing
--- test leaves stale buffers and directories behind that cascade into
--- unrelated failures in every test that runs after it.
---
---@param body fun(root: string, messages: string[]): nil The test body.
local function with_repo(body)
    local root = make_repo()
    local notify = vim.notify
    ---@type string[]
    local messages = {}

    rawset(vim, "notify", function(message, _level, _options)
        table.insert(messages, tostring(message))

        return nil
    end)

    local ok, err = pcall(body, root, messages)

    rawset(vim, "notify", notify)
    remove_tree(root)

    if not ok then
        for _, message in ipairs(messages) do
            notify(message)
        end

        error(err)
    end
end

describe("modules.features.git_add_submode", function()
    after_each(function()
        if git_add_submode.is_active() then
            press_keys("<Esc>")
            wait_for(function()
                return not git_add_submode.is_active()
            end)
        end
    end)

    teardown(remove_all_repos)

    it("does nothing when no Git hunks are cached", function()
        with_repo(function(root)
            commit_file(root, "file.txt", "one\ntwo\n")
            edit_file(vim.fs.joinpath(root, "file.txt"), { "one", "two" })

            git_add_submode.start()
            wait_for(function()
                return entries_count(root) == 0
            end)

            assert.is_false(git_add_submode.is_active())
            assert.is_nil(find_legend_window())
        end)
    end)

    it("activates at the first hunk, overrides y/n/N/a/v/q/<Esc>, and shows the legend", function()
        with_repo(function(root)
            commit_file(root, "a.txt", "one\ntwo\n")
            commit_file(root, "b.txt", "alpha\nbeta\n")
            edit_file(vim.fs.joinpath(root, "a.txt"), { "one", "TWO" })
            edit_file(vim.fs.joinpath(root, "b.txt"), { "alpha", "BETA" })
            focus_file(vim.fs.joinpath(root, "a.txt"))

            git_add_submode.start()
            wait_for(function()
                return git_add_submode.is_active()
            end)

            assert.is_true(git_add_submode.is_active())
            assert.equal("a.txt", current_file_name())
            assert.is_not_nil(find_legend_window())

            local y = vim.fn.maparg("y", "n", false, true)
            assert.is_function(y.callback)

            local shift_n = vim.fn.maparg("N", "n", false, true)
            assert.is_function(shift_n.callback)

            local v = vim.fn.maparg("v", "n", false, true)
            assert.is_function(v.callback)
        end)
    end)

    it("skips the current hunk with `n`, wrapping at the end of the list", function()
        with_repo(function(root)
            commit_file(root, "a.txt", "one\ntwo\n")
            commit_file(root, "b.txt", "alpha\nbeta\n")
            edit_file(vim.fs.joinpath(root, "a.txt"), { "one", "TWO" })
            edit_file(vim.fs.joinpath(root, "b.txt"), { "alpha", "BETA" })
            focus_file(vim.fs.joinpath(root, "a.txt"))

            git_add_submode.start()
            wait_for(function()
                return git_add_submode.is_active()
            end)
            assert.equal("a.txt", current_file_name())

            press_keys("n")
            wait_for(function()
                return current_file_name() == "b.txt"
            end)
            assert.equal("b.txt", current_file_name())

            press_keys("n")
            wait_for(function()
                return current_file_name() == "a.txt"
            end)
            assert.equal("a.txt", current_file_name())

            assert.equal("", run_git(root, { "diff", "--cached" }))
            assert.is_true(git_add_submode.is_active())
        end)
    end)

    it("jumps back to the previous hunk with `N`, wrapping at the start of the list", function()
        with_repo(function(root)
            commit_file(root, "a.txt", "one\ntwo\n")
            commit_file(root, "b.txt", "alpha\nbeta\n")
            edit_file(vim.fs.joinpath(root, "a.txt"), { "one", "TWO" })
            edit_file(vim.fs.joinpath(root, "b.txt"), { "alpha", "BETA" })
            focus_file(vim.fs.joinpath(root, "a.txt"))

            git_add_submode.start()
            wait_for(function()
                return git_add_submode.is_active()
            end)
            assert.equal("a.txt", current_file_name())

            press_keys("N")
            wait_for(function()
                return current_file_name() == "b.txt"
            end)
            assert.equal("b.txt", current_file_name())

            press_keys("N")
            wait_for(function()
                return current_file_name() == "a.txt"
            end)
            assert.equal("a.txt", current_file_name())

            assert.equal("", run_git(root, { "diff", "--cached" }))
            assert.is_true(git_add_submode.is_active())
        end)
    end)

    it("stages the current hunk with `y`, advances, and finishes once nothing is left", function()
        with_repo(function(root)
            commit_file(root, "a.txt", "one\ntwo\n")
            commit_file(root, "b.txt", "alpha\nbeta\n")
            edit_file(vim.fs.joinpath(root, "a.txt"), { "one", "TWO" })
            edit_file(vim.fs.joinpath(root, "b.txt"), { "alpha", "BETA" })
            focus_file(vim.fs.joinpath(root, "a.txt"))

            git_add_submode.start()
            wait_for(function()
                return git_add_submode.is_active()
            end)
            assert.equal("a.txt", current_file_name())

            local original_load = git_hunk_navigation._load
            local reloads = 0
            rawset(git_hunk_navigation, "_load", function(arguments, callback)
                reloads = reloads + 1
                original_load(arguments, callback)
            end)

            press_keys("y")
            wait_for(function()
                return entries_count(root) == 1
            end)
            rawset(git_hunk_navigation, "_load", original_load)

            assert.equal(0, reloads)
            assert.matches("%-two\n%+TWO", run_git(root, { "diff", "--cached", "--unified=0" }))
            assert.equal("b.txt", current_file_name())
            assert.is_true(git_add_submode.is_active())

            press_keys("y")
            wait_for(function()
                return not git_add_submode.is_active()
            end)

            assert.matches("%-beta\n%+BETA", run_git(root, { "diff", "--cached", "--unified=0" }))
            assert.is_false(git_add_submode.is_active())
            assert.is_nil(find_legend_window())
            assert.is_true(vim.tbl_isempty(vim.fn.maparg("y", "n", false, true)))
        end)
    end)

    it("reloads the hunk list after an edit made while Git mode is active", function()
        with_repo(function(root)
            commit_file(root, "file.txt", "one\ntwo\nthree\nfour\nfive\n")
            edit_file(vim.fs.joinpath(root, "file.txt"), { "one", "TWO", "three", "four", "five" })

            git_add_submode.start()
            wait_for(function()
                return git_add_submode.is_active()
            end)

            vim.api.nvim_buf_set_lines(0, 3, 4, false, { "FOUR" })
            vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
            assert.is_true(assert(git_hunk_navigation._get_repository_state(root)).stale)

            local original_load = git_hunk_navigation._load
            local reloads = 0
            rawset(git_hunk_navigation, "_load", function(arguments, callback)
                reloads = reloads + 1
                original_load(arguments, callback)
            end)

            press_keys("y")
            wait_for(function()
                return entries_count(root) == 1 and vim.api.nvim_win_get_cursor(0)[1] == 4
            end)
            rawset(git_hunk_navigation, "_load", original_load)

            assert.equal(1, reloads)
            assert.matches("%-two\n%+TWO", run_git(root, { "diff", "--cached", "--unified=0" }))
            assert.equal("FOUR", vim.api.nvim_buf_get_lines(0, 3, 4, false)[1])
            assert.is_true(git_add_submode.is_active())
        end)
    end)

    it("sees edits made after exiting when Git mode is immediately restarted", function()
        with_repo(function(root)
            commit_file(root, "file.txt", "one\ntwo\nthree\nfour\nfive\nsix\n")
            edit_file(vim.fs.joinpath(root, "file.txt"), { "one", "TWO", "three", "four", "five", "six" })

            git_add_submode.start()
            wait_for(function()
                return git_add_submode.is_active()
            end)
            press_keys("<Esc>")
            wait_for(function()
                return not git_add_submode.is_active()
            end)

            vim.api.nvim_buf_set_lines(0, 4, 5, false, { "FIVE" })
            vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
            git_add_submode.start()
            wait_for(function()
                return git_add_submode.is_active() and entries_count(root) == 2
            end)

            local state = assert(git_hunk_navigation._get_repository_state(root))
            assert.equal(2, #state.entries)
            assert.equal(2, state.entries[1].lnum)
            assert.equal(5, state.entries[2].lnum)
        end)
    end)

    it("shows a completion message once every hunk is staged", function()
        with_repo(function(root, messages)
            commit_file(root, "a.txt", "one\ntwo\n")
            edit_file(vim.fs.joinpath(root, "a.txt"), { "one", "TWO" })

            git_add_submode.start()
            wait_for(function()
                return git_add_submode.is_active()
            end)

            press_keys("y")
            wait_for(function()
                return not git_add_submode.is_active()
            end)

            local found = false

            for _, message in ipairs(messages) do
                if message:find("Git add is done.", 1, true) then
                    found = true
                end
            end

            assert.is_true(found)
        end)
    end)

    it("stages every hunk in the current file with `a` and advances to the next file", function()
        with_repo(function(root)
            commit_file(root, "a.txt", "one\ntwo\nthree\nfour\n")
            commit_file(root, "b.txt", "alpha\nbeta\n")
            edit_file(vim.fs.joinpath(root, "a.txt"), { "ONE", "two", "three", "FOUR" })
            edit_file(vim.fs.joinpath(root, "b.txt"), { "alpha", "BETA" })
            focus_file(vim.fs.joinpath(root, "a.txt"))

            git_add_submode.start()
            wait_for(function()
                return git_add_submode.is_active()
            end)
            assert.equal("a.txt", current_file_name())
            assert.is_true(entries_count(root) >= 3)

            press_keys("a")
            wait_for(function()
                return current_file_name() == "b.txt"
            end)

            local cached_a = run_git(root, { "diff", "--cached", "--unified=0", "--", "a.txt" })
            assert.matches("%-one\n%+ONE", cached_a)
            assert.matches("%-four\n%+FOUR", cached_a)
            assert.equal("", run_git(root, { "diff", "--cached", "--", "b.txt" }))
            assert.is_true(git_add_submode.is_active())
        end)
    end)

    it("exits with `q` without staging, restoring any pre-existing mapping", function()
        vim.keymap.set("n", "n", function() end, { desc = "custom n mapping" })

        with_repo(function(root)
            commit_file(root, "a.txt", "one\ntwo\n")
            edit_file(vim.fs.joinpath(root, "a.txt"), { "one", "TWO" })

            git_add_submode.start()
            wait_for(function()
                return git_add_submode.is_active()
            end)

            press_keys("q")
            wait_for(function()
                return not git_add_submode.is_active()
            end)

            assert.is_false(git_add_submode.is_active())
            assert.is_nil(find_legend_window())
            assert.equal("", run_git(root, { "diff", "--cached" }))
            assert.equal("custom n mapping", vim.fn.maparg("n", "n", false, true).desc)
            assert.is_true(vim.tbl_isempty(vim.fn.maparg("y", "n", false, true)))
        end)

        pcall(vim.keymap.del, "n", "n")
    end)

    it("exits with <Esc> without staging", function()
        with_repo(function(root)
            commit_file(root, "a.txt", "one\ntwo\n")
            edit_file(vim.fs.joinpath(root, "a.txt"), { "one", "TWO" })

            git_add_submode.start()
            wait_for(function()
                return git_add_submode.is_active()
            end)

            press_keys("<Esc>")
            wait_for(function()
                return not git_add_submode.is_active()
            end)

            assert.is_false(git_add_submode.is_active())
            assert.equal("", run_git(root, { "diff", "--cached" }))
        end)
    end)

    it("toggles the Git diff view with `v` without leaving the submode", function()
        local git_diff_view = require("modules.features.git_diff_view")

        with_repo(function(root)
            commit_file(root, "a.txt", "one\ntwo\n")
            edit_file(vim.fs.joinpath(root, "a.txt"), { "one", "TWO" })

            git_add_submode.start()
            wait_for(function()
                return git_add_submode.is_active()
            end)

            assert.is_false(git_diff_view.is_enabled())

            press_keys("v")
            wait_for(function()
                return git_diff_view.is_enabled()
            end)

            assert.is_true(git_diff_view.is_enabled())
            assert.is_true(git_add_submode.is_active())

            git_diff_view.toggle()
        end)
    end)

    it("repositions the legend window in the top-right corner on VimResized", function()
        local original_columns = vim.o.columns

        with_repo(function(root)
            commit_file(root, "a.txt", "one\ntwo\n")
            edit_file(vim.fs.joinpath(root, "a.txt"), { "one", "TWO" })

            git_add_submode.start()
            wait_for(function()
                return git_add_submode.is_active()
            end)

            local window = assert(find_legend_window())
            assert.equal(original_columns, vim.api.nvim_win_get_config(window).col)

            vim.o.columns = original_columns + 20
            vim.api.nvim_exec_autocmds("VimResized", {})

            assert.equal(vim.o.columns, vim.api.nvim_win_get_config(window).col)
        end)

        vim.o.columns = original_columns
    end)
end)
