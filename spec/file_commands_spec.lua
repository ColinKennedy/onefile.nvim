--- Write `text` to `path`.
---
---@param path string The path to write.
---@param text string The file contents.
local function write_file(path, text)
    local file = assert(vim.uv.fs_open(path, "w", 438))

    assert(vim.uv.fs_write(file, text, 0))
    assert(vim.uv.fs_close(file))
end

--- Make a temporary directory for command specs.
---
---@return string # The created directory.
local function make_directory()
    local root = vim.fn.tempname()

    assert.equal(1, vim.fn.mkdir(root, "p"))

    return root
end

--- Run a Git command inside `root`.
---
---@param root string The Git repository root.
---@param arguments string[] The Git command arguments.
local function run_git(root, arguments)
    ---@type string[]
    local command = { "git", "-C", root }
    vim.list_extend(command, arguments)

    local result = vim.system(command, { text = true }):wait()

    assert.equal(0, result.code, result.stderr)
end

--- Edit `path` in the current window.
---
---@param path string The file path to edit.
local function edit_file(path)
    require("modules.utilities.core_helpers").with_file_messages_suppressed(function()
        local buffer = vim.api.nvim_create_buf(true, false)

        vim.api.nvim_buf_set_name(buffer, path)
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.fn.readfile(path))
        vim.bo[buffer].modified = false
        vim.api.nvim_set_current_buf(buffer)
    end)
end

--- Create a real terminal buffer for command tests.
---
---@return integer # The terminal buffer.
local function make_terminal_buffer()
    local original = vim.api.nvim_get_current_buf()
    local buffer = vim.api.nvim_create_buf(true, true)

    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_open_term(buffer, {})
    vim.api.nvim_set_current_buf(original)

    return buffer
end

--- Capture vim.notify calls while `callback` runs.
---
---@param callback fun(): nil The function to run.
---@return {message: string, level: integer?}[] # Captured notifications.
local function capture_notifications(callback)
    local notify = vim.notify
    ---@type {message: string, level: integer?}[]
    local notifications = {}

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(message, level)
        table.insert(notifications, { message = message, level = level })
    end

    local ok, error_message = pcall(callback)
    vim.notify = notify

    if not ok then
        error(error_message, 0)
    end

    return notifications
end

--- Force-remove buffers left behind by earlier specs.
local function clear_buffers()
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buffer) then
            pcall(vim.api.nvim_buf_delete, buffer, { force = true })
        end
    end

    vim.cmd.enew({ bang = true })
end

describe("file commands", function()
    before_each(function()
        clear_buffers()
    end)

    after_each(function()
        clear_buffers()
    end)

    it("deletes hidden non-terminal buffers with BufferOnly", function()
        local current = vim.api.nvim_create_buf(true, true)
        local hidden = vim.api.nvim_create_buf(true, true)
        local terminal = make_terminal_buffer()
        vim.api.nvim_set_current_buf(current)

        vim.cmd.BufferOnly()

        assert.True(vim.api.nvim_buf_is_valid(current))
        assert.False(vim.api.nvim_buf_is_valid(hidden))
        assert.True(vim.api.nvim_buf_is_valid(terminal))
        vim.api.nvim_buf_delete(terminal, { force = true })
    end)

    it("deletes hidden terminal buffers with BufferOnly all", function()
        local current = vim.api.nvim_create_buf(true, true)
        local terminal = make_terminal_buffer()
        vim.api.nvim_set_current_buf(current)

        vim.cmd("BufferOnly --all")

        assert.True(vim.api.nvim_buf_is_valid(current))
        assert.False(vim.api.nvim_buf_is_valid(terminal))
    end)

    it("closes non-terminal windows and deletes their buffers with BufferOnly", function()
        local current = vim.api.nvim_create_buf(true, true)
        local sibling = vim.api.nvim_create_buf(true, true)
        local hidden = vim.api.nvim_create_buf(true, true)

        vim.api.nvim_set_current_buf(current)
        vim.cmd.vsplit()
        local sibling_window = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(sibling_window, sibling)
        vim.cmd.wincmd("p")

        vim.cmd.BufferOnly()

        assert.True(vim.api.nvim_buf_is_valid(current))
        assert.False(vim.api.nvim_buf_is_valid(sibling))
        assert.False(vim.api.nvim_buf_is_valid(hidden))
        assert.False(vim.api.nvim_win_is_valid(sibling_window))
        assert.equal(current, vim.api.nvim_get_current_buf())
    end)

    it("keeps terminal windows and buffers with BufferOnly", function()
        local current = vim.api.nvim_create_buf(true, true)
        local terminal = make_terminal_buffer()

        vim.api.nvim_set_current_buf(current)
        vim.cmd.vsplit()
        local terminal_window = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(terminal_window, terminal)
        vim.cmd.wincmd("p")

        vim.cmd.BufferOnly()

        assert.True(vim.api.nvim_buf_is_valid(current))
        assert.True(vim.api.nvim_buf_is_valid(terminal))
        assert.True(vim.api.nvim_win_is_valid(terminal_window))

        vim.api.nvim_win_close(terminal_window, true)
        vim.api.nvim_buf_delete(terminal, { force = true })
    end)

    it("describes BufferOnly as window-aware only", function()
        local command = vim.api.nvim_get_commands({ builtin = false }).BufferOnly

        assert.equal(":only, but window-aware", command.definition)
    end)

    it("changes directory to the Git repository root with Gcd", function()
        local original_cwd = vim.fn.getcwd()
        local root = make_directory()
        local nested = vim.fs.joinpath(root, "nested", "child")

        assert.equal(1, vim.fn.mkdir(nested, "p"))
        run_git(root, { "init" })
        vim.cmd.cd(nested)

        local notifications = capture_notifications(function()
            vim.cmd.Gcd()
        end)

        assert.equal(vim.fs.normalize(root), vim.fs.normalize(vim.fn.getcwd()))
        assert.equal(vim.log.levels.INFO, notifications[1].level)
        vim.cmd.cd(original_cwd)
        vim.fn.delete(root, "rf")
    end)

    it("notifies when Gcd is used outside of a Git repository", function()
        local original_cwd = vim.fn.getcwd()
        local root = make_directory()

        vim.cmd.cd(root)

        local notifications = capture_notifications(function()
            vim.cmd.Gcd()
        end)

        assert.equal(vim.log.levels.ERROR, notifications[1].level)
        assert.matches("No Git repository root", notifications[1].message)
        vim.cmd.cd(original_cwd)
        vim.fn.delete(root, "rf")
    end)

    it("deletes the current file and buffer with Delete", function()
        local root = make_directory()
        local path = vim.fs.joinpath(root, "delete-me.txt")

        write_file(path, "hello\n")
        edit_file(path)

        local buffer = vim.api.nvim_get_current_buf()

        vim.cmd.Delete()

        assert.equal(0, vim.fn.filereadable(path))
        assert.False(vim.api.nvim_buf_is_valid(buffer))
    end)

    it("notifies when Delete is used from an unlisted buffer", function()
        local buffer = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_set_current_buf(buffer)

        local notifications = capture_notifications(function()
            vim.cmd.Delete()
        end)

        assert.equal(vim.log.levels.ERROR, notifications[1].level)
        assert.matches("requires a listed buffer", notifications[1].message)
    end)

    it("moves the current file using a relative path", function()
        local root = make_directory()
        local path = vim.fs.joinpath(root, "before.txt")
        local target = vim.fs.joinpath(root, "after.txt")

        write_file(path, "hello\n")
        edit_file(path)

        vim.cmd("silent Move after.txt")

        assert.equal(0, vim.fn.filereadable(path))
        assert.equal(1, vim.fn.filereadable(target))
        assert.equal(target, vim.api.nvim_buf_get_name(0))
    end)

    it("moves the current file using a parent-relative path", function()
        local root = make_directory()
        local child = vim.fs.joinpath(root, "child")
        local path = vim.fs.joinpath(child, "before.txt")
        local target = vim.fs.joinpath(root, "after.txt")

        assert.equal(1, vim.fn.mkdir(child, "p"))
        write_file(path, "hello\n")
        edit_file(path)

        vim.cmd("silent Move ../after.txt")

        assert.equal(0, vim.fn.filereadable(path))
        assert.equal(1, vim.fn.filereadable(target))
        assert.equal(target, vim.api.nvim_buf_get_name(0))
    end)

    it("moves the current file using an absolute path", function()
        local root = make_directory()
        local path = vim.fs.joinpath(root, "before.txt")
        local target = vim.fs.joinpath(root, "after.txt")

        write_file(path, "hello\n")
        edit_file(path)

        vim.cmd("silent Move " .. vim.fn.fnameescape(target))

        assert.equal(0, vim.fn.filereadable(path))
        assert.equal(1, vim.fn.filereadable(target))
        assert.equal(target, vim.api.nvim_buf_get_name(0))
    end)

    it("refuses to move over an existing file without bang", function()
        local root = make_directory()
        local path = vim.fs.joinpath(root, "before.txt")
        local target = vim.fs.joinpath(root, "after.txt")

        write_file(path, "hello\n")
        write_file(target, "occupied\n")
        edit_file(path)

        local notifications = capture_notifications(function()
            vim.cmd.Move("after.txt")
        end)

        assert.equal(vim.log.levels.ERROR, notifications[1].level)
        assert.matches("already exists", notifications[1].message)
        assert.equal(1, vim.fn.filereadable(path))
        assert.equal("occupied\n", table.concat(vim.fn.readfile(target), "\n") .. "\n")
    end)

    it("moves over an existing file with Move bang", function()
        local root = make_directory()
        local path = vim.fs.joinpath(root, "before.txt")
        local target = vim.fs.joinpath(root, "after.txt")

        write_file(path, "hello\n")
        write_file(target, "occupied\n")
        edit_file(path)

        vim.cmd("silent Move! after.txt")

        assert.equal(0, vim.fn.filereadable(path))
        assert.equal(1, vim.fn.filereadable(target))
        assert.are.same({ "hello" }, vim.fn.readfile(target))
        assert.equal(target, vim.api.nvim_buf_get_name(0))
    end)

    it("moves unsaved buffer changes into the target file", function()
        local root = make_directory()
        local path = vim.fs.joinpath(root, "before.txt")
        local target = vim.fs.joinpath(root, "after.txt")

        write_file(path, "saved\n")
        edit_file(path)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })

        vim.cmd("silent Move after.txt")

        assert.equal(0, vim.fn.filereadable(path))
        assert.are.same({ "unsaved" }, vim.fn.readfile(target))
        assert.equal(target, vim.api.nvim_buf_get_name(0))
        assert.False(vim.bo.modified)
    end)

    it("allows a normal write after Move bang overwrites a file", function()
        local root = make_directory()
        local path = vim.fs.joinpath(root, "before.txt")
        local target = vim.fs.joinpath(root, "after.txt")

        write_file(path, "before\n")
        write_file(target, "occupied\n")
        edit_file(path)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "moved", "changed" })

        vim.cmd("Move! after.txt")
        vim.api.nvim_buf_set_lines(0, 1, 2, false, { "written" })
        vim.cmd("silent write")

        assert.are.same({ "moved", "written" }, vim.fn.readfile(target))
        assert.equal(target, vim.api.nvim_buf_get_name(0))
    end)
end)
