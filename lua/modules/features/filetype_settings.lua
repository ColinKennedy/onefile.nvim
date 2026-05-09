--- Apply indentation and spellcheck settings for specific filetypes.

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "lua", "python" },
    callback = function()
        vim.bo.shiftwidth = 4
        vim.bo.tabstop = 4
        vim.bo.expandtab = true
    end,
})

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "qf" },
    callback = function()
        vim.wo.winfixbuf = true
    end,
})
