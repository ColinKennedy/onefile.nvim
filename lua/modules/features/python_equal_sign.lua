local _P = {}
local core_helpers = require("modules.utilities.core_helpers")

--- Python equal-sign insertion support
local _BUILTINS = {
    ["False"] = true,
    ["None"] = true,
    ["True"] = true,
    ["and"] = true,
    ["as"] = true,
    ["assert"] = true,
    ["break"] = true,
    ["class"] = true,
    ["continue"] = true,
    ["def"] = true,
    ["del"] = true,
    ["elif"] = true,
    ["else"] = true,
    ["except"] = true,
    ["finally"] = true,
    ["for"] = true,
    ["from"] = true,
    ["global"] = true,
    ["if"] = true,
    ["import"] = true,
    ["in"] = true,
    ["is"] = true,
    ["lambda"] = true,
    ["nonlocal"] = true,
    ["not"] = true,
    ["or"] = true,
    ["pass"] = true,
    ["raise"] = true,
    ["return"] = true,
    ["try"] = true,
    ["while"] = true,
    ["with"] = true,
    ["yield"] = true,
}

--- Check if this "last `character` in the Python source code line" can have a = sign appended to it.
---
---@param character string Some text to check.
---@return boolean # If `true` then `character` is allowed assignments with = sign.
---
function _P.has_expected_last_character(character)
    if
        character:match("[%w_]") -- Reference: https://stackoverflow.com/a/12118024/3626104
    then
        return true
    end

    if character:match("]") then
        return true
    end

    if character:match("}") then
        return true
    end

    return false
end

--- Check if `text` is a python source code line that supports a = sign.
---
---@param text string Some Python source code to check.
---@return boolean # If `text` cannot assign with =, return `false`.
---
function _P.is_assignable(text)
    local _, count = string.gsub(text, "%s+", "")

    if count ~= 0 then
        return false
    end

    if not _P.has_expected_last_character(text:sub(-1)) then
        return false
    end

    if _P.is_builtin_keyword(text:gsub("%s+", "")) then
        -- Strip whitespace of `text` and check if it's a built-in keyword
        return false
    end

    if _P.is_blacklisted_context() then
        return false
    end

    return true
end

---@return boolean # Check if the current cursor's okay run the "compute = sign".
function _P.is_blacklisted_context()
    return vim.treesitter.get_node({ buffer = 0 }):type() == "string_content"
end

--- Check if `text` is a Python keyword.
---
---@param text string Some Python source to test.
---@return boolean # If `text` is owned by Python, return `true`.
---
function _P.is_builtin_keyword(text)
    return _BUILTINS[text] ~= nil
end

--- Remove unneeded syntax markers (to compute the equal sign).
---
---@param text string The original Python source-code.
---@return string # The stripped text.
---
local function _strip_braces_characters(text)
    text = text:gsub("%(.+%)", "()")
    text = text:gsub("%[.+%]", "[]")

    return text
end

---@return string # Append an `=` sign to the current line if it is needed.
function _P.add_equal_sign_if_needed_python()
    local _, cursor_row, cursor_column, _ = unpack(vim.fn.getpos("."))
    local current_line = vim.fn.getline(cursor_row)

    if cursor_column <= #current_line then
        -- If the cursor isn't at the end of the line, stop. There's no
        -- container data-type in Python where `=` are expected so this is
        -- always supposed to be a space.
        --
        return " "
    end

    local current_line_up_until_cursor = current_line:sub(1, cursor_column)
    local stripped = _strip_braces_characters(current_line_up_until_cursor)

    if not _P.is_assignable(core_helpers.lstrip(stripped)) then
        return " "
    end

    return " = "
end

if core_helpers.has_treesitter_parser("python") then
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "python",
        callback = function()
            vim.keymap.set("i", "<Space>", _P.add_equal_sign_if_needed_python, {
                buffer = true,
                desc = "Add = signs when needed.",
                expr = true,
            })
        end,
    })
end
