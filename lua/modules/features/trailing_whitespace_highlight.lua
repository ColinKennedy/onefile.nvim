local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
--- Visualize trailing whitespace
vim.api.nvim_set_hl(0, "TrailingWhitespace", { link = "Error" })
-- Apply the highlight using a match pattern
vim.cmd([[match TrailingWhitespace /\s\+$/]])
end)
