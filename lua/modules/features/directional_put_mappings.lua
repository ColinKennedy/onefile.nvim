--- Add deterministic linewise put mappings with indentation control.

local M = {}

---@alias _my.directional_put.Direction "above" | "below"

---@alias _my.directional_put.IndentMode "same" | "indent" | "dedent"

---@class _my.directional_put.Region
---@field buffer integer The buffer where the put happened.
---@field start_line integer The first pasted line.
---@field end_line integer The last pasted line.

---@type _my.directional_put.Region?
local _LAST_PUT_REGION

--- Get the register to paste from.
---
---@return string # A register name that can be passed to `getreg`.
---
local function _get_register_name()
    if vim.v.register ~= "" then
        return vim.v.register
    end

    return '"'
end

--- Get the current buffer's tab width.
---
---@return integer # The tabstop to use for visual indentation calculations.
---
local function _get_tabstop()
    return math.max(vim.bo.tabstop, 1)
end

--- Get the current buffer's shift width.
---
---@return integer # The indentation level width to add or remove.
---
local function _get_shiftwidth()
    return math.max(vim.fn.shiftwidth(), 1)
end

--- Get all leading whitespace from `text`.
---
---@param text string A line of text.
---@return string # Leading spaces and tabs from `text`.
---
local function _get_leading_whitespace(text)
    return text:match("^%s*") or ""
end

--- Count the visual indentation columns in `text`.
---
---@param text string A line or whitespace prefix to measure.
---@return integer # The number of visual columns occupied by leading whitespace.
---
local function _get_indent_columns(text)
    local tabstop = _get_tabstop()
    local columns = 0

    for character in text:gmatch(".") do
        if character == "\t" then
            columns = columns + (tabstop - (columns % tabstop))
        elseif character == " " then
            columns = columns + 1
        else
            break
        end
    end

    return columns
end

--- Make an indentation string for this buffer.
---
---@param columns integer The visual column width that the indentation should occupy.
---@return string # Whitespace that reaches `columns`.
---
local function _make_indent(columns)
    columns = math.max(columns, 0)

    if vim.bo.expandtab then
        return string.rep(" ", columns)
    end

    local tabstop = _get_tabstop()
    local tabs = math.floor(columns / tabstop)
    local spaces = columns % tabstop

    return string.rep("\t", tabs) .. string.rep(" ", spaces)
end

--- Remove up to `columns` visual indentation columns from `line`.
---
---@param line string A line to dedent.
---@param columns integer The maximum visual indentation columns to remove.
---@return string # The line after removing whole leading whitespace characters.
---
local function _remove_indent_columns(line, columns)
    if columns <= 0 then
        return line
    end

    local tabstop = _get_tabstop()
    local removed = 0
    local byte_index = 1

    while byte_index <= #line do
        local character = line:sub(byte_index, byte_index)
        local width

        if character == " " then
            width = 1
        elseif character == "\t" then
            width = tabstop - (removed % tabstop)
        else
            break
        end

        if removed + width > columns then
            break
        end

        removed = removed + width
        byte_index = byte_index + 1
    end

    return line:sub(byte_index)
end

--- Get the least visual indentation shared by all non-blank lines.
---
---@param lines string[] Lines to inspect.
---@return integer # The least indentation column count among non-blank lines.
---
local function _get_common_indent_columns(lines)
    local common

    for _, line in ipairs(lines) do
        if line:find("%S") then
            local columns = _get_indent_columns(_get_leading_whitespace(line))
            common = math.min(common or columns, columns)
        end
    end

    return common or 0
end

--- Remove the indentation shared by all non-blank `lines`.
---
---@param lines string[] Register lines to normalize before inserting.
---@return string[] # Lines with common indentation removed.
---
local function _dedent_common_indent(lines)
    local common = _get_common_indent_columns(lines)
    ---@type string[]
    local output = {}

    for _, line in ipairs(lines) do
        table.insert(output, _remove_indent_columns(line, common))
    end

    return output
end

--- Get linewise register contents from `register`.
---
---@param register string The register to inspect.
---@return string[] # Register text split into lines.
---
local function _get_register_lines_from(register)
    ---@type string[]
    local value = vim.fn.getreg(register, 1, true)

    if #value > 1 and value[#value] == "" then
        table.remove(value)
    end

    return value
end

--- Get linewise register contents.
---
---@return string[] # Register text split into lines.
---
local function _get_register_lines()
    return _get_register_lines_from(_get_register_name())
end

--- Apply a computed indentation prefix to every non-blank line.
---
---@param lines string[] Lines that have already been common-dedented.
---@param indent string The indentation prefix to use.
---@return string[] # Lines ready to insert into the buffer.
---
local function _apply_indent(lines, indent)
    ---@type string[]
    local output = {}

    for _, line in ipairs(lines) do
        if line:find("%S") then
            table.insert(output, indent .. line)
        else
            table.insert(output, "")
        end
    end

    return output
end

--- Compute the target indentation for a put mapping.
---
---@param mode _my.directional_put.IndentMode How much indentation to add or remove.
---@return string # The whitespace prefix to use for pasted non-blank lines.
---
local function _get_target_indent(mode)
    local current_line = vim.api.nvim_get_current_line()
    local current_indent = _get_leading_whitespace(current_line)

    if mode == "same" then
        return current_indent
    end

    local current_columns = _get_indent_columns(current_indent)
    local offset = mode == "indent" and _get_shiftwidth() or -_get_shiftwidth()

    return _make_indent(current_columns + offset)
end

--- Remember the last put region for `gp`.
---
---@param start_line integer The first pasted line.
---@param end_line integer The last pasted line.
---
local function _set_last_put_region(start_line, end_line)
    _LAST_PUT_REGION = {
        buffer = vim.api.nvim_get_current_buf(),
        start_line = start_line,
        end_line = end_line,
    }
    vim.fn.setpos("'[", { 0, start_line, 1, 0 })
    vim.fn.setpos("']", { 0, end_line, math.max(#vim.fn.getline(end_line), 1), 0 })
end

--- Find `register_lines` near likely native put marks.
---
---@param candidates integer[] Possible 1-or-more start lines to inspect.
---@param register_lines string[] The linewise register contents.
---@return _my.directional_put.Region? region The matching buffer region, if found.
local function _find_register_region(candidates, register_lines)
    local line_count = vim.api.nvim_buf_line_count(0)

    for _, candidate in ipairs(candidates) do
        if candidate >= 1 and (candidate + #register_lines - 1) <= line_count then
            local lines = vim.api.nvim_buf_get_lines(0, candidate - 1, candidate - 1 + #register_lines, false)

            if vim.deep_equal(lines, register_lines) then
                return {
                    buffer = vim.api.nvim_get_current_buf(),
                    start_line = candidate,
                    end_line = candidate + #register_lines - 1,
                }
            end
        end
    end

    return nil
end

--- Get the linewise put region remembered by Vim's native put marks.
---
---@return _my.directional_put.Region? region The native put region, if one exists.
local function _get_native_put_region()
    local start_position = vim.fn.getpos("'[")
    local end_position = vim.fn.getpos("']")
    local start_line = start_position[2]
    local end_line = end_position[2]
    local is_linewise_register = vim.fn.getregtype('"'):sub(1, 1) == "V"
    local register_lines = _get_register_lines_from('"')
    local register_line_count = #register_lines
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

    if start_line <= 0 or end_line <= 0 then
        if not is_linewise_register then
            return nil
        end

        start_line = cursor_line
        end_line = start_line + register_line_count - 1
    end

    if start_line == end_line and is_linewise_register then
        local matched_region = _find_register_region({
            start_line,
            start_line + 1,
            cursor_line,
            cursor_line + 1,
        }, register_lines)

        if matched_region then
            return matched_region
        end

        if register_line_count > 1 then
            start_line = cursor_line
        end

        end_line = start_line + register_line_count - 1
    end

    return {
        start_line = math.min(start_line, end_line),
        end_line = math.max(start_line, end_line),
    }
end

--- Put register lines above or below the current line with indentation control.
---
---@param direction _my.directional_put.Direction Where to insert relative to the cursor line.
---@param mode _my.directional_put.IndentMode How to indent the pasted block.
---
function M.put_linewise(direction, mode)
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local insert_index = direction == "above" and (row - 1) or row
    local lines = _apply_indent(_dedent_common_indent(_get_register_lines()), _get_target_indent(mode))

    vim.api.nvim_buf_set_lines(0, insert_index, insert_index, true, lines)

    local start_line = insert_index + 1
    local end_line = start_line + #lines - 1
    _set_last_put_region(start_line, end_line)
    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
end

--- Select the last region inserted by a custom put mapping.
function M.select_last_put()
    local current_buffer = vim.api.nvim_get_current_buf()
    local region = _LAST_PUT_REGION

    if not region or region.buffer ~= current_buffer then
        region = _get_native_put_region()
    end

    if not region then
        vim.notify("No custom put region found.", vim.log.levels.WARN)

        return
    end

    local line_count = vim.api.nvim_buf_line_count(0)
    local start_line = math.min(region.start_line, line_count)
    local end_line = math.min(region.end_line, line_count)

    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
    vim.cmd("normal! V")
    vim.api.nvim_win_set_cursor(0, { end_line, 0 })
end

vim.keymap.set("n", "[p", function()
    M.put_linewise("above", "same")
end, { desc = "Paste line above with the current indentation." })
vim.keymap.set("n", "]p", function()
    M.put_linewise("below", "same")
end, { desc = "Paste line below with the current indentation." })
vim.keymap.set("n", "=p", function()
    M.put_linewise("below", "same")
end, { desc = "Paste line below with the current indentation." })
vim.keymap.set("n", "=P", function()
    M.put_linewise("above", "same")
end, { desc = "Paste line above with the current indentation." })
vim.keymap.set("n", ">p", function()
    M.put_linewise("below", "indent")
end, { desc = "Paste line below and add one indentation level." })
vim.keymap.set("n", ">P", function()
    M.put_linewise("above", "indent")
end, { desc = "Paste line above and add one indentation level." })
vim.keymap.set("n", "<p", function()
    M.put_linewise("below", "dedent")
end, { desc = "Paste line below and remove one indentation level." })
vim.keymap.set("n", "<P", function()
    M.put_linewise("above", "dedent")
end, { desc = "Paste line above and remove one indentation level." })
vim.keymap.set("n", "gp", M.select_last_put, { desc = "Select the last custom put region." })

return M
