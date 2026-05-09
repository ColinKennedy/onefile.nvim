local M = {}
local _P = {}

_P.operatorfunc_caller = nil
_P.operatorfunc_original = nil

--- Make text-objects to work with `p`. e.g. `piw`
--- Change `p` into a text-object-aware operator.
---
---@param type_ "char" | "line" The type of operator to consider.
---
function _P.operator_paste(type_)
    local register = vim.v.register ~= "" and vim.v.register or '"'

    -- Delete the target text to the black hole register
    if type_ == "char" then
        vim.cmd('normal! `[v`]"_d')
    elseif type_ == "line" then
        vim.cmd('normal! `[V`]"_d')
    else
        vim.notify(
            string.format('Unknown mode "%s" is not supported for paste operator.', type_),
            vim.log.levels.WARN
        )

        return
    end

    vim.cmd(string.format('normal! `["%sP', register))
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
vim.keymap.set("n", "PP", "P", { noremap = true, silent = true, desc = "Paste the text." })
vim.keymap.set("n", "pp", "p", { noremap = true, silent = true, desc = "Paste the text." })
vim.keymap.set("n", "P", "<Nop>", { noremap = true, silent = true, desc = "Disable pasting with P." })

return M
