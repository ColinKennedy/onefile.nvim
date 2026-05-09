--- Define insert-mode auto-pair mappings for brackets, quotes, and backspace cleanup.

--- Whenever `character` is typed, check if we want to move the cursor right instead.
---
--- If `character` like `")"` is already in the buffer and is the cursor is
--- immediately to the left of it, typing another `")"` means "don't
--- actually insert a second `")"`, just move me outside of the `"()"` pair.
---
---@param character string An ending character. e.g. `")"`.
---
local function _define_close_mapping(character)
    vim.keymap.set("i", character, function()
        local line = vim.api.nvim_get_current_line()
        local column = vim.api.nvim_win_get_cursor(0)[2]
        local next_character = line:sub(column + 1, column + 1)

        if next_character == character then
            return "<Right>"
        end

        return character
    end, { expr = true, desc = "Decide whether to type a closing character or move to the right, instead." })
end

--- Whenever `open` is typed, also type `close` and place the cursor between them.
---
---@param open string A starting character. e.g. `"("`.
---@param close string An ending character. e.g. `")"`.
---
local function _define_open_mapping(open, close)
    local reverse_characters = string.rep("<Left>", #close)

    vim.keymap.set("i", open, function()
        return open .. close .. reverse_characters
    end, { expr = true, desc = "Create an open + close pair and move the cursor to the middle." })
end

local _PAIRS = {
    ["("] = ")",
    ["["] = "]",
    ["{"] = "}",

    -- TODO: These symmetric-pair characters don't work as mappings yet. Fix them later.
    ["'"] = "'",
    ['"'] = '"',
    ["`"] = "`",
}

local _CLOSING_PAIRS = {
    ")",
    "]",
    "}",
    "'",
    '"',
    "`",
}

for open, close in pairs(_PAIRS) do
    _define_open_mapping(open, close)
end

for _, character in ipairs(_CLOSING_PAIRS) do
    _define_close_mapping(character)
end

vim.keymap.set("i", "<BS>", function()
    local line = vim.api.nvim_get_current_line()
    local column = vim.api.nvim_win_get_cursor(0)[2]
    local previous_character = line:sub(column, column)
    local next_character = line:sub(column + 1, column + 1)

    for open, close in pairs(_PAIRS) do
        if previous_character == open and next_character == close then
            return "<Del><BS>"
        end
    end

    return "<BS>"
end, { expr = true, desc = "Delete the open and close pair characters at once." })
