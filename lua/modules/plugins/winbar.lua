--- A lightweight winbar inspired by fgheng/winbar.nvim.

local _P = {}
local core_helpers = require("modules.utilities.core_helpers")

---@class _my.winbar.Scope
---@field name string The display name for the scope.
---@field start_row integer The first zero-based row in the scope.
---@field start_column integer The first zero-based column in the scope.
---@field end_row integer The final zero-based row in the scope.
---@field end_column integer The final zero-based column in the scope.

local _EXCLUDED_FILETYPES = {
    alpha = true,
    checkhealth = true,
    dashboard = true,
    gitcommit = true,
    help = true,
    lir = true,
    man = true,
    messages = true,
    neogitstatus = true,
    noice = true,
    notify = true,
    NvimTree = true,
    Outline = true,
    packer = true,
    qf = true,
    query = true,
    spectre_panel = true,
    startify = true,
    toggleterm = true,
    Trouble = true,
}

local _EXCLUDED_BUFTYPES = {
    acwrite = true,
    help = true,
    nofile = true,
    nowrite = true,
    prompt = true,
    quickfix = true,
    terminal = true,
}

local _ICONS = {
    file_icon_default = "[file]",
    lock_icon = "[lock]",
    separator = ">",
}
local _ELLIPSIS = "..."

if core_helpers.IS_NERDFONT_ALLOWED then
    _ICONS.file_icon_default = ""
    _ICONS.lock_icon = ""
    _ICONS.separator = ">"
end

--- Escape `text` for use inside a statusline-like option.
---
---@param text string
---@return string
function _P.escape_statusline_text(text)
    local escaped = text:gsub("%%", "%%%%")

    return escaped
end

--- Remove statusline highlight and escape syntax from `text`.
---
---@param text string A statusline-formatted string.
---@return string # The visible text without statusline syntax.
function _P.strip_statusline_syntax(text)
    local cleaned = text:gsub("%%#[^#]*#", ""):gsub("%%%%", "%%")

    return cleaned
end

--- Get the display width for a statusline-formatted string.
---
---@param text string A statusline-formatted string.
---@return integer # The visible display width.
function _P.get_statusline_display_width(text)
    return vim.fn.strdisplaywidth(_P.strip_statusline_syntax(text))
end

--- Define the highlight groups used by the winbar.
function _P.set_highlights()
    local background = vim.api.nvim_get_hl(0, { name = "Function", link = false }).bg
    local directory = vim.api.nvim_get_hl(0, { name = "Directory", link = false }).fg
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).fg
    local error_message = vim.api.nvim_get_hl(0, { name = "ErrorMsg", link = false }).fg
    local function_ = vim.api.nvim_get_hl(0, { name = "Function", link = false }).fg

    vim.api.nvim_set_hl(0, "MyWinBarPath", { fg = directory, bg = background })
    vim.api.nvim_set_hl(0, "MyWinBarFileName", { fg = normal, bg = background })
    vim.api.nvim_set_hl(0, "MyWinBarReadonly", { fg = error_message, bg = background })
    vim.api.nvim_set_hl(0, "MyWinBarSymbols", { fg = function_, bg = background })
end

---@param window integer
---@return boolean
function _P.is_window_excluded(window)
    if not vim.api.nvim_win_is_valid(window) then
        return true
    end

    return vim.api.nvim_win_get_config(window).relative ~= ""
end

---@param buffer integer
---@return boolean
function _P.is_buffer_excluded(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return true
    end

    local filetype = vim.bo[buffer].filetype
    local buftype = vim.bo[buffer].buftype
    local path = vim.api.nvim_buf_get_name(buffer)

    return _EXCLUDED_FILETYPES[filetype] or _EXCLUDED_BUFTYPES[buftype] or not vim.bo[buffer].buflisted or path == ""
end

---@param window integer
---@param buffer integer
---@return boolean
function _P.is_excluded(window, buffer)
    return _P.is_window_excluded(window) or _P.is_buffer_excluded(buffer)
end

---@param path string
---@return string
function _P.get_display_path(path)
    local relative = vim.fs.relpath(vim.fn.getcwd(), path)

    if relative and relative ~= "" then
        return relative
    end

    return vim.fn.fnamemodify(path, ":~:.")
end

---@param path string
---@return string
function _P.get_file_icon(path)
    local ok, devicons = pcall(require, "nvim-web-devicons")

    if not ok then
        return _ICONS.file_icon_default
    end

    local icon = devicons.get_icon(vim.fs.basename(path), vim.fn.fnamemodify(path, ":e"), { default = true })

    return icon or _ICONS.file_icon_default
end

---@param path string
---@return string
function _P.get_path_text(path)
    local display = _P.get_display_path(path)
    local parts = vim.split(display, "[/\\]", { trimempty = true })

    if vim.tbl_isempty(parts) then
        return ""
    end

    local file_name = table.remove(parts)
    ---@type string[]
    local output = {}

    for _, part in ipairs(parts) do
        table.insert(output, "%#MyWinBarPath#")
        table.insert(output, _P.escape_statusline_text(part))
        table.insert(output, " ")
        table.insert(output, _ICONS.separator)
        table.insert(output, " ")
    end

    table.insert(output, "%#MyWinBarFileName#")
    table.insert(output, _P.escape_statusline_text(_P.get_file_icon(path)))
    table.insert(output, " ")
    table.insert(output, _P.escape_statusline_text(file_name))

    return table.concat(output, "")
end

---@param buffer integer
---@return string
function _P.get_editor_state_text(buffer)
    ---@type string[]
    local output = {}

    if vim.bo[buffer].readonly or not vim.bo[buffer].modifiable then
        table.insert(output, "%#MyWinBarReadonly#")
        table.insert(output, " ")
        table.insert(output, _ICONS.lock_icon)
    end

    return table.concat(output, "")
end

local _TREESITTER_QUERIES = {
    lua = [[
        (function_declaration
          name: (identifier) @name) @scope
    ]],
    python = [[
        (function_definition
          name: (identifier) @name) @scope

        (class_definition
          name: (identifier) @name) @scope
    ]],
}

---@type table<string, vim.treesitter.Query|false>
local _TREESITTER_QUERY_CACHE = {}

---@param language string
---@return vim.treesitter.Query?
function _P.get_treesitter_query(language)
    if _TREESITTER_QUERY_CACHE[language] ~= nil then
        local cached = _TREESITTER_QUERY_CACHE[language]

        if cached == false then
            return nil
        end

        return cached
    end

    local query_text = _TREESITTER_QUERIES[language]

    if not query_text then
        _TREESITTER_QUERY_CACHE[language] = false

        return nil
    end

    local ok, query = pcall(vim.treesitter.query.parse, language, query_text)

    if not ok then
        _TREESITTER_QUERY_CACHE[language] = false

        return nil
    end

    _TREESITTER_QUERY_CACHE[language] = query

    return query
end

---@param node TSNode
---@param row integer
---@param column integer
---@return boolean
function _P.node_contains_position(node, row, column)
    local start_row, start_column, end_row, end_column = node:range()

    if row < start_row or row > end_row then
        return false
    end

    if row == start_row and column < start_column then
        return false
    end

    if row == end_row and column > end_column then
        return false
    end

    return true
end

---@param left _my.winbar.Scope
---@param right _my.winbar.Scope
---@return boolean
function _P.sort_scopes_by_range(left, right)
    if left.start_row ~= right.start_row then
        return left.start_row < right.start_row
    end

    if left.start_column ~= right.start_column then
        return left.start_column < right.start_column
    end

    if left.end_row ~= right.end_row then
        return left.end_row > right.end_row
    end

    return left.end_column > right.end_column
end

---@param node TSNode
---@param buffer integer
---@return string
function _P.get_node_text(node, buffer)
    local text = vim.treesitter.get_node_text(node, buffer)
    local cleaned = text:gsub("^%s*", ""):gsub("%s*$", ""):gsub("%s+", " ")

    return cleaned
end

---@param match table<integer, TSNode[]|TSNode>
---@param query vim.treesitter.Query
---@param buffer integer
---@return string?
function _P.get_match_name(match, query, buffer)
    for id, nodes in pairs(match) do
        if query.captures[id] == "name" then
            if type(nodes) == "table" then
                nodes = nodes[1]
            end

            return _P.get_node_text(nodes, buffer)
        end
    end

    return nil
end

---@param match table<integer, TSNode[]|TSNode>
---@param query vim.treesitter.Query
---@return TSNode?
function _P.get_match_scope(match, query)
    for id, nodes in pairs(match) do
        if query.captures[id] == "scope" then
            if type(nodes) == "table" then
                return nodes[1]
            end

            return nodes
        end
    end

    return nil
end

---@param buffer integer
---@return string[]
function _P.get_treesitter_scope_names(buffer)
    local filetype = vim.bo[buffer].filetype
    local language = core_helpers._FILETYPE_TO_TREESITTER[filetype] or filetype
    local query = _P.get_treesitter_query(language)

    if not query or not core_helpers.has_treesitter_parser(language) then
        return {}
    end

    local parser_ok, parser = pcall(vim.treesitter.get_parser, buffer, language)

    if not parser_ok or not parser then
        return {}
    end

    ---@cast parser vim.treesitter.LanguageTree
    local parse_ok, trees = pcall(function()
        return parser:parse()
    end)

    if not parse_ok or not trees then
        return {}
    end

    local tree = trees[1]

    if not tree then
        return {}
    end

    local row, column = unpack(vim.api.nvim_win_get_cursor(0))
    row = row - 1

    ---@type _my.winbar.Scope[]
    local scopes = {}

    for _, match, _ in query:iter_matches(tree:root(), buffer, 0, row + 1) do
        local scope = _P.get_match_scope(match, query)

        if scope and _P.node_contains_position(scope, row, column) then
            local name = _P.get_match_name(match, query, buffer)

            if name and name ~= "" then
                local start_row, start_column, end_row, end_column = scope:range()

                table.insert(scopes, {
                    end_column = end_column,
                    end_row = end_row,
                    name = name,
                    start_column = start_column,
                    start_row = start_row,
                })
            end
        end
    end

    table.sort(scopes, _P.sort_scopes_by_range)

    ---@type string[]
    local names = {}

    for _, scope in ipairs(scopes) do
        table.insert(names, scope.name)
    end

    return names
end

--- Check whether `buffer` has a Tree-sitter parser available.
---
---@param buffer integer The buffer to inspect.
---@return boolean # If a parser can be used, return `true`.
function _P.has_treesitter_context(buffer)
    local filetype = vim.bo[buffer].filetype
    local language = core_helpers._FILETYPE_TO_TREESITTER[filetype] or filetype

    if language == "" then
        return false
    end

    if not core_helpers.has_treesitter_parser(language) then
        return false
    end

    local parser_ok = pcall(vim.treesitter.get_parser, buffer, language)

    return parser_ok
end

--- Trim whitespace and collapse internal spacing from `text`.
---
---@param text string The line text to clean.
---@return string # The normalized line text.
function _P.clean_indent_context_text(text)
    local cleaned = text:gsub("^%s*", ""):gsub("%s*$", ""):gsub("%s+", " ")

    return cleaned
end

--- Remove paired bracket contents from `text`.
---
---@param text string The text to simplify.
---@param open string The opening bracket character.
---@param close string The closing bracket character.
---@return string # The simplified text.
local function _remove_paired_bracket_contents(text, open, close)
    local characters = vim.fn.split(text, [[\zs]])
    ---@type integer[]
    local stack = {}
    ---@type table<integer, boolean>
    local remove = {}

    for index, character in ipairs(characters) do
        if character == open then
            table.insert(stack, index)
        elseif character == close and not vim.tbl_isempty(stack) then
            local start = table.remove(stack)

            for remove_index = start, index do
                remove[remove_index] = true
            end
        end
    end

    ---@type string[]
    local output = {}

    for index, character in ipairs(characters) do
        if not remove[index] then
            table.insert(output, character)
        end
    end

    return table.concat(output, "")
end

--- Simplify a context section for compact winbar display.
---
---@param text string The raw context text.
---@return string # The simplified context text.
function _P.simplify_context_text(text)
    local cleaned = _P.clean_indent_context_text(text)

    cleaned = _remove_paired_bracket_contents(cleaned, "(", ")")
    cleaned = _remove_paired_bracket_contents(cleaned, "{", "}")
    cleaned = _remove_paired_bracket_contents(cleaned, "[", "]")
    cleaned = cleaned:gsub("[:;,]+", " ")
    cleaned = _P.clean_indent_context_text(cleaned)

    return cleaned
end

--- Get the indentation level of `text`.
---
---@param text string The line text to inspect.
---@param tabstop integer? The tab display width. Defaults to the current buffer's `tabstop`.
---@return integer # The number of leading whitespace characters.
function _P.get_line_indent(text, tabstop)
    tabstop = tabstop or vim.bo.tabstop

    local column = 0
    local whitespace = text:match("^%s*") or ""

    for _, character in ipairs(vim.fn.split(whitespace, [[\zs]])) do
        if character == "\t" then
            column = column + (tabstop - (column % tabstop))
        else
            column = column + vim.fn.strdisplaywidth(character)
        end
    end

    return column
end

--- Find the nearest nonblank row at or before `row`.
---
---@param buffer integer The buffer to inspect.
---@param row integer The 1-or-more row to start from.
---@return integer? # The nearest nonblank row, if any.
local function _find_nearest_nonblank_row(buffer, row)
    for index = row, 1, -1 do
        local line = vim.api.nvim_buf_get_lines(buffer, index - 1, index, false)[1] or ""

        if line:match("%S") then
            return index
        end
    end

    return nil
end

--- Get indentation-based context names for `buffer`.
---
---@param buffer integer The buffer to inspect.
---@param row integer? The 1-or-more cursor row. Defaults to the window cursor.
---@return string[] # The indentation context from shallowest to deepest.
function _P.get_indentation_scope_names(buffer, row)
    row = row or vim.api.nvim_win_get_cursor(0)[1]
    row = _find_nearest_nonblank_row(buffer, row)

    if not row then
        return {}
    end

    local line = vim.api.nvim_buf_get_lines(buffer, row - 1, row, false)[1] or ""
    local tabstop = vim.bo[buffer].tabstop
    local maximum_indent = _P.get_line_indent(line, tabstop)
    ---@type string[]
    local names = {}

    for index = row - 1, 1, -1 do
        line = vim.api.nvim_buf_get_lines(buffer, index - 1, index, false)[1] or ""

        if line:match("%S") then
            local indent = _P.get_line_indent(line, tabstop)

            if indent < maximum_indent then
                local name = _P.simplify_context_text(line)

                if name ~= "" then
                    table.insert(names, 1, name)
                end

                maximum_indent = indent
            end
        end
    end

    return names
end

--- Elide `text` from the left to fit within `budget`.
---
---@param text string The text to elide.
---@param budget integer The maximum display width.
---@return string # The elided text.
function _P.elide_left(text, budget)
    if budget <= 0 then
        return ""
    end

    if vim.fn.strdisplaywidth(text) <= budget then
        return text
    end

    if budget <= #_ELLIPSIS then
        return _ELLIPSIS:sub(1, budget)
    end

    local suffix_budget = budget - vim.fn.strdisplaywidth(_ELLIPSIS .. " ")
    local suffix = ""

    local characters = vim.fn.split(text, [[\zs]])

    for index = #characters, 1, -1 do
        local character = characters[index]
        local candidate = character .. suffix

        if vim.fn.strdisplaywidth(candidate) > suffix_budget then
            break
        end

        suffix = candidate
    end

    suffix = suffix:gsub("^%s*", "")

    return _ELLIPSIS .. " " .. suffix
end

--- Fit context `names` into `budget`, preferring deeper entries.
---
---@param names string[] The context names from shallowest to deepest.
---@param budget integer The maximum display width.
---@return string # The formatted context text.
function _P.format_context_names(names, budget)
    if vim.tbl_isempty(names) or budget <= 0 then
        return ""
    end

    --- Fit `values` into `available`.
    ---
    ---@param values string[] The values to fit.
    ---@param available integer The available display width.
    ---@return string # The formatted values.
    local function _format_visible(values, available)
        local separator = " " .. _ICONS.separator .. " "
        local separator_width = math.max(#values - 1, 0) * vim.fn.strdisplaywidth(separator)
        local item_budget = available - separator_width

        if item_budget <= 0 then
            return ""
        end

        local fair_budget = math.max(math.floor(item_budget / #values), 1)
        ---@type integer[]
        local budgets = {}
        local used = 0

        for index, value in ipairs(values) do
            budgets[index] = math.min(vim.fn.strdisplaywidth(value), fair_budget)
            used = used + budgets[index]
        end

        local leftover = item_budget - used

        local has_placeholder = values[1] == _ELLIPSIS

        while leftover > 0 do
            local changed = false
            local indexes = has_placeholder and { #values, 2 } or vim.fn.range(1, #values)

            for _, index in ipairs(indexes) do
                local maximum = vim.fn.strdisplaywidth(values[index])

                if has_placeholder then
                    maximum = math.min(maximum, 10)
                end

                while has_placeholder and budgets[index] < maximum and leftover > 0 do
                    budgets[index] = budgets[index] + 1
                    leftover = leftover - 1
                    changed = true
                end

                if not has_placeholder and budgets[index] < maximum then
                    budgets[index] = budgets[index] + 1
                    leftover = leftover - 1
                    changed = true
                end

                if leftover <= 0 then
                    break
                end
            end

            if not changed then
                break
            end
        end

        ---@type string[]
        local parts = {}

        for index, value in ipairs(values) do
            table.insert(parts, _P.elide_left(value, budgets[index]))
        end

        return table.concat(parts, separator)
    end

    local separator = " " .. _ICONS.separator .. " "
    local separator_width = math.max(#names - 1, 0) * vim.fn.strdisplaywidth(separator)
    local average_budget = (budget - separator_width) / #names

    if #names > 3 and average_budget < (vim.fn.strdisplaywidth(_ELLIPSIS .. " ") + 2) then
        return _format_visible({ _ELLIPSIS, names[#names - 1], names[#names] }, budget)
    end

    return _format_visible(names, budget)
end

---@return string
function _P.get_treesitter_symbols_text()
    local names = _P.get_treesitter_scope_names(vim.api.nvim_get_current_buf())

    if vim.tbl_isempty(names) then
        return ""
    end

    return "%#MyWinBarSymbols# "
        .. _P.escape_statusline_text(_ICONS.separator .. " " .. table.concat(names, " " .. _ICONS.separator .. " "))
end

--- Get the width available for symbols in `window`.
---
---@param window integer The window to inspect.
---@param path_text string The already-rendered path text.
---@param editor_state_text string The already-rendered editor state text.
---@return integer # The remaining visible width.
function _P.get_symbols_budget(window, path_text, editor_state_text)
    local used = _P.get_statusline_display_width(" " .. path_text .. editor_state_text .. " ")

    return math.max(vim.api.nvim_win_get_width(window) - used, 0)
end

---@param window integer
---@param path_text string
---@param editor_state_text string
---@return string
function _P.get_symbols_text(window, path_text, editor_state_text)
    local buffer = vim.api.nvim_get_current_buf()

    if _P.has_treesitter_context(buffer) then
        local treesitter_symbols = _P.get_treesitter_symbols_text()

        if treesitter_symbols ~= "" then
            return treesitter_symbols
        end

        return ""
    end

    local navic_ok, navic = pcall(require, "nvim-navic")

    if navic_ok and navic.is_available and navic.is_available() then
        local location = navic.get_location()

        if location and location ~= "" then
            return "%#MyWinBarSymbols# " .. _P.escape_statusline_text(_ICONS.separator .. " " .. location)
        end
    end

    local gps_ok, gps = pcall(require, "nvim-gps")

    if gps_ok and gps.is_available and gps.is_available() then
        local location = gps.get_location()

        if location and location ~= "" then
            return "%#MyWinBarSymbols# " .. _P.escape_statusline_text(_ICONS.separator .. " " .. location)
        end
    end

    local budget = _P.get_symbols_budget(window, path_text, editor_state_text)
    local names = _P.get_indentation_scope_names(buffer)
    local context_budget = math.max(budget - vim.fn.strdisplaywidth(" " .. _ICONS.separator .. " "), 0)
    local context = _P.format_context_names(names, context_budget)

    if context ~= "" then
        return "%#MyWinBarSymbols# " .. _P.escape_statusline_text(_ICONS.separator .. " " .. context)
    end

    return ""
end

---@return string
function _P.get_winbar()
    local window = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_get_current_buf()

    if _P.is_excluded(window, buffer) then
        return ""
    end

    local path = vim.api.nvim_buf_get_name(buffer)

    if path == "" then
        return "%#MyWinBarFileName# [No Name]"
    end

    local path_text = _P.get_path_text(path)
    local editor_state_text = _P.get_editor_state_text(buffer)

    return table.concat({
        " ",
        path_text,
        editor_state_text,
        _P.get_symbols_text(window, path_text, editor_state_text),
        " ",
    }, "")
end

_G.get_winbar = function()
    return _P.get_winbar()
end

_P.WINBAR_EXPRESSION = "%{%v:lua.get_winbar()%}"

---@param window integer?
function _P.sync_window_winbar(window)
    window = window or vim.api.nvim_get_current_win()

    if not vim.api.nvim_win_is_valid(window) then
        return
    end

    local buffer = vim.api.nvim_win_get_buf(window)

    if _P.is_excluded(window, buffer) then
        vim.wo[window].winbar = ""

        return
    end

    vim.wo[window].winbar = _P.WINBAR_EXPRESSION
end

function _P.sync_all_window_winbars()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        _P.sync_window_winbar(window)
    end
end

_P.set_highlights()

vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
        _P.set_highlights()
        _P.sync_all_window_winbars()
    end,
})

vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "BufWinEnter", "TermOpen", "FileType" }, {
    callback = function()
        _P.sync_window_winbar()
    end,
})

_P.sync_all_window_winbars()

return _P
