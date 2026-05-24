--- Synchronize custom session tracking when Neovim loads a Session.vim file.

local _P = {}

---@class _my.session_sync.Options
---@field shortmess string
---@field more boolean

---@type _my.session_sync.Options?
_P.session_load_options = nil

--- Quiet noisy session restore messages that otherwise trigger hit-enter prompts.
function _P.start_quiet_session_load()
    if not _P.session_load_options then
        _P.session_load_options = {
            shortmess = vim.o.shortmess,
            more = vim.o.more,
        }
    end

    vim.opt.shortmess:append("F")
    vim.o.more = false
end

--- Restore message options after session restore finishes.
function _P.stop_quiet_session_load()
    local options = _P.session_load_options

    if not options then
        return
    end

    _P.session_load_options = nil

    vim.schedule(function()
        vim.o.shortmess = options.shortmess
        vim.o.more = options.more
    end)
end

local group = vim.api.nvim_create_augroup("my.session_sync", { clear = true })

-- TODO: Remove this pcall once Neovim 0.11 is dropped
pcall(function()
    vim.api.nvim_create_autocmd("SessionLoadPre", {
        group = group,
        callback = function()
            _P.start_quiet_session_load()

            -- NOTE: We use `pcall` because this method will error if there is no session to load
            pcall(function()
                require("modules.features.core_editor_setup")._SESSION_MANAGER:sync_current_session()
            end)
        end,
    })

    vim.api.nvim_create_autocmd("SessionLoadPost", {
        group = group,
        callback = _P.stop_quiet_session_load,
    })
end)

return _P
