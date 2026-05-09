--- Toggle bracketed code between one-line and multiline argument layouts.

local M = {}

---@class _my.code_argument_toggle.Position
---@field line integer The 1-or-more line number.
---@field column integer The 0-or-more column.

---@class _my.code_argument_toggle.Pair
---@field open _my.code_argument_toggle.Position The opening delimiter.
---@field close _my.code_argument_toggle.Position The closing delimiter.
---@field open_character string The opening delimiter text.
---@field close_character string The closing delimiter text.

local _OPEN_TO_CLOSE = {
    ["("] = ")",
    ["{"] = "}",
    ["["] = "]",
}

local _CLOSE_TO_OPEN = {
    [")"] = "(",
    ["}"] = "{",
    ["]"] = "[",
}

--- Get all buffer lines.
---
---@param buffer integer The buffer to inspect.
---@return string[] # The buffer lines.
local function _get_lines(buffer)
    return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

--- Get one line from `lines`.
---
---@param lines string[] The source lines.
---@param line_number integer The 1-or-more line number.
---@return string # The line text.
local function _get_line(lines, line_number)
    return lines[line_number] or ""
end

--- Compare two positions.
---
---@param left _my.code_argument_toggle.Position The left position.
---@param right _my.code_argument_toggle.Position The right position.
---@return integer # -1 if left is before right, 0 if equal, 1 if after.
local function _compare_positions(left, right)
    if left.line < right.line then
        return -1
    end

    if left.line > right.line then
        return 1
    end

    if left.column < right.column then
        return -1
    end

    if left.column > right.column then
        return 1
    end

    return 0
end

--- Find the innermost delimiter pair that contains `cursor`.
---
---@param lines string[] The source lines.
---@param cursor _my.code_argument_toggle.Position The cursor position.
---@return _my.code_argument_toggle.Pair? # The containing delimiter pair, if any.
local function _find_pair(lines, cursor)
    ---@type any[]
    local stack = {}

    for line_number, line in ipairs(lines) do
        for column = 1, #line do
            local character = line:sub(column, column)
            local position = { line = line_number, column = column - 1 }

            if _OPEN_TO_CLOSE[character] then
                table.insert(stack, {
                    open = position,
                    open_character = character,
                    close_character = _OPEN_TO_CLOSE[character],
                })
            elseif _CLOSE_TO_OPEN[character] then
                local candidate = stack[#stack]

                if candidate ~= nil and candidate.open_character == _CLOSE_TO_OPEN[character] then
                    table.remove(stack)
                    candidate.close = position

                    local contains_cursor = _compare_positions(candidate.open, cursor) <= 0
                        and _compare_positions(cursor, candidate.close) <= 0

                    if contains_cursor then
                        return candidate
                    end
                end
            end
        end
    end

    return nil
end

--- Get the text inside a delimiter pair.
---
---@param lines string[] The source lines.
---@param pair _my.code_argument_toggle.Pair The delimiter pair.
---@return string # The inner text.
local function _get_inner_text(lines, pair)
    if pair.open.line == pair.close.line then
        local line = _get_line(lines, pair.open.line)

        return line:sub(pair.open.column + 2, pair.close.column)
    end

    ---@type string[]
    local output = {}

    for line_number = pair.open.line, pair.close.line do
        local line = _get_line(lines, line_number)

        if line_number == pair.open.line then
            table.insert(output, line:sub(pair.open.column + 2))
        elseif line_number == pair.close.line then
            table.insert(output, line:sub(1, pair.close.column))
        else
            table.insert(output, line)
        end
    end

    return table.concat(output, "\n")
end

--- Split `text` on top-level commas.
---
---@param text string The text to split.
---@return string[] # The top-level items.
local function _split_top_level_items(text)
    ---@type string[]
    local items = {}
    local start_index = 1
    local depth = 0

    for index = 1, #text do
        local character = text:sub(index, index)

        if _OPEN_TO_CLOSE[character] then
            depth = depth + 1
        elseif _CLOSE_TO_OPEN[character] then
            depth = depth - 1
        elseif character == "," and depth == 0 then
            table.insert(items, text:sub(start_index, index - 1))
            start_index = index + 1
        end
    end

    table.insert(items, text:sub(start_index))

    return items
end

--- Trim leading and trailing whitespace from `text`.
---
---@param text string The text to trim.
---@return string # The trimmed text.
local function _trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Normalize split items.
---
---@param items string[] Raw split items.
---@return string[] # Trimmed nonempty items.
local function _clean_items(items)
    ---@type string[]
    local result = {}

    for _, item in ipairs(items) do
        local trimmed = _trim(item)

        if trimmed ~= "" then
            table.insert(result, trimmed)
        end
    end

    return result
end

--- Get a line's indentation text.
---
---@param line string The line to inspect.
---@return string # Leading whitespace.
local function _get_indent(line)
    return line:match("^%s*") or ""
end

--- Make one indentation level for the current buffer.
---
---@return string # One indentation level.
local function _make_indent_level()
    local shiftwidth = math.max(vim.fn.shiftwidth(), 1)

    if vim.bo.expandtab then
        return string.rep(" ", shiftwidth)
    end

    return "\t"
end

--- Check whether the delimiter pair is currently expanded.
---
---@param pair _my.code_argument_toggle.Pair The delimiter pair.
---@return boolean # Whether the pair spans multiple lines.
local function _is_expanded(pair)
    return pair.open.line ~= pair.close.line
end

--- Build expanded replacement lines.
---
---@param pair _my.code_argument_toggle.Pair The delimiter pair.
---@param items string[] The items inside the pair.
---@param base_indent string The indentation for the opening and closing delimiters.
---@return string[] # Replacement lines.
local function _build_expanded_lines(pair, items, base_indent)
    local child_indent = base_indent .. _make_indent_level()
    local lines = { pair.open_character }

    for _, item in ipairs(items) do
        table.insert(lines, child_indent .. item .. ",")
    end

    table.insert(lines, base_indent .. pair.close_character)

    return lines
end

--- Build collapsed replacement lines.
---
---@param pair _my.code_argument_toggle.Pair The delimiter pair.
---@param items string[] The items inside the pair.
---@return string[] # Replacement lines.
local function _build_collapsed_lines(pair, items)
    return { pair.open_character .. table.concat(items, ", ") .. pair.close_character }
end

--- Replace the whole delimiter pair with `replacement`.
---
---@param pair _my.code_argument_toggle.Pair The delimiter pair.
---@param replacement string[] Replacement lines.
local function _replace_pair(pair, replacement)
    vim.api.nvim_buf_set_text(
        0,
        pair.open.line - 1,
        pair.open.column,
        pair.close.line - 1,
        pair.close.column + 1,
        replacement
    )
end

--- Toggle the bracketed code around the cursor.
function M.toggle()
    local buffer = vim.api.nvim_get_current_buf()
    local lines = _get_lines(buffer)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local pair = _find_pair(lines, { line = cursor[1], column = cursor[2] })

    if pair == nil then
        vim.notify("No bracketed code found to toggle.", vim.log.levels.WARN)
        return
    end

    local inner_text = _get_inner_text(lines, pair)
    local items = _clean_items(_split_top_level_items(inner_text))
    local open_line = _get_line(lines, pair.open.line)
    local base_indent = _get_indent(open_line)
    local replacement = _is_expanded(pair) and _build_collapsed_lines(pair, items)
        or _build_expanded_lines(pair, items, base_indent)

    _replace_pair(pair, replacement)
end

vim.keymap.set("n", "<leader>sa", M.toggle, {
    desc = "Toggle bracketed code between single-line and multiline arguments.",
})

return M
