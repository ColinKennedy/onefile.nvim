local aerial = require("modules.plugins.aerial")
local core_helpers = require("modules.utilities.core_helpers")
local file_tree = require("modules.plugins.file_tree")

--- Run a `git` command in `root` and make sure that it succeeds.
---
---@param root string The Git repository root.
---@param arguments string[] The Git command arguments.
---@return string # The command stdout text.
---
local function run_git(root, arguments)
    ---@type string[]
    local command = { "git", "-C", root }
    vim.list_extend(command, arguments)

    local result = vim.system(command, { text = true }):wait()

    assert.equal(0, result.code, result.stderr)

    return result.stdout or ""
end

--- Write `text` to `path`, creating parent directories as needed.
---
---@param path string An absolute file path to write to.
---@param text string The blob of text to write.
---
local function write_text(path, text)
    assert.equal(1, vim.fn.mkdir(vim.fs.dirname(path), "p"))

    local file = assert(vim.uv.fs_open(path, "w", 438))
    assert(vim.uv.fs_write(file, text, 0))
    assert(vim.uv.fs_close(file))
end

--- Make a temporary Git repository with a few tracked and ignored files.
---
---@return string # The created repository root.
---
local function make_repository()
    local root = assert(vim.uv.fs_mkdtemp(vim.fs.joinpath(vim.uv.os_tmpdir(), "file-tree-spec-XXXXXX")))
    root = vim.uv.fs_realpath(root) or root

    run_git(root, { "init" })
    run_git(root, { "config", "user.email", "test@example.com" })
    run_git(root, { "config", "user.name", "Test User" })

    write_text(vim.fs.joinpath(root, ".gitignore"), "*.log\n")
    write_text(vim.fs.joinpath(root, "src", "main.py"), "print('hello')\n")
    write_text(vim.fs.joinpath(root, "notes.md"), "# Notes\n")
    write_text(vim.fs.joinpath(root, "ignored.log"), "ignored\n")
    run_git(root, { "add", ".gitignore", "src/main.py" })
    run_git(root, { "commit", "-m", "Initial commit" })

    return root
end

--- Get the display name of every row in `rows`.
---
---@param rows _my.file_tree.Entry[] The tree rows to inspect.
---@return string[] # The found display names.
---
local function names(rows)
    ---@type string[]
    local output = {}

    for _, row in ipairs(rows) do
        table.insert(output, row.name)
    end

    return output
end

--- Get every line in `buffer` as one blob of text.
---
---@param buffer integer The Vim buffer to read.
---@return string # The buffer text.
---
local function buffer_text(buffer)
    return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
end

--- Wait until `predicate` passes or fail the test.
---
---@param predicate fun(): boolean? The condition to wait for.
---
local function wait_for(predicate)
    assert.True(vim.wait(10000, predicate, 20))
end

--- Find a window that shows a file tree buffer that lost its 'filetype'.
---
---@return integer? # The found window, if any.
---
local function get_stale_file_tree_window()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)

        local is_stale_tree = vim.bo[buffer].filetype ~= "filetree"
            and vim.startswith(vim.api.nvim_buf_get_name(buffer), "filetree://")

        if is_stale_tree then
            return window
        end
    end

    return nil
end

--- Find a window that shows a file tree buffer.
---
---@return integer? # The found window, if any.
---
local function get_file_tree_window()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)

        if vim.bo[buffer].filetype == "filetree" then
            return window
        end
    end

    return nil
end

---@return integer?
local function get_aerial_window()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)

        if vim.bo[buffer].filetype == "aerial" then
            return window
        end
    end

    return nil
end

local function close_file_tree_windows()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)
        local name = vim.api.nvim_buf_get_name(buffer)

        if vim.bo[buffer].filetype == "filetree" or vim.startswith(name, "filetree://") then
            pcall(vim.api.nvim_win_close, window, true)
        end
    end
end

describe("file tree", function()
    ---@type boolean
    local original_nerdfont_allowed

    before_each(function()
        original_nerdfont_allowed = core_helpers.IS_NERDFONT_ALLOWED
        close_file_tree_windows()
        vim.cmd.enew({ bang = true })
    end)

    after_each(function()
        core_helpers.IS_NERDFONT_ALLOWED = original_nerdfont_allowed
        aerial._close_all()
        close_file_tree_windows()
        vim.cmd.enew({ bang = true })
    end)

    it("shows Git-visible files by default", function()
        local root = make_repository()
        local rows = file_tree._P.build_rows(root, false, { [vim.fs.normalize(root)] = true })

        assert.are.same({ "src", ".gitignore", "notes.md" }, names(rows))
        vim.fn.delete(root, "rf")
    end)

    it("can show ignored files when show-all is enabled", function()
        local root = make_repository()
        local rows = file_tree._P.build_rows(root, true, { [vim.fs.normalize(root)] = true })

        assert.are.same({ "src", ".gitignore", "ignored.log", "notes.md" }, names(rows))
        vim.fn.delete(root, "rf")
    end)

    it("expands and collapses directories", function()
        local root = make_repository()
        ---@type table<string, boolean>
        local expanded = { [vim.fs.normalize(root)] = true }
        local collapsed_rows = file_tree._P.build_rows(root, false, expanded)

        assert.are.same({ "src", ".gitignore", "notes.md" }, names(collapsed_rows))

        expanded[vim.fs.normalize(vim.fs.joinpath(root, "src"))] = true

        local expanded_rows = file_tree._P.build_rows(root, false, expanded)

        assert.are.same({ "src", "main.py", ".gitignore", "notes.md" }, names(expanded_rows))
        vim.fn.delete(root, "rf")
    end)

    it("uses ASCII icons when Nerd Font icons are disabled", function()
        local root = make_repository()

        core_helpers.IS_NERDFONT_ALLOWED = false

        assert.equal("D", file_tree._P.get_icon(vim.fs.joinpath(root, "src")))
        assert.equal("F", file_tree._P.get_icon(vim.fs.joinpath(root, "src", "main.py")))
        vim.fn.delete(root, "rf")
    end)

    it("uses a Python file icon when Nerd Font icons are enabled", function()
        local root = make_repository()

        core_helpers.IS_NERDFONT_ALLOWED = true

        assert.is_false(file_tree._P.get_icon(vim.fs.joinpath(root, "src", "main.py")) == "F")
        vim.fn.delete(root, "rf")
    end)

    it("opens selected files in the source window", function()
        local root = make_repository()
        local source_window = vim.api.nvim_get_current_win()

        file_tree._open(root)

        local tree_window = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_cursor(tree_window, { 1, 0 })
        file_tree._expand()
        vim.api.nvim_win_set_cursor(tree_window, { 2, 0 })
        core_helpers.with_file_messages_suppressed(function()
            file_tree._open_entry()
        end)

        assert.equal(source_window, vim.api.nvim_get_current_win())
        assert.equal(
            vim.fs.normalize(vim.fs.joinpath(root, "src", "main.py")),
            vim.fs.normalize(vim.api.nvim_buf_get_name(0))
        )
        vim.fn.delete(root, "rf")
    end)

    it("expands and collapses all directories under the current row", function()
        local root = make_repository()
        write_text(vim.fs.joinpath(root, "src", "package", "util.py"), "print('util')\n")
        run_git(root, { "add", "src/package/util.py" })

        file_tree._open(root)

        file_tree._expand_all()

        assert.is_not_nil(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):match("util%.py"))

        file_tree._collapse_all()

        assert.is_nil(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):match("main%.py"))
        assert.is_nil(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):match("util%.py"))
        vim.fn.delete(root, "rf")
    end)

    it("sets winfixbuf on the file tree window", function()
        local root = make_repository()

        file_tree._open(root)

        assert.True(vim.wo[vim.api.nvim_get_current_win()].winfixbuf)
        vim.fn.delete(root, "rf")
    end)

    it("opens selected files in the most recent non-tree window", function()
        local root = make_repository()
        local first_window = vim.api.nvim_get_current_win()

        file_tree._open(root)
        vim.api.nvim_set_current_win(first_window)
        vim.cmd.vsplit()

        local second_window = vim.api.nvim_get_current_win()

        file_tree._toggle()

        local tree_window = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_cursor(tree_window, { 1, 0 })
        file_tree._expand()
        vim.api.nvim_win_set_cursor(tree_window, { 2, 0 })
        core_helpers.with_file_messages_suppressed(function()
            file_tree._open_entry()
        end)

        assert.equal(second_window, vim.api.nvim_get_current_win())
        assert.equal(
            vim.fs.normalize(vim.fs.joinpath(root, "src", "main.py")),
            vim.fs.normalize(vim.api.nvim_buf_get_name(0))
        )
        vim.fn.delete(root, "rf")
    end)

    it("registers buffer-local navigation and show-all mappings", function()
        local root = make_repository()

        file_tree._open(root)

        for _, key in ipairs({ "h", "l", "H", "L", "<CR>", "<leader>sa" }) do
            local mapping = vim.fn.maparg(key, "n", false, true)

            assert.is_function(mapping.callback)
        end

        vim.fn.delete(root, "rf")
    end)

    it("toggles showing ignored files from the tree buffer", function()
        local root = make_repository()

        file_tree._open(root)

        assert.is_nil(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):match("ignored%.log"))

        local mapping = vim.fn.maparg("<leader>sa", "n", false, true)
        mapping.callback()

        assert.is_not_nil(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):match("ignored%.log"))
        vim.fn.delete(root, "rf")
    end)

    it("registers a toggle mapping", function()
        local mapping = vim.fn.maparg("<Space>F", "n", false, true)

        assert.is_function(mapping.callback)
        assert.equal("Toggle/Show the [f]ile tree.", mapping.desc)
    end)

    it("refreshes when a visible root file is deleted externally", function()
        local root = make_repository()

        file_tree._open(root)

        local buffer = vim.api.nvim_get_current_buf()

        assert.is_not_nil(buffer_text(buffer):match("notes%.md"))
        assert.equal(0, vim.fn.delete(vim.fs.joinpath(root, "notes.md")))

        wait_for(function()
            return buffer_text(buffer):match("notes%.md") == nil
        end)

        vim.fn.delete(root, "rf")
    end)

    it("refreshes when a file inside an expanded nested directory is deleted externally", function()
        local root = make_repository()
        local nested_file = vim.fs.joinpath(root, "src", "package", "util.py")

        write_text(nested_file, "print('util')\n")
        run_git(root, { "add", "src/package/util.py" })
        file_tree._open(root)

        local buffer = vim.api.nvim_get_current_buf()

        file_tree._expand_all()

        assert.is_not_nil(buffer_text(buffer):match("util%.py"))
        assert.equal(0, vim.fn.delete(nested_file))

        wait_for(function()
            return buffer_text(buffer):match("util%.py") == nil
        end)

        vim.fn.delete(root, "rf")
    end)

    it("serializes the root, linked source buffer, show-all setting, and expanded directories", function()
        local root = make_repository()
        local source_name = vim.fs.joinpath(root, "notes.md")

        core_helpers.with_file_messages_suppressed(function()
            vim.cmd.edit(vim.fn.fnameescape(source_name))
        end)

        file_tree._open(root)
        file_tree._expand()
        file_tree._toggle_show_all()

        local entries = file_tree._get_session_entries()

        assert.equal(1, #entries)
        assert.equal(vim.fs.normalize(root), entries[1].root)
        assert.equal(vim.fs.normalize(source_name), vim.fs.normalize(entries[1].source_name))
        assert.True(entries[1].show_all)
        assert.True(vim.tbl_contains(entries[1].expanded, vim.fs.normalize(vim.fs.joinpath(root, "src"))))
        assert.is_not_nil(file_tree._serialize_session_restore():match("modules%.plugins%.file_tree"))
        assert.equal("", file_tree._serialize_session_restore(root .. "-other"))
        vim.fn.delete(root, "rf")
    end)

    it("restores file tree sessions with expanded directories and the linked source window", function()
        local root = make_repository()
        local source_name = vim.fs.joinpath(root, "notes.md")

        core_helpers.with_file_messages_suppressed(function()
            vim.cmd.edit(vim.fn.fnameescape(source_name))
        end)

        local source_window = vim.api.nvim_get_current_win()

        file_tree.restore_session({
            {
                expanded = { vim.fs.normalize(root), vim.fs.normalize(vim.fs.joinpath(root, "src")) },
                root = vim.fs.normalize(root),
                show_all = true,
                source_name = source_name,
            },
        })

        local tree_window = get_file_tree_window()

        assert.is_not_nil(tree_window)
        ---@cast tree_window integer
        assert.equal(source_window, vim.api.nvim_get_current_win())

        local tree_buffer = vim.api.nvim_win_get_buf(tree_window)
        local text = buffer_text(tree_buffer)

        assert.is_not_nil(text:match("main%.py"))
        assert.is_not_nil(text:match("ignored%.log"))
        vim.fn.delete(root, "rf")
    end)

    it("restores non-empty file trees from stale buffers created by mksession", function()
        local root = make_repository()
        local source_name = vim.fs.joinpath(root, "notes.md")

        core_helpers.with_file_messages_suppressed(function()
            vim.cmd.edit(vim.fn.fnameescape(source_name))
        end)

        local source_window = vim.api.nvim_get_current_win()

        vim.cmd.vsplit()

        local stale_buffer = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_name(stale_buffer, "filetree://" .. vim.fs.normalize(root))
        vim.api.nvim_win_set_buf(0, stale_buffer)
        vim.api.nvim_set_current_win(source_window)

        assert.equal("", vim.bo[stale_buffer].filetype)
        assert.are.same({
            {
                expanded = { vim.fs.normalize(root) },
                root = vim.fs.normalize(root),
                show_all = false,
                source_window = get_stale_file_tree_window(),
            },
        }, file_tree._get_stale_session_entries())

        file_tree._restore_stale_session_windows()

        local tree_window = assert(get_file_tree_window())
        local tree_buffer = vim.api.nvim_win_get_buf(tree_window)
        local text = buffer_text(tree_buffer)

        assert.equal("filetree", vim.bo[tree_buffer].filetype)
        assert.is_nil(get_stale_file_tree_window())
        assert.is_not_nil(text:match("src/"))
        assert.is_not_nil(text:match("notes%.md"))
        assert.is_not_nil(text:match("%.gitignore"))
        vim.fn.delete(root, "rf")
    end)

    it("restores stale file trees on SessionLoadPost with filetype and non-empty contents", function()
        local root = make_repository()

        vim.cmd.vsplit()

        local stale_buffer = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_name(stale_buffer, "filetree://" .. vim.fs.normalize(root))
        vim.api.nvim_win_set_buf(0, stale_buffer)
        vim.api.nvim_exec_autocmds("SessionLoadPost", { modeline = false })

        wait_for(function()
            local tree_window = get_file_tree_window()

            if tree_window == nil then
                return false
            end

            local tree_buffer = vim.api.nvim_win_get_buf(tree_window)

            return vim.bo[tree_buffer].filetype == "filetree" and buffer_text(tree_buffer):match("notes%.md") ~= nil
        end)

        local tree_window = assert(get_file_tree_window())
        local tree_buffer = vim.api.nvim_win_get_buf(tree_window)

        assert.equal("filetree", vim.bo[tree_buffer].filetype)
        assert.is_not_nil(buffer_text(tree_buffer):match("src/"))
        vim.fn.delete(root, "rf")
    end)

    it("reloads Sessionx sidecars with a non-empty file tree for the saved project", function()
        local root = make_repository()
        local session = vim.fs.joinpath(root, "Session.vim")
        local original_cwd = vim.fn.getcwd(-1, -1)
        local branch = vim.trim(run_git(root, { "branch", "--show-current" }))
        local sidecar = vim.fs.joinpath(root, ".sessions", branch, ".file_tree.lua")

        local ok, error_ = pcall(function()
            vim.cmd.tcd(vim.fn.fnameescape(root))
            file_tree._open(root)

            vim.cmd("mksession! " .. vim.fn.fnameescape(session))

            assert.equal(1, vim.fn.filereadable(sidecar))

            local sidecar_text = table.concat(vim.fn.readfile(sidecar), "\n")

            assert.is_not_nil(sidecar_text:match(vim.pesc(vim.fs.normalize(root))))
            assert.is_nil(sidecar_text:match("/tmp/nvim"))

            close_file_tree_windows()
            assert.is_nil(get_file_tree_window())

            vim.cmd.source(vim.fn.fnameescape(sidecar))

            local tree_window = assert(get_file_tree_window())
            local tree_buffer = vim.api.nvim_win_get_buf(tree_window)
            local text = buffer_text(tree_buffer)

            assert.equal("filetree", vim.bo[tree_buffer].filetype)
            assert.is_not_nil(text:match("src/"))
            assert.is_not_nil(text:match("notes%.md"))
        end)

        vim.cmd.tcd(vim.fn.fnameescape(original_cwd))
        vim.fn.delete(root, "rf")

        if not ok then
            error(error_)
        end
    end)

    it("reloads three-window aerial and file tree sessions for different focused files", function()
        local root = make_repository()
        local session = vim.fs.joinpath(root, "Session.vim")
        local original_cwd = vim.fn.getcwd(-1, -1)
        local branch = vim.trim(run_git(root, { "branch", "--show-current" }))
        local sessionx = vim.fs.joinpath(root, ".sessions", branch, "Sessionx.vim")
        local aerial_sidecar = vim.fs.joinpath(root, ".sessions", branch, ".aerial.lua")
        local tree_sidecar = vim.fs.joinpath(root, ".sessions", branch, ".file_tree.lua")
        ---@type string[]
        local source_paths = {
            vim.fs.joinpath(root, "src", "main.py"),
            vim.fs.joinpath(root, "notes.md"),
            vim.fs.joinpath(root, ".gitignore"),
        }

        write_text(source_paths[1], "def main():\n    return 1\n")

        local ok, error_ = pcall(function()
            vim.cmd.tcd(vim.fn.fnameescape(root))

            for _, source_path in ipairs(source_paths) do
                aerial._close_all()
                close_file_tree_windows()
                vim.cmd("silent! only")
                vim.cmd("silent edit " .. vim.fn.fnameescape(source_path))
                local source_window = vim.api.nvim_get_current_win()

                aerial._open_for_window(source_window, false)
                vim.api.nvim_set_current_win(source_window)
                file_tree._open(root)
                vim.api.nvim_set_current_win(source_window)

                assert.equal(3, #vim.api.nvim_list_wins())
                assert.is_not_nil(get_aerial_window())
                assert.is_not_nil(get_file_tree_window())

                vim.cmd("mksession! " .. vim.fn.fnameescape(session))

                assert.equal(1, vim.fn.filereadable(sessionx))
                assert.equal(1, vim.fn.filereadable(aerial_sidecar))
                assert.equal(1, vim.fn.filereadable(tree_sidecar))
                assert.is_not_nil(table.concat(vim.fn.readfile(aerial_sidecar), "\n"):find(source_path, 1, true))
                assert.is_not_nil(table.concat(vim.fn.readfile(tree_sidecar), "\n"):find(source_path, 1, true))

                aerial._close_all()
                close_file_tree_windows()
                vim.cmd("silent! only")
                vim.cmd("silent source " .. vim.fn.fnameescape(session))

                local restored_aerial_window = assert(get_aerial_window())
                local restored_tree_window = assert(get_file_tree_window())
                local tree_buffer = vim.api.nvim_win_get_buf(restored_tree_window)

                assert.equal(3, #vim.api.nvim_list_wins())
                assert.equal("aerial", vim.bo[vim.api.nvim_win_get_buf(restored_aerial_window)].filetype)
                assert.equal("filetree", vim.bo[tree_buffer].filetype)
                assert.is_not_nil(buffer_text(tree_buffer):match("src/"))
                assert.is_not_nil(buffer_text(tree_buffer):match("notes%.md"))
            end
        end)

        vim.cmd.tcd(vim.fn.fnameescape(original_cwd))
        aerial._close_all()
        close_file_tree_windows()
        vim.fn.delete(root, "rf")

        if not ok then
            error(error_)
        end
    end)

    it("saves the active session without errors when the file tree window is focused", function()
        require("modules.features.sessions")

        local root = make_repository()
        local session = vim.fs.joinpath(root, "Session.vim")
        local original_cwd = vim.fn.getcwd(-1, -1)
        local original_notify = vim.notify
        ---@type string[]
        local notifications = {}
        local branch = vim.trim(run_git(root, { "branch", "--show-current" }))
        local branch_session = vim.fs.joinpath(root, ".sessions", branch, "Session.vim")

        local ok, error_ = pcall(function()
            ---@diagnostic disable-next-line: duplicate-set-field
            vim.notify = function(message, level, options)
                table.insert(notifications, tostring(message))
                return original_notify(message, level, options)
            end

            vim.cmd.tcd(vim.fn.fnameescape(root))
            vim.cmd("silent edit " .. vim.fn.fnameescape(vim.fs.joinpath(root, "src", "main.py")))
            local source_window = vim.api.nvim_get_current_win()

            file_tree._open(root)
            assert(get_file_tree_window())

            vim.api.nvim_set_current_win(source_window)
            vim.cmd("mksession! " .. vim.fn.fnameescape(session))

            close_file_tree_windows()
            vim.cmd("silent! only")
            vim.cmd("silent source " .. vim.fn.fnameescape(session))

            local tree_window = assert(get_file_tree_window())
            vim.api.nvim_set_current_win(tree_window)

            local leave_ok, leave_error = pcall(function()
                vim.api.nvim_exec_autocmds("VimLeavePre", {})
            end)

            assert.True(leave_ok)
            assert.is_nil(leave_error)
            assert.equal(1, vim.fn.filereadable(branch_session))

            for _, message in ipairs(notifications) do
                assert.is_nil(message:find("Cannot save", 1, true))
                assert.is_nil(message:find("No VCS root", 1, true))
                assert.is_nil(message:find("No branch", 1, true))
            end
        end)

        vim.notify = original_notify
        vim.cmd([[let v:this_session = ""]])
        vim.cmd.tcd(vim.fn.fnameescape(original_cwd))
        aerial._close_all()
        close_file_tree_windows()
        vim.fn.delete(root, "rf")

        if not ok then
            error(error_)
        end
    end)
end)
