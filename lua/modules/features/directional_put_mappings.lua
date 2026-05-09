--- Add [p ]p >p <p >P <P mappings.
--- Paste to the line above or below, and move text left or right.
---
---@param direction "above" | "below"
---    Put text above or below the current line.
---@param indent string?
---    If not provided, the pasted text is on the same line as the current line.
---    Otherwise >> indents right and << indents left.
---
local function _paste_line(direction, indent)
    local row = vim.fn.line(".")

    if direction == "above" then
        row = row - 1
    end

    local register = vim.v.register ~= "" and vim.v.register or '"'
    local line = vim.fn.getreg(register)
    line = require("modules.utilities.core_helpers").rstrip(line)
    local lines = vim.split(line, "\n")
    vim.api.nvim_buf_set_lines(0, row, row, true, lines)
    local start = row + 1
    local end_ = start + #lines - 1

    vim.cmd(string.format("%s,%snormal! ==", start, end_))

    if indent then
        vim.cmd(string.format("%s,%snormal! %s", start, end_, indent))
    end
end

vim.keymap.set("n", "[p", function()
    _paste_line("above")
end, { desc = "Paste line above" })
vim.keymap.set("n", "]p", function()
    _paste_line("below")
end, { desc = "Paste line below" })
vim.keymap.set("n", ">p", function()
    _paste_line("below", ">>")
end, { desc = "Paste below + indent" })
vim.keymap.set("n", "<p", function()
    _paste_line("below", "<<")
end, { desc = "Paste below + dedent" })
vim.keymap.set("n", ">P", function()
    _paste_line("above", ">>")
end, { desc = "Paste above + indent" })
vim.keymap.set("n", "<P", function()
    _paste_line("above", "<<")
end, { desc = "Paste above + dedent" })
