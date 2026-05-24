--- Add command-line mode completion mappings that behave like insert completion.

local M = {}
local _P = {}
local _WILDCHARM_KEY = "<C-z>"

--- Convert key notation to bytes that can be returned from an expr mapping.
---
---@param keys string The key notation to convert.
---@return string # The key bytes Neovim should execute.
function _P.keycode(keys)
    return vim.api.nvim_replace_termcodes(keys, true, false, true)
end

--- Ensure command-line completion can be triggered from a mapping.
---
--- Physical `<Tab>` uses `wildchar`, but mappings need `wildcharm`.
function _P.ensure_wildcharm()
    if vim.o.wildcharm == 0 then
        vim.o.wildcharm = vim.fn.char2nr(_P.keycode(_WILDCHARM_KEY))
    end
end

--- Return the command-line completion key for the requested direction.
---
--- If the wildmenu is not open yet, the first press opens completion using
--- `wildcharm`. Once completion is visible, the direction key scrolls through
--- the existing candidates.
---
---@param direction "next"|"previous" The completion direction to use once the menu is open.
---@return string # The command-line key sequence to run.
function _P.get_command_line_completion_key(direction)
    if vim.fn.wildmenumode() == 0 then
        return vim.fn.nr2char(vim.o.wildcharm)
    end

    if direction == "previous" then
        return _P.keycode("<C-p>")
    end

    return _P.keycode("<C-n>")
end

_P.ensure_wildcharm()

vim.keymap.set("c", "<C-n>", function()
    return _P.get_command_line_completion_key("next")
end, {
    desc = "Open command-line completion or select the next completion item.",
    expr = true,
})

vim.keymap.set("c", "<C-p>", function()
    return _P.get_command_line_completion_key("previous")
end, {
    desc = "Open command-line completion or select the previous completion item.",
    expr = true,
})

vim.keymap.set("c", "<C-x><C-o>", function()
    return _P.get_command_line_completion_key("next")
end, {
    desc = "Open command-line completion.",
    expr = true,
})

M._P = _P

return M
