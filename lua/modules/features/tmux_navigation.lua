--- Move between Neovim windows and adjacent tmux panes with the same directional keys.

--- Move in `direction` if 1. on a Neovim edge tab 2. there is a nearby tmux pane.
---
---@param direction "h" | "j" | "k" | "l"
---    The Neovim or tmux pane to move in.
---
local function _move_to_tmux_pane_if_needed(direction)
    local tmux_directions = { h = "L", j = "D", k = "U", l = "R" }

    local current_window = vim.api.nvim_get_current_win()
    vim.cmd("wincmd " .. direction)

    if vim.api.nvim_get_current_win() ~= current_window then
        return
    end

    vim.fn.system(string.format("tmux select-pane -%s", tmux_directions[direction]))
end

local _desc = function(opts, direction)
    return vim.tbl_deep_extend(
        "force",
        opts,
        { desc = string.format('Move the cursor to the "%s" window.', direction) }
    )
end
local desc = function(direction)
    _desc({ noremap = true, silent = true }, direction)
end

vim.keymap.set("n", "<C-h>", function()
    _move_to_tmux_pane_if_needed("h")
end, desc("left"))
vim.keymap.set("n", "<C-j>", function()
    _move_to_tmux_pane_if_needed("j")
end, desc("down"))
vim.keymap.set("n", "<C-k>", function()
    _move_to_tmux_pane_if_needed("k")
end, desc("up"))
vim.keymap.set("n", "<C-l>", function()
    _move_to_tmux_pane_if_needed("l")
end, desc("right"))
