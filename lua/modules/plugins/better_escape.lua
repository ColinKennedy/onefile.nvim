--- Escape INSERT and TERMINAL mode with a delayed `jk` chord.

local M = {}

local _AUGROUP = vim.api.nvim_create_augroup("my.better_escape", { clear = true })
local _ON_KEY_NAMESPACE = vim.api.nvim_create_namespace("my.better_escape")
local _TIMER = assert(vim.uv.new_timer())
local _TIMEOUT = vim.o.timeoutlen

---@class _my.better_escape.State
---@field first_key string? The first key in a pending escape chord.
---@field mode "i" | "t"? The mode where the first key was typed.
---@field buffer integer? The buffer where the chord started.
---@field modified boolean? Whether the buffer was modified before the first key.
---@field waiting boolean Whether a first key is currently waiting for the second key.

---@type _my.better_escape.State
local _STATE = {
    buffer = nil,
    first_key = nil,
    mode = nil,
    modified = nil,
    waiting = false,
}

local _HAS_RECORDED_KEY = false

--- Clear the currently pending key chord.
local function _clear_recorded_key()
    _STATE.buffer = nil
    _STATE.first_key = nil
    _STATE.mode = nil
    _STATE.modified = nil
    _STATE.waiting = false
end

--- Stop and restart the pending-key timeout.
local function _restart_timer()
    if _TIMER:is_active() then
        _TIMER:stop()
    end

    _TIMER:start(_TIMEOUT, 0, function()
        vim.schedule(_clear_recorded_key)
    end)
end

--- Record the first key in a possible escape chord.
---
---@param mode "i" | "t" The mode where the key was typed.
---@param key string The typed key.
---@return string # The key to insert/send normally.
local function _record_first_key(mode, key)
    _STATE.buffer = vim.api.nvim_get_current_buf()
    _STATE.first_key = key
    _STATE.mode = mode
    _STATE.modified = vim.bo.modified
    _STATE.waiting = true
    _HAS_RECORDED_KEY = true
    _restart_timer()

    return key
end

--- Get the key sequence that undoes the first key in `mode`.
---
---@param mode "i" | "t" The mode where the chord is completed.
---@return string # The undo key sequence.
local function _get_undo_keys(mode)
    if mode == "i" and _STATE.modified == false then
        return "<BS><Cmd>setlocal nomodified<CR>"
    end

    return "<BS>"
end

--- Get the key sequence that leaves `mode`.
---
---@param mode "i" | "t" The mode where the chord is completed.
---@return string # The escape key sequence.
local function _get_escape_keys(mode)
    if mode == "t" then
        return "<C-\\><C-n>"
    end

    return "<Esc>"
end

--- Check if `key` completes the configured escape chord.
---
---@param mode "i" | "t" The mode where the key was typed.
---@param key string The typed key.
---@return boolean # If `true`, the key completes the chord.
local function _is_escape_chord(mode, key)
    return _STATE.waiting and _STATE.mode == mode and _STATE.first_key == "j" and key == "k"
end

--- Handle the second key in a possible escape chord.
---
---@param mode "i" | "t" The mode where the key was typed.
---@param key string The typed key.
---@return string # The keys to feed from the expression mapping.
local function _handle_second_key(mode, key)
    if _is_escape_chord(mode, key) then
        local keys = _get_undo_keys(mode) .. _get_escape_keys(mode)

        _clear_recorded_key()

        return keys
    end

    return _record_first_key(mode, key)
end

--- Install one mode's better-escape mappings.
---
---@param mode "i" | "t" The mode that receives the mappings.
local function _map_mode(mode)
    local options = { expr = true, desc = "Escape to NORMAL mode with a delayed jk chord." }

    vim.keymap.set(mode, "j", function()
        return _record_first_key(mode, "j")
    end, options)

    vim.keymap.set(mode, "k", function()
        return _handle_second_key(mode, "k")
    end, options)
end

--- Clear stale pending chords when unrelated keys are typed.
local function _watch_keys()
    vim.on_key(function(key, typed)
        local actual = typed

        if actual == nil or actual == "" then
            actual = key
        end

        if actual == "" then
            return
        end

        if not _HAS_RECORDED_KEY then
            _clear_recorded_key()

            return
        end

        _HAS_RECORDED_KEY = false
    end, _ON_KEY_NAMESPACE)
end

--- Install the better-escape mappings.
function M.setup()
    pcall(vim.keymap.del, "i", "jk")
    pcall(vim.keymap.del, "t", "jk")
    _map_mode("i")
    _map_mode("t")
    _watch_keys()
end

vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
        if _TIMER:is_active() then
            _TIMER:stop()
        end

        _TIMER:close()
    end,
    desc = "Close the better-escape timer.",
    group = _AUGROUP,
})

M.setup()

return M
