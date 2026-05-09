local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
    --- LSP log command

    vim.api.nvim_create_user_command("LspLog", function()
        vim.cmd("edit " .. vim.lsp.log.get_filename())
    end, { desc = "Open Neovim's LSP log file.", nargs = 0 })
end)
