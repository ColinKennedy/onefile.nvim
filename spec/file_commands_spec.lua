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

--- Edit `path` in the current window.
---
---@param path string The file path to edit.
local function edit_file(path)
    local buffer = vim.api.nvim_create_buf(true, false)

    vim.api.nvim_buf_set_name(buffer, path)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.fn.readfile(path))
    vim.bo[buffer].modified = false
    vim.api.nvim_set_current_buf(buffer)
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

describe("file commands", function()
    after_each(function()
        vim.cmd.enew({ bang = true })
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

        vim.cmd.Move("after.txt")

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

        vim.cmd.Move("../after.txt")

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

        vim.cmd.Move(target)

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

        vim.cmd("Move! after.txt")

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

        vim.cmd.Move("after.txt")

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
