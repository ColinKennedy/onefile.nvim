--- Automatically reload listed file buffers after external file changes.

local M = {}
local _P = {}

local _GROUP_NAME = "my.file_system_watcher"

---@class _my.file_system_watcher.Options
---@field poll_interval_ms integer?
---    How frequently libuv should check watched files for stat changes.
---@field reload_debounce_ms integer?
---    How long to wait before reloading after a file-change notification.

---@class _my.file_system_watcher.Watch
---@field path string The watched on-disk file path.
---@field poller any The libuv fs_poll handle for `path`.
---@field signature string? The most recently-observed file metadata.
---@field reload_timer any? A one-shot timer used to debounce reloads.

---@type _my.file_system_watcher.Options
local _OPTIONS = {
    poll_interval_ms = 1000,
    reload_debounce_ms = 100,
}

---@type table<integer, _my.file_system_watcher.Watch>
local _WATCHES = {}

--- Build a small comparable value from a file's current metadata.
---
---@param path string An absolute file path.
---@return string? # The file signature, or `nil` if `path` cannot be read.
function _P.get_file_signature(path)
    local stat = vim.uv.fs_stat(path)

    if not stat then
        return nil
    end

    local modified = stat.mtime or {}

    return string.format("%s:%s:%s", stat.size or 0, modified.sec or 0, modified.nsec or 0)
end

--- Check if `buffer` is a listed file buffer that can be watched.
---
---@param buffer integer A Neovim buffer handle.
---@return boolean # If `buffer` points to a listed on-disk file, return `true`.
function _P.is_watchable_buffer(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return false
    end

    if not vim.bo[buffer].buflisted or vim.bo[buffer].buftype ~= "" then
        return false
    end

    local path = vim.api.nvim_buf_get_name(buffer)

    return path ~= "" and vim.fn.filereadable(path) == 1
end

--- Reload `buffer` from `path`, preserving unsaved user edits.
---
---@param buffer integer A Neovim buffer handle.
---@param path string The file path backing `buffer`.
---@return boolean # If the buffer was reloaded, return `true`.
function _P.reload_buffer(buffer, path)
    if not _P.is_watchable_buffer(buffer) or vim.bo[buffer].modified then
        return false
    end

    local mode = vim.api.nvim_get_mode().mode

    if mode:match("^[iR]") and vim.api.nvim_get_current_buf() == buffer then
        _P.schedule_reload(buffer)

        return false
    end

    local ok = pcall(function()
        vim.bo[buffer].autoread = true
        vim.cmd("silent! checktime " .. tostring(buffer))
    end)

    if ok and _WATCHES[buffer] then
        _WATCHES[buffer].signature = _P.get_file_signature(path)
    end

    return ok
end

--- Reload `buffer` if its file metadata has changed.
---
---@param buffer integer A Neovim buffer handle.
---@return boolean # If a reload happened, return `true`.
function M.reload_if_changed(buffer)
    local watch = _WATCHES[buffer]

    if not watch then
        return false
    end

    local signature = _P.get_file_signature(watch.path)

    if not signature then
        M.stop_buffer(buffer)

        return false
    end

    if signature == watch.signature then
        return false
    end

    return _P.reload_buffer(buffer, watch.path)
end

--- Debounce an external file-change notification for `buffer`.
---
---@param buffer integer A Neovim buffer handle.
function _P.schedule_reload(buffer)
    local watch = _WATCHES[buffer]

    if not watch then
        return
    end

    if watch.reload_timer then
        watch.reload_timer:stop()
    else
        watch.reload_timer = assert(vim.uv.new_timer())
    end

    watch.reload_timer:start(_OPTIONS.reload_debounce_ms or 100, 0, function()
        vim.schedule(function()
            M.reload_if_changed(buffer)
        end)
    end)
end

--- Stop watching a single buffer.
---
---@param buffer integer A Neovim buffer handle.
function M.stop_buffer(buffer)
    local watch = _WATCHES[buffer]

    if not watch then
        return
    end

    if watch.reload_timer then
        watch.reload_timer:stop()
        watch.reload_timer:close()
    end

    watch.poller:stop()
    watch.poller:close()
    _WATCHES[buffer] = nil
end

--- Check whether `buffer` currently has an active file watcher.
---
---@param buffer integer A Neovim buffer handle.
---@return boolean # If `buffer` is being watched, return `true`.
function M.is_watching(buffer)
    return _WATCHES[buffer] ~= nil
end

--- Start watching `buffer` if it is a listed file buffer.
---
---@param buffer integer A Neovim buffer handle.
function M.watch_buffer(buffer)
    if not _P.is_watchable_buffer(buffer) then
        M.stop_buffer(buffer)

        return
    end

    local path = vim.api.nvim_buf_get_name(buffer)
    local existing = _WATCHES[buffer]

    if existing and existing.path == path then
        existing.signature = _P.get_file_signature(path)

        return
    end

    M.stop_buffer(buffer)

    local poller = assert(vim.uv.new_fs_poll())

    _WATCHES[buffer] = {
        path = path,
        poller = poller,
        signature = _P.get_file_signature(path),
    }

    poller:start(path, _OPTIONS.poll_interval_ms or 1000, function(error, previous, current)
        if error or not previous or not current then
            return
        end

        _P.schedule_reload(buffer)
    end)
end

--- Start watchers for every currently-listed file buffer.
function M.refresh_watches()
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].buflisted then
            M.watch_buffer(buffer)
        end
    end
end

--- Stop every active file watcher.
function M.stop_all()
    for buffer, _ in pairs(_WATCHES) do
        M.stop_buffer(buffer)
    end
end

--- Remove watcher autocommands and stop every active watcher.
function M.teardown()
    M.stop_all()
    pcall(vim.api.nvim_del_augroup_by_name, _GROUP_NAME)
end

--- Install file-system watcher autocommands.
---
---@param options _my.file_system_watcher.Options?
function M.setup(options)
    _OPTIONS = vim.tbl_deep_extend("force", _OPTIONS, options or {})

    M.stop_all()

    local group = vim.api.nvim_create_augroup(_GROUP_NAME, { clear = true })

    vim.api.nvim_create_autocmd({ "BufAdd", "BufEnter", "BufFilePost" }, {
        group = group,
        callback = function(event)
            M.watch_buffer(event.buf)
        end,
        desc = "Watch listed file buffers for external changes.",
    })

    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        callback = function(event)
            local watch = _WATCHES[event.buf]

            if watch then
                watch.signature = _P.get_file_signature(watch.path)
            else
                M.watch_buffer(event.buf)
            end
        end,
        desc = "Refresh file watcher metadata after saving a buffer.",
    })

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = group,
        callback = function(event)
            M.stop_buffer(event.buf)
        end,
        desc = "Stop watching deleted or wiped buffers.",
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = M.stop_all,
        desc = "Stop all file watchers before Neovim exits.",
    })

    M.refresh_watches()
end

--- Check if Neovim is running the Busted test harness.
---
---@return boolean # If this process is running Busted, return `true`.
function _P.is_running_busted()
    local arguments = _G.arg or {}

    return tostring(arguments[0] or ""):match("busted") ~= nil
end

if not _P.is_running_busted() then
    M.setup()
end

return M
