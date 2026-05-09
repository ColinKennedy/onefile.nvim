local file_system_watcher = require("modules.plugins.file_system_watcher")

---@type integer[]
local _BUFFERS = {}

--- Write `lines` to `path` and wait for the filesystem metadata to move.
---
---@param path string An on-disk file path.
---@param lines string[] The new file contents.
local function write_external_file(path, lines)
    vim.fn.writefile(lines, path)
    vim.uv.fs_utime(path, os.time() + 5, os.time() + 5)
end

--- Create a temporary file-backed buffer.
---
---@param lines string[] The initial file contents.
---@return integer buffer The edited buffer.
---@return string path The created file path.
local function create_file_buffer(lines)
    local directory = vim.fn.tempname()

    vim.fn.mkdir(directory, "p")

    local path = vim.fs.joinpath(directory, "watched.txt")

    vim.fn.writefile(lines, path)
    vim.cmd("silent edit " .. vim.fn.fnameescape(path))

    local buffer = vim.api.nvim_get_current_buf()

    table.insert(_BUFFERS, buffer)

    return buffer, path
end

describe("modules.plugins.file_system_watcher", function()
    before_each(function()
        pcall(vim.cmd.stopinsert)
        ---@type integer[]
        _BUFFERS = {}
        file_system_watcher.setup({ poll_interval_ms = 50, reload_debounce_ms = 10 })
    end)

    after_each(function()
        pcall(vim.cmd.stopinsert)
        file_system_watcher.teardown()

        for _, buffer in ipairs(_BUFFERS) do
            if vim.api.nvim_buf_is_valid(buffer) then
                vim.api.nvim_buf_delete(buffer, { force = true })
            end
        end

        vim.cmd.enew({ bang = true })
    end)

    it("watches listed buffers that point to files on disk", function()
        local buffer, _ = create_file_buffer({ "original" })

        file_system_watcher.watch_buffer(buffer)

        assert.True(file_system_watcher.is_watching(buffer))
    end)

    it("does not watch unlisted scratch buffers", function()
        local buffer = vim.api.nvim_create_buf(false, true)

        table.insert(_BUFFERS, buffer)
        vim.api.nvim_set_current_buf(buffer)
        file_system_watcher.watch_buffer(buffer)

        assert.False(file_system_watcher.is_watching(buffer))
    end)

    it("reloads a watched buffer after an external file change", function()
        local buffer, path = create_file_buffer({ "original" })

        file_system_watcher.watch_buffer(buffer)
        write_external_file(path, { "changed" })

        assert.True(vim.wait(1000, function()
            return file_system_watcher.reload_if_changed(buffer)
                or vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] == "changed"
        end, 20))

        assert.equal("changed", vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1])
    end)

    it("reloads through Neovim's normal file-changed autocmd path", function()
        local buffer, path = create_file_buffer({ "local value = 1" })
        local group = vim.api.nvim_create_augroup("file_system_watcher.spec.file_changed", { clear = true })
        local did_fire = false

        vim.api.nvim_create_autocmd("FileChangedShellPost", {
            buffer = buffer,
            group = group,
            callback = function()
                did_fire = true
            end,
        })

        vim.bo[buffer].filetype = "lua"
        file_system_watcher.watch_buffer(buffer)
        write_external_file(path, { "local value = 2" })

        assert.True(vim.wait(1000, function()
            return file_system_watcher.reload_if_changed(buffer)
                or vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] == "local value = 2"
        end, 20))

        assert.True(did_fire)
        assert.equal("lua", vim.bo[buffer].filetype)
    end)

    it("does not overwrite unsaved buffer edits", function()
        local buffer, path = create_file_buffer({ "original" })

        file_system_watcher.watch_buffer(buffer)
        vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { "unsaved" })
        write_external_file(path, { "external" })

        assert.False(file_system_watcher.reload_if_changed(buffer))
        assert.equal("unsaved", vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1])
    end)
end)
