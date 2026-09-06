--- Make sure `:ToggleGitDiffView` shows added, deleted, and changed lines.

local git_diff_view = require("modules.features.git_diff_view")

local _NAMESPACE = vim.api.nvim_create_namespace("my.git_diff_view")

--- Run a Git command inside `root`.
---
---@param root string The Git repository root.
---@param arguments string[] The Git arguments to run after `-C root`.
---@return string # The command's standard output.
local function run_git(root, arguments)
    vim.wait(120)

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

--- Remove a temporary test directory after leaving its buffer.
---
---@param path string The directory to remove.
local function remove_tree(path)
    vim.cmd("enew!")
    vim.wait(20)
    vim.fn.delete(path, "rf")
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
    end

    assert(ok, err)
end

--- Get the git diff view extmarks that are currently drawn.
---
---@param buffer integer? The buffer to inspect. Defaults to the current buffer.
---@return vim.api.keyset.get_extmark_item[] # The drawn extmarks.
local function get_extmarks(buffer)
    return vim.api.nvim_buf_get_extmarks(buffer or 0, _NAMESPACE, 0, -1, { details = true })
end

--- Get the plain text of every virtual line in `mark`.
---
---@param mark _my.git_diff_view.Mark The computed extmark to read.
---@return string[] # One string per virtual line.
local function get_virtual_line_text(mark)
    ---@type string[]
    local lines = {}

    for _, virtual_line in ipairs(mark.virtual_lines or {}) do
        ---@type string[]
        local pieces = {}

        for _, chunk in ipairs(virtual_line) do
            table.insert(pieces, chunk[1])
        end

        table.insert(lines, table.concat(pieces))
    end

    return lines
end

describe("modules.features.git_diff_view", function()
    ---@type string
    local _original_diffopt

    before_each(function()
        _original_diffopt = vim.o.diffopt
        vim.o.diffopt = "internal,filler,closeoff"
    end)

    after_each(function()
        vim.o.diffopt = _original_diffopt
    end)

    it("shows a deleted line under the line that came before it", function()
        local marks = git_diff_view.compute_marks({ "one", "two", "three" }, { "one", "three" }, 4)

        assert.equal(1, #marks)
        assert.equal(0, marks[1].row)
        assert.is_false(marks[1].virtual_lines_above)
        assert.are.same({ "two" }, get_virtual_line_text(marks[1]))
        assert.is_nil(marks[1].regions)
    end)

    it("shows a deleted first line above the new first line", function()
        local marks = git_diff_view.compute_marks({ "one", "two" }, { "two" }, 4)

        assert.equal(1, #marks)
        assert.equal(0, marks[1].row)
        assert.is_true(marks[1].virtual_lines_above)
        assert.are.same({ "one" }, get_virtual_line_text(marks[1]))
    end)

    it("highlights every added line", function()
        local marks = git_diff_view.compute_marks({ "one" }, { "one", "two", "" }, 4)

        assert.are.same({
            { line_highlight = "MyGitDiffViewAdd", row = 1 },
            { line_highlight = "MyGitDiffViewAdd", row = 2 },
        }, marks)
    end)

    it("highlights extra added lines inside a changed hunk", function()
        local marks = git_diff_view.compute_marks({ "one", "two" }, { "one", "TWO", "THREE" }, 4)

        assert.are.same({ "two" }, get_virtual_line_text(marks[1]))
        assert.equal(1, marks[2].row)
        assert.is_table(marks[2].regions)
        assert.are.same({ line_highlight = "MyGitDiffViewAdd", row = 2 }, marks[3])
    end)

    it("does not draw anything when nothing changed", function()
        assert.are.same({}, git_diff_view.compute_marks({ "one" }, { "one" }, 4))
    end)

    it("shows the previous line and highlights the changed part of the new line", function()
        local marks = git_diff_view.compute_marks({ "local foo = 10" }, { "local foo = 20" }, 4)

        assert.equal(2, #marks)

        assert.equal(0, marks[1].row)
        assert.is_true(marks[1].virtual_lines_above)
        assert.are.same({ "local foo = 10" }, get_virtual_line_text(marks[1]))

        assert.equal(0, marks[2].row)
        assert.are.same({ { end_column = 13, start_column = 12 } }, marks[2].regions)
    end)

    it("highlights the removed part of the deleted line", function()
        local marks = git_diff_view.compute_marks({ "local foo = 10" }, { "local foo = 20" }, 4)
        ---@type _my.git_diff_view.Chunk[]
        local chunks = marks[1].virtual_lines[1]

        assert.are.same({
            { "local foo = ", "MyGitDiffViewDelete" },
            { "1", "MyGitDiffViewDeleteText" },
            { "0", "MyGitDiffViewDelete" },
        }, chunks)
    end)

    it("expands tabs so deleted lines line up with the code", function()
        local marks = git_diff_view.compute_marks({ "\tone" }, { "\ttwo" }, 4)

        assert.are.same({ "    one" }, get_virtual_line_text(marks[1]))
    end)

    it("highlights whole lines when `inline:none` is used", function()
        local supported = pcall(function()
            vim.o.diffopt = "internal,filler,closeoff,inline:none"
        end)

        if not supported then
            return
        end

        local marks = git_diff_view.compute_marks({ "local foo = 10" }, { "local foo = 20" }, 4)

        assert.are.same({ { end_column = 14, start_column = 0 } }, marks[2].regions)
    end)

    it("keeps a cell for a deleted empty line", function()
        local marks = git_diff_view.compute_marks({ "one", "", "two" }, { "one", "two" }, 4)

        assert.are.same({ { { " ", "MyGitDiffViewDelete" } } }, marks[1].virtual_lines)
    end)

    it("ignores trailing carriage returns from CRLF blobs", function()
        assert.are.same({}, git_diff_view.compute_marks({ "one\r", "two\r" }, { "one", "two" }, 4))
    end)

    it("draws and clears extmarks with :ToggleGitDiffView", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })

            vim.cmd("silent edit " .. vim.fn.fnameescape(path))
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "TWO", "three", "four" })

            vim.cmd.ToggleGitDiffView()
            vim.wait(2000, function()
                return #get_extmarks() > 0
            end)

            local marks = get_extmarks()

            assert.is_true(git_diff_view.is_enabled())
            assert.is_true(#marks > 0)

            ---@type string[]
            local virtual_lines = {}
            ---@type integer[]
            local added_rows = {}
            ---@type integer[]
            local changed_rows = {}

            for _, mark in ipairs(marks) do
                for _, virtual_line in ipairs(mark[4].virt_lines or {}) do
                    ---@type string[]
                    local pieces = {}

                    for _, chunk in ipairs(virtual_line) do
                        table.insert(pieces, chunk[1])
                    end

                    table.insert(virtual_lines, table.concat(pieces))
                end

                if mark[4].line_hl_group == "MyGitDiffViewAdd" then
                    table.insert(added_rows, mark[2])
                end

                if mark[4].hl_group == "MyGitDiffViewChangeText" then
                    table.insert(changed_rows, mark[2])
                end
            end

            assert.are.same({ "two" }, virtual_lines)
            assert.are.same({ 1 }, changed_rows)
            assert.are.same({ 3 }, added_rows)

            vim.cmd.ToggleGitDiffView()
            vim.wait(120)

            assert.is_false(git_diff_view.is_enabled())
            assert.are.same({}, get_extmarks())
        end)

        remove_tree(root)
    end)

    it("keeps following its window when the displayed buffer changes", function()
        local root = make_repo()

        with_captured_notifications(function()
            local first = vim.fs.joinpath(root, "first.txt")
            local second = vim.fs.joinpath(root, "second.txt")
            write_text(first, "one\ntwo\nthree\n")
            write_text(second, "one\ntwo\nthree\n")
            run_git(root, { "add", "first.txt", "second.txt" })
            run_git(root, { "commit", "-m", "init" })

            write_text(first, "one\nFIRST\nthree\n")
            write_text(second, "one\nSECOND\nthree\n")

            vim.cmd("silent edit " .. vim.fn.fnameescape(first))

            local first_buffer = vim.api.nvim_get_current_buf()

            vim.cmd.ToggleGitDiffView()
            vim.wait(2000, function()
                return #get_extmarks(first_buffer) > 0
            end)

            assert.is_true(#get_extmarks(first_buffer) > 0)

            vim.cmd("silent edit " .. vim.fn.fnameescape(second))

            local second_buffer = vim.api.nvim_get_current_buf()

            vim.wait(2000, function()
                return #get_extmarks(second_buffer) > 0
            end)

            assert.is_true(git_diff_view.is_enabled())
            assert.is_true(#get_extmarks(second_buffer) > 0)
            assert.are.same({}, get_extmarks(first_buffer))

            vim.cmd.ToggleGitDiffView()
            vim.wait(120)

            assert.is_false(git_diff_view.is_enabled())
            assert.are.same({}, get_extmarks(second_buffer))
        end)

        remove_tree(root)
    end)

    it("keeps other windows alone when one window toggles the view", function()
        local root = make_repo()

        with_captured_notifications(function()
            local path = vim.fs.joinpath(root, "file.txt")
            write_text(path, "one\ntwo\nthree\n")
            run_git(root, { "add", "file.txt" })
            run_git(root, { "commit", "-m", "init" })
            write_text(path, "one\nTWO\nthree\n")

            vim.cmd("silent edit " .. vim.fn.fnameescape(path))
            vim.cmd("silent split")

            local other_window = vim.api.nvim_get_current_win()

            vim.cmd.ToggleGitDiffView()
            vim.wait(2000, function()
                return #get_extmarks() > 0
            end)

            assert.is_true(#get_extmarks() > 0)

            vim.cmd("silent wincmd w")

            assert.is_false(git_diff_view.is_enabled())
            assert.is_true(git_diff_view.is_enabled(other_window))

            vim.api.nvim_win_close(other_window, true)
            vim.wait(250)

            assert.are.same({}, get_extmarks())
        end)

        remove_tree(root)
    end)
end)
