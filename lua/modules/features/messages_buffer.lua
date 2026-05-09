local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
    --- Write `:messages` to a buffer
    vim.api.nvim_create_user_command("Messages", function()
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_call(bufnr, function()
            vim.cmd([[put= execute('messages')]])
        end)
        vim.bo[bufnr].modifiable = false
        vim.cmd.split()
        local winnr = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(winnr, bufnr)
    end, { desc = "Dump all (Neo)vim messages to a read-only buffer", nargs = 0 })
end)
