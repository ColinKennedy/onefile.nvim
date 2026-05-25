--- Make `p` behave as a text-object operator for replacing motions and text objects.

local M = {}
local _P = {}

_P.operatorfunc_caller = nil
_P.operatorfunc_original = nil

--- Get the lines from the register that should replace a text object.
---
---@param register string The register name to read.
---@return string[] # The register contents as replacement lines.
function _P.get_register_lines(register)
    local lines = vim.fn.getreg(register, 1, true)

    if vim.tbl_isempty(lines) then
        return { "" }
    end

    return lines
end

--- Remember the region replaced by a characterwise paste operation.
---
---@param start_row integer The 1-or-more start row.
---@param start_column integer The 0-or-more start column.
---@param replacement string[] The replacement text.
function _P.set_last_put_marks(start_row, start_column, replacement)
    local end_row = start_row + #replacement - 1
    local end_column = #replacement[#replacement]

    if #replacement == 1 then
        end_column = start_column + end_column
    end

    vim.fn.setpos("'[", { 0, start_row, start_column + 1, 0 })
    vim.fn.setpos("']", { 0, end_row, math.max(end_column, 1), 0 })
end

--- Replace a characterwise operator range with register text.
---
---@param register string The register name to paste from.
function _P.replace_characterwise_range(register)
    local start_position = vim.fn.getpos("'[")
    local end_position = vim.fn.getpos("']")
    local start_row = start_position[2]
    local start_column = start_position[3] - 1
    local end_row = end_position[2]
    local end_column = end_position[3]
    local replacement = _P.get_register_lines(register)

    vim.api.nvim_buf_set_text(0, start_row - 1, start_column, end_row - 1, end_column, replacement)
    _P.set_last_put_marks(start_row, start_column, replacement)
end

--- Change `p` into a text-object-aware operator.
---
---@param type_ "char" | "line" The type of operator to consider.
---
function _P.operator_paste(type_)
    local register = vim.v.register ~= "" and vim.v.register or '"'

    -- Delete the target text to the black hole register
    if type_ == "char" then
        _P.replace_characterwise_range(register)
    elseif type_ == "line" then
        vim.cmd('normal! `[V`]"_d')
        vim.cmd(string.format('normal! `["%sP', register))
    else
        vim.notify(string.format('Unknown mode "%s" is not supported for paste operator.', type_), vim.log.levels.WARN)

        return
    end
end

--- Change `p` into a text-object-aware operator and revert later.
---
---@param caller fun(type_: string): nil Some custom operatorfunc behavior.
---
function _P.wrap_operatorfunc(caller)
    return function()
        _P.operatorfunc_caller = caller
        _P.operatorfunc_original = vim.go.operatorfunc
        vim.go.operatorfunc = "v:lua.require'modules.features.put_text_objects'.temporary_operator_paste"

        return "g@"
    end
end

--- Call operatorfunc with `type_` and then cleanup everything.
---
--- We clean up after ourselves so there are no side-effects from
--- the operatorfunc work we have been doing up until now.
---
---@param type_ "char" | "line"
---    An indicator from Vim which operator mode we're in.
---    See `:help Operator-pending-mode` for details. e.g. `"char"`.
---
function M.temporary_operator_paste(type_)
    local caller = _P.operatorfunc_caller

    if caller then
        caller(type_)
    end

    vim.go.operatorfunc = _P.operatorfunc_original or ""
    _P.operatorfunc_caller = nil
    _P.operatorfunc_original = nil
end

vim.keymap.set(
    "n",
    "p",
    _P.wrap_operatorfunc(_P.operator_paste),
    { silent = true, desc = "[p]ut text and replace the [i]nner [w]ord with that text.", expr = true }
)

--- Put text with Vim's native command and remember the exact region for `gp`.
---
---@param command "p" | "P" The native put command to execute.
local function _native_put(command)
    local register = vim.v.register ~= "" and vim.v.register or '"'
    local keys = register == '"' and command or string.format('"%s%s', register, command)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local context = {
        command = command,
        cursor_line = cursor[1],
        cursor_column = cursor[2],
        line_count = vim.api.nvim_buf_line_count(0),
    }

    vim.cmd.normal({ args = { keys }, bang = true })
    require("modules.features.directional_put_mappings").remember_native_put(register, context)
end

vim.keymap.set("n", "PP", function()
    _native_put("P")
end, { silent = true, desc = "Paste the text above." })
vim.keymap.set("n", "pp", function()
    _native_put("p")
end, { silent = true, desc = "Paste the text below." })
vim.keymap.set("n", "P", "<Nop>", { noremap = true, silent = true, desc = "Disable pasting with P." })

return M
