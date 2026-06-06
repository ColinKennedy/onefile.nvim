--- Fold only Python docstrings, using cached Tree-sitter or fallback ranges.

local core_helpers = require("modules.utilities.core_helpers")

local M = {}

---@class _my.python_docstring_folds.Range
---@field first integer 1-indexed start line.
---@field last integer 1-indexed end line.

---@type table<integer, table<integer, boolean>>
local _FOLD_LINES_BY_BUFFER = {}

---@type table<integer, table<integer, _my.python_docstring_folds.Range>>
local _FOLD_RANGES_BY_BUFFER = {}

---@type table<integer, uv.uv_timer_t>
local _REFRESH_TIMERS = {}

local _FOLD_TEXT_WIDTH = 80

---@type table<string, boolean>
local _ALLOWED_FILETYPES = {
    python = true,
}

local _FOLDEXPR = "v:lua.require'modules.features.python_docstring_folds'.foldexpr(v:lnum)"
local _FOLDTEXT = "v:lua.require'modules.features.python_docstring_folds'.foldtext()"

local _AUGROUP = vim.api.nvim_create_augroup("my.python.docstring.folds", { clear = true })

local _PYTHON_DOCSTRING_QUERY = [[
    (module
      .
      (expression_statement
        (string) @docstring))

    (class_definition
      body: (block
        .
        (expression_statement
          (string) @docstring)))

    (function_definition
      body: (block
        .
        (expression_statement
          (string) @docstring)))
]]

---@param range _my.python_docstring_folds.Range
---@return string
local function _range_key(range)
    return string.format("%d:%d", range.first, range.last)
end

---@param ranges _my.python_docstring_folds.Range[]
---@return table<string, boolean>
local function _get_open_ranges(ranges)
    ---@type table<string, boolean>
    local result = {}

    for _, range in ipairs(ranges) do
        if vim.fn.foldclosed(range.first) == -1 then
            result[_range_key(range)] = true
        end
    end

    return result
end

---@param buffer integer
---@param ranges _my.python_docstring_folds.Range[]
local function _save_ranges_to_cache(buffer, ranges)
    ---@type table<integer, boolean>
    local lines = {}

    for _, range in ipairs(ranges) do
        for line = range.first, range.last do
            lines[line] = true
        end
    end

    _FOLD_RANGES_BY_BUFFER[buffer] = ranges
    _FOLD_LINES_BY_BUFFER[buffer] = lines
end

---@param ranges _my.python_docstring_folds.Range[]
---@param open_ranges table<string, boolean>
local function _restore_open_ranges(ranges, open_ranges)
    for _, range in ipairs(ranges) do
        if open_ranges[_range_key(range)] then
            vim.cmd(string.format("silent! %dfoldopen!", range.first))
        end
    end
end

---@return boolean
local function _is_insert_like_mode()
    local mode = vim.api.nvim_get_mode().mode

    return mode:sub(1, 1) == "i" or mode:sub(1, 1) == "R"
end

---@class _my.python_docstring_folds.Options
---@field filetypes string[]?

---@param options _my.python_docstring_folds.Options?
function M.setup(options)
    if not options or not options.filetypes then
        return
    end

    _ALLOWED_FILETYPES = {}

    for _, filetype in ipairs(options.filetypes) do
        _ALLOWED_FILETYPES[filetype] = true
    end
end

---@param buffer integer
---@return boolean
function M.is_enabled_filetype(buffer)
    return _ALLOWED_FILETYPES[vim.bo[buffer].filetype] == true
end

local function _install_for_current_window()
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = _FOLDEXPR
    vim.wo.foldlevel = 0
    vim.wo.foldtext = _FOLDTEXT
    vim.wo.foldenable = true
end

local function _uninstall_from_current_window()
    vim.wo.foldmethod = "manual"
    vim.wo.foldexpr = "0"
    vim.wo.foldtext = "foldtext()"
    vim.wo.foldenable = false
end

---@param buffer integer?
---@param should_refresh boolean?
function M.apply_to_current_window(buffer, should_refresh)
    buffer = buffer or vim.api.nvim_get_current_buf()

    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end

    if M.is_enabled_filetype(buffer) then
        _install_for_current_window()

        if should_refresh then
            M.refresh(buffer)
        end
    else
        _uninstall_from_current_window()
    end
end

---@param first integer
---@param last integer
---@return _my.python_docstring_folds.Range?
local function _make_range(first, last)
    if first >= last then
        return nil
    end

    return { first = first, last = last }
end

---@param node TSNode
---@return _my.python_docstring_folds.Range?
local function _range_from_node(node)
    local start_row, _, end_row, _ = node:range()

    return _make_range(start_row + 1, end_row + 1)
end

---@param buffer integer
---@return _my.python_docstring_folds.Range[]?
function M.get_treesitter_docstring_ranges(buffer)
    if not core_helpers.has_treesitter_parser("python") then
        return nil
    end

    local ok_parser, parser = pcall(vim.treesitter.get_parser, buffer, "python")

    if not ok_parser or not parser then
        return nil
    end

    local ok_query, query = pcall(vim.treesitter.query.parse, "python", _PYTHON_DOCSTRING_QUERY)

    if not ok_query then
        return nil
    end

    local trees = parser:parse()
    local tree = trees and trees[1]

    if not tree then
        return nil
    end

    ---@type _my.python_docstring_folds.Range[]
    local ranges = {}

    for _, node in query:iter_captures(tree:root(), buffer, 0, -1) do
        local range = _range_from_node(node)

        if range then
            table.insert(ranges, range)
        end
    end

    return ranges
end

---@param line string
---@return integer
local function _indent_of(line)
    return #(line:match("^%s*") or "")
end

---@param line string
---@return boolean
local function _is_blank_or_comment(line)
    return line:match("^%s*$") ~= nil or line:match("^%s*#") ~= nil
end

---@param line string
---@return boolean
local function _opens_python_block(line)
    local text = line:gsub("#.*$", "")

    return text:match("^%s*async%s+def%s+[%w_]+.*:%s*$") ~= nil
        or text:match("^%s*def%s+[%w_]+.*:%s*$") ~= nil
        or text:match("^%s*class%s+[%w_]+.*:%s*$") ~= nil
end

---@param line string
---@return string?
local function _docstring_quote(line)
    local quote = line:match([[^%s*[rRuUfFbB]*(["'])]])

    if not quote then
        return nil
    end

    local triple_quote = quote .. quote .. quote

    if line:find(triple_quote, 1, true) then
        return triple_quote
    end

    return nil
end

---@param line string
---@return string
local function _strip_docstring_quotes(line)
    line = line:gsub([[^%s*[rRuUfFbB]*"""]], "")
    line = line:gsub([[^%s*[rRuUfFbB]*''']], "")
    line = line:gsub([["""%s*$]], "")
    line = line:gsub([['''%s*$]], "")
    line = line:gsub("^%s+", "")
    line = line:gsub("%s+$", "")

    return line
end

---@param line string
---@param quote string
---@return boolean
local function _has_closing_quote_after_opener(line, quote)
    local _, opener_end = line:find(quote, 1, true)

    if not opener_end then
        return false
    end

    return line:find(quote, opener_end + 1, true) ~= nil
end

---@param lines string[]
---@param start_line integer
---@return integer?
local function _find_docstring_end(lines, start_line)
    local quote = _docstring_quote(lines[start_line])

    if not quote then
        return nil
    end

    if _has_closing_quote_after_opener(lines[start_line], quote) then
        return start_line
    end

    for line_number = start_line + 1, #lines do
        if lines[line_number]:find(quote, 1, true) then
            return line_number
        end
    end

    return nil
end

---@param lines string[]
---@param start_line integer
---@param minimum_indent integer?
---@return integer?
local function _first_statement_line(lines, start_line, minimum_indent)
    for line_number = start_line, #lines do
        local line = lines[line_number]

        if not _is_blank_or_comment(line) then
            if minimum_indent and _indent_of(line) < minimum_indent then
                return nil
            end

            return line_number
        end
    end

    return nil
end

---@param lines string[]
---@return _my.python_docstring_folds.Range[]
function M.get_fallback_docstring_ranges(lines)
    ---@type _my.python_docstring_folds.Range[]
    local ranges = {}

    local module_docstring_line = _first_statement_line(lines, 1, nil)

    if module_docstring_line then
        local last = _find_docstring_end(lines, module_docstring_line)
        local range = last and _make_range(module_docstring_line, last) or nil

        if range then
            table.insert(ranges, range)
        end
    end

    for line_number, line in ipairs(lines) do
        if _opens_python_block(line) then
            local block_indent = _indent_of(line)
            local first_statement = _first_statement_line(lines, line_number + 1, block_indent + 1)

            if first_statement and _indent_of(lines[first_statement]) > block_indent then
                local last = _find_docstring_end(lines, first_statement)
                local range = last and _make_range(first_statement, last) or nil

                if range then
                    table.insert(ranges, range)
                end
            end
        end
    end

    return ranges
end

---@param buffer integer
---@return _my.python_docstring_folds.Range[]
function M.get_docstring_ranges(buffer)
    local ranges = M.get_treesitter_docstring_ranges(buffer)

    if ranges then
        return ranges
    end

    return M.get_fallback_docstring_ranges(vim.api.nvim_buf_get_lines(buffer, 0, -1, false))
end

---@param buffer integer?
function M.refresh(buffer)
    buffer = buffer or vim.api.nvim_get_current_buf()

    if not vim.api.nvim_buf_is_valid(buffer) or not M.is_enabled_filetype(buffer) then
        return
    end

    vim.api.nvim_buf_call(buffer, function()
        local previous_ranges = _FOLD_RANGES_BY_BUFFER[buffer] or {}
        local open_ranges = _get_open_ranges(previous_ranges)
        local view = vim.fn.winsaveview()
        local cursor = vim.api.nvim_win_get_cursor(0)

        _save_ranges_to_cache(buffer, M.get_docstring_ranges(buffer))

        if _is_insert_like_mode() then
            return
        end

        vim.cmd("silent! normal! zx")
        _restore_open_ranges(_FOLD_RANGES_BY_BUFFER[buffer] or {}, open_ranges)
        pcall(vim.api.nvim_win_set_cursor, 0, cursor)
        vim.fn.winrestview(view)
    end)
end

---@param buffer integer?
---@param delay integer?
function M.schedule_refresh(buffer, delay)
    buffer = buffer or vim.api.nvim_get_current_buf()
    delay = delay or 500

    if _REFRESH_TIMERS[buffer] then
        _REFRESH_TIMERS[buffer]:stop()
    else
        _REFRESH_TIMERS[buffer] = vim.uv.new_timer()
    end

    _REFRESH_TIMERS[buffer]:start(
        delay,
        0,
        vim.schedule_wrap(function()
            if _REFRESH_TIMERS[buffer] then
                _REFRESH_TIMERS[buffer]:stop()
            end

            M.refresh(buffer)
        end)
    )
end

---@param lnum integer
---@return integer
function M.foldexpr(lnum)
    local buffer = vim.api.nvim_get_current_buf()

    if not M.is_enabled_filetype(buffer) then
        return 0
    end

    local lines = _FOLD_LINES_BY_BUFFER[buffer]

    if not lines then
        return 0
    end

    if lines[lnum] then
        return 1
    end

    return 0
end

---@param buffer integer
---@param first_line integer
---@param last_line integer
---@return string
function M.get_summary(buffer, first_line, last_line)
    local lines = vim.api.nvim_buf_get_lines(buffer, first_line - 1, last_line, false)

    for _, line in ipairs(lines) do
        local summary = _strip_docstring_quotes(line)

        if summary ~= "" then
            return summary
        end
    end

    return "docstring"
end

---@param text string
---@param maximum integer
---@return string
local function _truncate(text, maximum)
    if #text <= maximum then
        return text
    end

    return text:sub(1, maximum)
end

---@return string
function M.foldtext()
    local buffer = vim.api.nvim_get_current_buf()

    if not M.is_enabled_filetype(buffer) then
        return vim.fn.foldtext()
    end

    local first_line = vim.v.foldstart
    local last_line = vim.v.foldend
    local line_count = last_line - first_line + 1
    local indent = vim.fn.getline(first_line):match("^%s*") or ""
    local suffix = string.format("[%d lines]>", line_count)
    local prefix = indent .. "<"
    local summary_width = math.max(1, _FOLD_TEXT_WIDTH - #prefix - #suffix - 1)
    local summary = _truncate(M.get_summary(buffer, first_line, last_line), summary_width)
    local dot_count = math.max(1, _FOLD_TEXT_WIDTH - #prefix - #summary - #suffix)

    return prefix .. summary .. string.rep("·", dot_count) .. suffix
end

vim.api.nvim_create_autocmd("FileType", {
    group = _AUGROUP,
    pattern = "*",
    callback = function(event)
        M.apply_to_current_window(event.buf, true)
    end,
})

vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = _AUGROUP,
    callback = function(event)
        M.apply_to_current_window(event.buf)
    end,
})

vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave", "BufWritePost" }, {
    group = _AUGROUP,
    callback = function(event)
        if not M.is_enabled_filetype(event.buf) then
            return
        end

        M.schedule_refresh(event.buf, 500)
    end,
})

vim.api.nvim_create_autocmd("FileChangedShellPost", {
    group = _AUGROUP,
    callback = function(event)
        if not M.is_enabled_filetype(event.buf) then
            return
        end

        M.refresh(event.buf)
    end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
    group = _AUGROUP,
    callback = function(event)
        _FOLD_LINES_BY_BUFFER[event.buf] = nil
        _FOLD_RANGES_BY_BUFFER[event.buf] = nil

        if _REFRESH_TIMERS[event.buf] then
            _REFRESH_TIMERS[event.buf]:stop()
            _REFRESH_TIMERS[event.buf]:close()
            _REFRESH_TIMERS[event.buf] = nil
        end
    end,
})

return M
