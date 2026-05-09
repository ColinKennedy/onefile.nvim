local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
    --- Filetype-specific details
    vim.api.nvim_create_autocmd("FileType", {
        pattern = { "lua", "python" },
        callback = function()
            vim.bo.shiftwidth = 4
            vim.bo.tabstop = 4
            vim.bo.expandtab = true
        end,
    })
end)
