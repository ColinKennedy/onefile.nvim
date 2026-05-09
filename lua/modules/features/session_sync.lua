--- Synchronize custom session tracking when Neovim loads a Session.vim file.

vim.api.nvim_create_autocmd("SessionLoadPre", {
    group = vim.api.nvim_create_augroup("my.session_sync", { clear = true }),
    callback = function()
        -- NOTE: We use `pcall` because this method will error if there is no session to load
        pcall(function()
            require("modules.features.core_editor_setup")._SESSION_MANAGER:sync_current_session()
        end)
    end,
})
