--- Add an automatic winbar title to quickfix windows.

local M = {}

--- The 'winbar' value used by quickfix and location list windows.
---
--- The expression is re-evaluated on every redraw so the winbar always shows
--- the current quickfix title, even when the title changes later.
---
M.WINBAR_EXPRESSION = " %{v:lua.require'modules.features.quickfix_winbar'.get_quickfix_winbar_title()}"

--- Check if `window` displays a quickfix or location list buffer.
---
---@param window integer The window to inspect.
---@return boolean # If `window` shows a quickfix list, return `true`.
function M.is_quickfix_window(window)
    if not vim.api.nvim_win_is_valid(window) then
        return false
    end

    return vim.bo[vim.api.nvim_win_get_buf(window)].buftype == "quickfix"
end

--- Get the title of the quickfix or location list shown in `window`.
---
---@param window integer? The quickfix window to query. Defaults to the current window.
---@return string # The quickfix window title, if any is defined.
function M.get_quickfix_winbar_title(window)
    window = window or vim.api.nvim_get_current_win()

    local information = vim.fn.getwininfo(window)[1]
    ---@type string?
    local title

    if information and information.loclist == 1 then
        title = vim.fn.getloclist(window, { title = 0 }).title
    else
        title = vim.fn.getqflist({ title = 0 }).title
    end

    if not title or title == "" then
        return "Quickfix"
    end

    return title
end

--- Show the quickfix title in the winbar of `window`, if it is a quickfix window.
---
---@param window integer The window to modify.
function M.sync_quickfix_winbar(window)
    if not M.is_quickfix_window(window) then
        return
    end

    if vim.api.nvim_win_get_config(window).relative ~= "" then
        return
    end

    vim.wo[window].winbar = M.WINBAR_EXPRESSION
end

vim.api.nvim_create_autocmd({ "BufWinEnter", "FileType", "WinEnter" }, {
    callback = function(args)
        local window = vim.fn.bufwinid(args.buf)

        if window == -1 then
            return
        end

        M.sync_quickfix_winbar(window)
    end,
})

return M
