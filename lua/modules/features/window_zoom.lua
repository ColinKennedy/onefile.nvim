--- Toggle a full-window zoom view without destroying the original layout.

local M = {}

---@class _my.window_zoom.State
---@field source_tab integer The tabpage that owned the original window layout.
---@field source_window integer The source window to return to when zooming out.
---@field source_buffer integer The buffer shown by the source window when zooming in.
---@field zoom_tab integer The temporary tabpage that contains the zoomed window.
---@field showtabline integer The original global tabline visibility value.

---@type table<integer, _my.window_zoom.State>
local _STATE_BY_ZOOM_TAB = {}

local _RESTORE_SOURCE_TAB_ERROR = "Cannot restore zoomed window: original tab no longer exists."
local _RESTORE_SOURCE_WINDOW_ERROR = "Cannot restore zoomed window: original window no longer exists."

--- Return the non-floating windows in `tabpage`.
---
---@param tabpage integer The tabpage handle to inspect.
---@return integer[] # The non-floating windows contained by the tabpage.
---
local function _get_normal_windows(tabpage)
    ---@type integer[]
    local windows = {}

    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        if vim.api.nvim_win_get_config(window).relative == "" then
            table.insert(windows, window)
        end
    end

    return windows
end

--- Notify that a zoomed window cannot be restored.
---
---@param message string The restore failure message to show.
local function _notify_restore_error(message)
    vim.notify(message, vim.log.levels.ERROR)
end

--- Check whether `tabpage` is currently a tracked zoom tab.
---
---@param tabpage? integer The tabpage handle to inspect. Defaults to the current tabpage.
---@return boolean # If the tabpage is a tracked zoom tab, return `true`.
---
function M.is_zoomed_tab(tabpage)
    local tab = tabpage or vim.api.nvim_get_current_tabpage()

    return _STATE_BY_ZOOM_TAB[tab] ~= nil
end

--- Get the zoom state for a tabpage.
---
---@param tabpage? integer The tabpage handle to inspect. Defaults to the current tabpage.
---@return _my.window_zoom.State? # The zoom state, if the tabpage is zoomed.
---
function M.get_state(tabpage)
    local tab = tabpage or vim.api.nvim_get_current_tabpage()

    return _STATE_BY_ZOOM_TAB[tab]
end

--- Zoom the current window into a temporary tabpage.
function M.zoom_current_window()
    local source_tab = vim.api.nvim_get_current_tabpage()
    local source_window = vim.api.nvim_get_current_win()
    local source_buffer = vim.api.nvim_win_get_buf(source_window)
    local showtabline = vim.o.showtabline

    if #_get_normal_windows(source_tab) <= 1 then
        return
    end

    vim.cmd("tab split")

    local zoom_tab = vim.api.nvim_get_current_tabpage()
    _STATE_BY_ZOOM_TAB[zoom_tab] = {
        source_tab = source_tab,
        source_window = source_window,
        source_buffer = source_buffer,
        zoom_tab = zoom_tab,
        showtabline = showtabline,
    }
    vim.o.showtabline = 0
end

--- Restore the original tab/window layout for the current zoom tab.
---
---@return boolean # If the zoom tab was restored, return `true`.
---
function M.restore_current_zoom()
    local zoom_tab = vim.api.nvim_get_current_tabpage()
    local state = _STATE_BY_ZOOM_TAB[zoom_tab]

    if not state then
        return false
    end

    if not vim.api.nvim_tabpage_is_valid(state.source_tab) then
        _notify_restore_error(_RESTORE_SOURCE_TAB_ERROR)
        return false
    end

    if not vim.api.nvim_win_is_valid(state.source_window) then
        _notify_restore_error(_RESTORE_SOURCE_WINDOW_ERROR)
        return false
    end

    _STATE_BY_ZOOM_TAB[zoom_tab] = nil
    vim.o.showtabline = state.showtabline

    local zoom_tab_number = vim.api.nvim_tabpage_get_number(zoom_tab)
    vim.api.nvim_set_current_tabpage(state.source_tab)
    vim.api.nvim_set_current_win(state.source_window)
    vim.cmd("silent! tabclose! " .. tostring(zoom_tab_number))

    return true
end

--- Toggle the current window between normal layout and a zoom tab.
function M.toggle()
    if M.is_zoomed_tab() then
        M.restore_current_zoom()
        return
    end

    M.zoom_current_window()
end

--- Restore settings for any zoom tab that has already been closed.
function M.clean_invalid_zoom_tabs()
    for tabpage, state in pairs(_STATE_BY_ZOOM_TAB) do
        if not vim.api.nvim_tabpage_is_valid(tabpage) then
            vim.o.showtabline = state.showtabline
            _STATE_BY_ZOOM_TAB[tabpage] = nil
        end
    end
end

--- Clear zoom state for tests.
function M.reset_for_tests()
    _STATE_BY_ZOOM_TAB = {}
end

vim.api.nvim_create_autocmd("TabClosed", {
    callback = M.clean_invalid_zoom_tabs,
    desc = "Clean up closed zoom tabs.",
})

vim.keymap.set("n", "<C-w>o", M.toggle, {
    desc = "Toggle-zoom the current window.",
    silent = true,
})

return M
