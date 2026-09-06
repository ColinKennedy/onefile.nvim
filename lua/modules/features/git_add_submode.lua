--- A fake "submode" that turns `y` / `n` / `a` into a native `git add -p` flow.
---
--- Reuses the repo-wide hunk cache that `git_hunk_navigation.lua` already
--- builds for `]g` / `[g` so the submode does not maintain its own hunk list.

local M = {}
local _P = {}

local _AUGROUP = vim.api.nvim_create_augroup("my.git_add_submode", { clear = true })

--- If `true`, the submode keymaps, statusline color, and legend window are active.
---
---@type boolean
local _ACTIVE = false

--- The Normal-mode keys the submode temporarily takes over.
local _SUBMODE_KEYS = { "y", "n", "N", "a", "v", "q", "<Esc>" }

--- The prior mapping for each submode key, saved before overriding it.
---
--- `false` means the key had no prior mapping (fall back to Neovim's builtin
--- behavior on restore instead of calling `mapset`).
---
---@type table<string, table|false>
local _SAVED_KEYMAPS = {}

---@type integer? The floating legend window, while active.
local _LEGEND_WINDOW = nil
---@type integer? The floating legend scratch buffer, while active.
local _LEGEND_BUFFER = nil

-- NOTE: Every line must stay under 10 characters so the legend window stays tiny.
local _LEGEND_LINES = { "y stage", "n skip", "N prev", "a all", "v diff", "q exit", "esc exit" }

--- Save the current Normal-mode mapping for `key`, then replace it with `callback`.
---
---@param key string The key to override, e.g. `"y"`.
---@param callback fun(): nil The function to run when `key` is pressed.
---@param desc string The keymap description.
local function _override_key(key, callback, desc)
    local existing = vim.fn.maparg(key, "n", false, true)
    _SAVED_KEYMAPS[key] = next(existing) ~= nil and existing or false

    vim.keymap.set("n", key, callback, { desc = desc })
end

--- Restore the Normal-mode mapping for `key` that `_override_key` saved.
---
---@param key string The key to restore.
local function _restore_key(key)
    local saved = _SAVED_KEYMAPS[key]
    _SAVED_KEYMAPS[key] = nil

    if saved then
        vim.fn.mapset(saved.mode or "n", false, saved)

        return
    end

    pcall(vim.keymap.del, "n", key)
end

--- Get the display width the legend window needs for its longest line.
---
---@return integer # The widest legend line's display width.
local function _get_legend_width()
    local width = 0

    for _, line in ipairs(_LEGEND_LINES) do
        width = math.max(width, vim.fn.strdisplaywidth(line))
    end

    return width
end

--- Get the floating window config that pins the legend to the top-right corner.
---
---@return vim.api.keyset.win_config # The window position config.
local function _get_legend_position()
    return { relative = "editor", anchor = "NE", row = 0, col = vim.o.columns }
end

--- Open the top-right legend window, if it is not already open.
function _P.open_legend_window()
    if _LEGEND_WINDOW and vim.api.nvim_win_is_valid(_LEGEND_WINDOW) then
        return
    end

    _LEGEND_BUFFER = vim.api.nvim_create_buf(false, true)
    vim.bo[_LEGEND_BUFFER].buftype = "nofile"
    vim.bo[_LEGEND_BUFFER].bufhidden = "wipe"
    vim.bo[_LEGEND_BUFFER].swapfile = false
    vim.api.nvim_buf_set_lines(_LEGEND_BUFFER, 0, -1, false, _LEGEND_LINES)
    vim.bo[_LEGEND_BUFFER].modifiable = false

    local config = _get_legend_position()
    config.width = _get_legend_width()
    config.height = #_LEGEND_LINES
    config.style = "minimal"
    config.border = "single"
    config.title = "Git Mode"
    config.title_pos = "center"
    config.focusable = false
    config.noautocmd = true

    _LEGEND_WINDOW = vim.api.nvim_open_win(_LEGEND_BUFFER, false, config)
end

--- Move the legend window back into the top-right corner.
---
--- Called after `VimResized` so the window follows the terminal size.
function _P.reposition_legend_window()
    if not (_LEGEND_WINDOW and vim.api.nvim_win_is_valid(_LEGEND_WINDOW)) then
        return
    end

    vim.api.nvim_win_set_config(_LEGEND_WINDOW, _get_legend_position())
end

--- Close the legend window and forget its buffer.
function _P.close_legend_window()
    if _LEGEND_WINDOW and vim.api.nvim_win_is_valid(_LEGEND_WINDOW) then
        vim.api.nvim_win_close(_LEGEND_WINDOW, true)
    end

    _LEGEND_WINDOW = nil
    _LEGEND_BUFFER = nil
end

--- Reload the active repository's cached hunks.
---
---@param callback fun(state: _my.git_hunk_navigation.RepositoryState?): nil
---    Callback with the refreshed repository state, or `nil` if the reload
---    failed or no hunks remain.
function _P.reload(callback)
    local git_hunk_navigation = require("modules.features.git_hunk_navigation")
    local repository_state = git_hunk_navigation._get_repository_state()
    local arguments = repository_state and repository_state.arguments or {}

    git_hunk_navigation._load(arguments, function(success)
        local new_state = git_hunk_navigation._get_repository_state()

        if not success or not new_state or #new_state.entries == 0 then
            callback(nil)

            return
        end

        callback(new_state)
    end)
end

--- Turn the Git add submode on: override keymaps, show the legend, and color the statusline.
function _P.activate()
    if _ACTIVE then
        return
    end

    _ACTIVE = true

    _override_key("y", _P.on_y, "Stage the current Git hunk.")
    _override_key("n", _P.on_n, "Skip to the next Git hunk.")
    _override_key("N", _P.on_shift_n, "Jump to the previous Git hunk.")
    _override_key("a", _P.on_a, "Stage every Git hunk in the current file.")
    _override_key("v", _P.on_v, "Toggle the Git diff view.")
    _override_key("q", _P.on_exit, "Exit the Git add submode.")
    _override_key("<Esc>", _P.on_exit, "Exit the Git add submode.")

    _P.open_legend_window()
    require("modules.features.statusline").set_git_submode_active(true)
end

--- Turn the Git add submode off: restore keymaps, hide the legend, and reset the statusline.
---
---@param message string? An optional message to show after exiting.
function _P.deactivate(message)
    if not _ACTIVE then
        return
    end

    _ACTIVE = false

    for _, key in ipairs(_SUBMODE_KEYS) do
        _restore_key(key)
    end

    _P.close_legend_window()
    require("modules.features.statusline").set_git_submode_active(false)

    if message then
        vim.notify(message, vim.log.levels.INFO)
    end
end

--- Update the hunk cache locally, then either finish or jump to the next hunk.
---
---@param buffer integer The buffer whose hunks were staged.
---@param line integer? The staged hunk line, or `nil` when the whole file was staged.
function _P.advance_or_finish(buffer, line)
    local git_hunk_navigation = require("modules.features.git_hunk_navigation")
    local remaining = git_hunk_navigation.remove_cached_hunks_for_buffer(buffer, line)
    local repository_state = git_hunk_navigation._get_repository_state()

    --- Finish after falling back to a full reload when the local cache did not match.
    ---
    ---@param state _my.git_hunk_navigation.RepositoryState?
    local function _finish(state)
        if not state then
            _P.deactivate("Git add is done.")

            return
        end

        vim.cmd.GitDiffNext()
    end

    if remaining == nil or (repository_state and repository_state.stale) then
        _P.reload(_finish)

        return
    end

    _finish(remaining > 0 and repository_state or nil)
end

--- Stage the hunk under the cursor, then advance.
function _P.on_y()
    local buffer = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_win_get_cursor(0)[1]

    require("modules.features.git_hunks").apply_closest_hunk("stage", function(success)
        if success then
            _P.advance_or_finish(buffer, line)
        end
    end, true)
end

--- Skip the current hunk and advance, wrapping at the end of the list.
function _P.on_n()
    vim.cmd.GitDiffNext()
end

--- Jump back to the previous hunk, wrapping at the start of the list.
function _P.on_shift_n()
    vim.cmd.GitDiffPrevious()
end

--- Stage every hunk in the current file, then advance to the next file.
function _P.on_a()
    local buffer = vim.api.nvim_get_current_buf()

    require("modules.features.git_hunks").apply_current_file("stage", function(success)
        if success then
            _P.advance_or_finish(buffer, nil)
        end
    end, true)
end

--- Toggle the Git diff view for the current window.
function _P.on_v()
    vim.cmd.ToggleGitDiffView()
end

--- Leave the Git add submode without staging anything.
function _P.on_exit()
    _P.deactivate()
end

--- Check if the Git add submode is currently active.
---
---@return boolean # If `true`, the submode is active.
function M.is_active()
    return _ACTIVE
end

--- Start the Git add submode at the first cached Git hunk.
function M.start()
    if _ACTIVE then
        return
    end

    _P.reload(function(state)
        if not state then
            return
        end

        _P.activate()
        vim.cmd.GitDiffNext()
    end)
end

vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
        if _ACTIVE then
            _P.reposition_legend_window()
        end
    end,
    desc = "Reposition the Git add submode legend window after a terminal resize.",
    group = _AUGROUP,
})

return M
