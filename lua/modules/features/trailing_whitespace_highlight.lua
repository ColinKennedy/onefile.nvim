--- Highlight trailing whitespace in visible buffers.

vim.api.nvim_set_hl(0, "TrailingWhitespace", { link = "Error" })
-- Apply the highlight using a match pattern
vim.cmd([[match TrailingWhitespace /\s\+$/]])
