--- This module fixes a common issue when pasting with `:+p` - on Windows, when pasting to WSL, these annoying ^M line-ending characters get inserted.
---
--- But with this module, there's no issue anymore, the characters get
--- auto-stripped-out
---

local function _remove_literal_carriage_returns()
    if not vim.bo.modifiable or vim.bo.readonly then
        return
    end

    local view = vim.fn.winsaveview()

    pcall(function()
        vim.cmd([[silent! keepjumps keeppatterns %s/\%x0d//ge]])
    end)
    vim.fn.winrestview(view)
end

-- Prefer WSL-friendly LF line endings while still detecting CRLF files on read.
vim.opt.fileformat = "unix"
vim.opt.fileformats = { "unix", "dos" }

vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedP" }, {
    group = vim.api.nvim_create_augroup("my.line_endings", { clear = true }),
    callback = _remove_literal_carriage_returns,
})
