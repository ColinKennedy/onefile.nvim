--- A tiny aerial.nvim-like outline sidebar for the current buffer.

local M = {}

---@alias _my.aerial.SymbolKind "class" | "function" | "fallback"

---@class _my.aerial.HighlightSegment
---@field start_column integer The 0-or-more start column relative to the rendered symbol name.
---@field end_column integer The exclusive end column relative to the rendered symbol name.
---@field group string The highlight group to apply.

---@class _my.aerial.Symbol
---@field key string A stable-ish key used to remember fold state across refreshes.
---@field kind _my.aerial.SymbolKind The kind of outline item.
---@field name string The display name.
---@field line integer The 1-or-more source line where the symbol starts.
---@field column integer The 0-or-more source column where the symbol starts.
---@field end_line integer The 1-or-more source line where the symbol ends.
---@field level integer The nesting depth of this symbol.
---@field children _my.aerial.Symbol[] Nested symbols.
---@field highlights _my.aerial.HighlightSegment[] Highlight groups copied from source text.

---@class _my.aerial.Row
---@field symbol _my.aerial.Symbol The symbol rendered on this row.
---@field text string The row text.
---@field name_column integer The 0-or-more column where the symbol name starts.

---@class _my.aerial.State
---@field source_buffer integer The buffer being outlined.
---@field source_window integer The window that opened the outline.
---@field aerial_buffer integer The outline buffer.
---@field aerial_window integer The outline window.
---@field symbols _my.aerial.Symbol[] The root outline symbols.
---@field rows _my.aerial.Row[] The currently visible rows.
---@field collapsed table<string, boolean> Collapsed symbol keys.
---@field namespace integer Extmark namespace for active-row highlighting.
---@field refresh_generation integer Monotonic counter used to ignore stale debounced refreshes.
---@field refresh_timer any? Timer used to debounce source-buffer outline rebuilds.

---@class _my.aerial.SessionEntry
---@field source_name string The source buffer path whose sidebar should be restored.

local _SIDEBAR_WIDTH = 30
local _FALLBACK_HIGHLIGHT_MAX_LINES = 500
local _REFRESH_DEBOUNCE_MS = 120
local _AERIAL_FILETYPE = "aerial"
local _AERIAL_BUFFER_PREFIX = "aerial://"
---@type table<integer, _my.aerial.State>
local _STATE_BY_SOURCE_BUFFER = {}
---@type table<integer, _my.aerial.State>
local _STATE_BY_AERIAL_BUFFER = {}
---@type table<integer, integer>
local _SOURCE_BUFFER_BY_AERIAL_BUFFER = {}
local _GROUP = vim.api.nvim_create_augroup("my.aerial", { clear = true })
local _HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("my.aerial.highlight")
local _SOURCE_HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("my.aerial.source_highlight")

--- Check if `buffer` is an aerial sidebar buffer, even after `:mksession`.
---
---@param buffer integer The buffer to inspect.
---@return boolean # Whether the buffer is an aerial outline buffer.
local function _is_aerial_buffer(buffer)
    return vim.bo[buffer].filetype == _AERIAL_FILETYPE
        or vim.startswith(vim.api.nvim_buf_get_name(buffer), _AERIAL_BUFFER_PREFIX)
end

--- Stop any pending refresh timer for `state`.
---
---@param state _my.aerial.State The aerial state to mutate.
local function _stop_refresh_timer(state)
    if state.refresh_timer == nil then
        return
    end

    state.refresh_timer:stop()
    state.refresh_timer:close()
    state.refresh_timer = nil
end

local _TREESITTER_QUERIES = {
    javascript = [[
        (class_declaration
          name: (identifier) @class.name) @class.scope

        (function_declaration
          name: (identifier) @function.name) @function.scope

        (method_definition
          name: (property_identifier) @function.name) @function.scope
    ]],
    lua = [[
        (function_declaration
          name: (_) @function.name) @function.scope

        (local_function
          name: (identifier) @function.name) @function.scope
    ]],
    python = [[
        (class_definition
          name: (identifier) @class.name) @class.scope

        (function_definition
          name: (identifier) @function.name) @function.scope
    ]],
    typescript = [[
        (class_declaration
          name: (type_identifier) @class.name) @class.scope

        (function_declaration
          name: (identifier) @function.name) @function.scope

        (method_definition
          name: (property_identifier) @function.name) @function.scope
    ]],
}

---@type table<string, vim.treesitter.Query|false>
local _TREESITTER_QUERY_CACHE = {}

--- Get a line's indentation in display columns, respecting `tabstop`.
---
---@param text string The line text to inspect.
---@param tabstop integer The tab display width.
---@return integer # The indentation display width.
local function _get_indent(text, tabstop)
    local column = 0
    local index = 1

    while index <= #text do
        local byte = text:byte(index)

        if byte == 9 then
            column = column + (tabstop - (column % tabstop))
        elseif byte == 32 then
            column = column + 1
        else
            break
        end

        index = index + 1
    end

    return column
end

--- Get the first non-whitespace column in `text`.
---
---@param text string The text to inspect.
---@return integer? # The 0-or-more column, if any non-whitespace exists.
local function _get_first_nonspace_column(text)
    local index = text:find("%S")

    if index == nil then
        return nil
    end

    return index - 1
end

--- Collapse whitespace in `text` for compact outline display.
---
---@param text string The text to clean.
---@return string # The cleaned display text.
local function _clean_text(text)
    local cleaned = text:gsub("^%s*", ""):gsub("%s*$", ""):gsub("%s+", " ")

    return cleaned
end

--- Get comment prefixes that mark whole-line comments in `buffer`.
---
---@param buffer integer The source buffer.
---@return string[] # Comment prefixes to ignore in fallback outlines.
local function _get_comment_prefixes(buffer)
    local prefixes = { "#", "//", "--", "/*", "*", ";" }
    local commentstring = vim.bo[buffer].commentstring
    local comment_prefix = commentstring:match("^(.-)%%s")

    if comment_prefix then
        comment_prefix = _clean_text(comment_prefix)

        if comment_prefix ~= "" then
            table.insert(prefixes, 1, comment_prefix)
        end
    end

    return prefixes
end

--- Check if `line` is a comment-only line.
---
---@param line string The line text to inspect.
---@param prefixes string[] Comment prefixes to check.
---@return boolean # If `line` only contains a comment, return `true`.
local function _is_comment_line(line, prefixes)
    local start_column = _get_first_nonspace_column(line)

    if start_column == nil then
        return false
    end

    local trimmed = line:sub(start_column + 1)

    for _, prefix in ipairs(prefixes) do
        if trimmed:sub(1, #prefix) == prefix then
            return true
        end
    end

    return false
end

--- Get a generic class definition outline name from `line`.
---
---@param line string The source line to inspect.
---@return _my.aerial.SymbolKind? kind The detected symbol kind.
---@return string? name The compact display name.
local function _get_class_fallback_definition(line)
    local text = _clean_text(line)
    local class_name = text:match("^class%s+([%w_]+)")

    if class_name then
        return "class", "class " .. class_name
    end

    return nil, nil
end

--- Get a useful Python fallback outline name from `line`.
---
---@param line string The source line to inspect.
---@return _my.aerial.SymbolKind? kind The detected symbol kind.
---@return string? name The compact display name.
local function _get_python_fallback_definition(line)
    local class_kind, class_name = _get_class_fallback_definition(line)

    if class_kind then
        return class_kind, class_name
    end

    local text = _clean_text(line)
    local async_function_name = text:match("^async%s+def%s+([%w_]+)")

    if async_function_name then
        return "function", "async def " .. async_function_name
    end

    local function_name = text:match("^def%s+([%w_]+)")

    if function_name then
        return "function", "def " .. function_name
    end

    return nil, nil
end

--- Get a useful Lua fallback outline name from `line`.
---
---@param line string The source line to inspect.
---@return _my.aerial.SymbolKind? kind The detected symbol kind.
---@return string? name The compact display name.
local function _get_lua_fallback_definition(line)
    local class_kind, class_name = _get_class_fallback_definition(line)

    if class_kind then
        return class_kind, class_name
    end

    local text = _clean_text(line)
    local local_function_name = text:match("^local%s+function%s+([%w_%.:]+)")

    if local_function_name then
        return "function", "local function " .. local_function_name
    end

    local function_name = text:match("^function%s+([%w_%.:]+)")

    if function_name then
        return "function", "function " .. function_name
    end

    return nil, nil
end

--- Get a useful C++ fallback outline name from `line`.
---
---@param line string The source line to inspect.
---@return _my.aerial.SymbolKind? kind The detected symbol kind.
---@return string? name The compact display name.
local function _get_cpp_fallback_definition(line)
    local class_kind, class_name = _get_class_fallback_definition(line)

    if class_kind then
        return class_kind, class_name
    end

    local text = _clean_text(line)
    local first_word = text:match("^([%a_][%w_]*)")

    if first_word and vim.tbl_contains({ "if", "for", "while", "switch", "catch", "return" }, first_word) then
        return nil, nil
    end

    local function_name = text:match("^[%w_:<>~%*&%s]+%s+([~%w_:]+)%s*%(")

    if function_name then
        return "function", function_name
    end

    return nil, nil
end

--- Get a permissive fallback outline name when the source language is unknown.
---
---@param line string The source line to inspect.
---@return _my.aerial.SymbolKind? kind The detected symbol kind.
---@return string? name The compact display name.
local function _get_unknown_language_fallback_definition(line)
    local class_kind, class_name = _get_class_fallback_definition(line)

    if class_kind then
        return class_kind, class_name
    end

    local text = _clean_text(line)
    local python_function_name = text:match("^def%s+([%w_]+)")

    if python_function_name then
        return "function", "def " .. python_function_name
    end

    local async_python_function_name = text:match("^async%s+def%s+([%w_]+)")

    if async_python_function_name then
        return "function", "async def " .. async_python_function_name
    end

    local lua_function_name = text:match("^function%s+([%w_%.:]+)")

    if lua_function_name then
        return "function", "function " .. lua_function_name
    end

    return nil, nil
end

--- Check if an unknown-language buffer has any obvious definition rows.
---
---@param lines string[] The source lines to inspect.
---@param comment_prefixes string[] Comment prefixes to ignore.
---@return boolean # Whether at least one obvious definition was found.
local function _has_unknown_language_definitions(lines, comment_prefixes)
    for _, line in ipairs(lines) do
        if _get_first_nonspace_column(line) ~= nil and not _is_comment_line(line, comment_prefixes) then
            local kind = _get_unknown_language_fallback_definition(line)

            if kind ~= nil then
                return true
            end
        end
    end

    return false
end

--- Resolve the fallback language from buffer filetype or filename extension.
---
---@param buffer integer The source buffer.
---@return string? # The language to use for definition fallback, if known.
local function _get_fallback_language(buffer)
    local filetype = vim.bo[buffer].filetype

    if filetype ~= "" then
        if filetype == "python" or filetype == "lua" then
            return filetype
        elseif vim.tbl_contains({ "c", "cpp", "cc", "cxx", "h", "hpp", "hxx" }, filetype) then
            return "cpp"
        end
    end

    local extension = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer), ":e"):lower()

    if extension == "py" then
        return "python"
    elseif extension == "lua" then
        return "lua"
    elseif vim.tbl_contains({ "c", "cc", "cpp", "cxx", "h", "hh", "hpp", "hxx" }, extension) then
        return "cpp"
    end

    return nil
end

--- Get a language-aware fallback definition from `line`.
---
---@param language string The source buffer fallback language.
---@param line string The source line to inspect.
---@return _my.aerial.SymbolKind? kind The detected symbol kind.
---@return string? name The compact display name.
local function _get_language_fallback_definition(language, line)
    if language == "python" then
        return _get_python_fallback_definition(line)
    elseif language == "lua" then
        return _get_lua_fallback_definition(line)
    elseif language == "cpp" then
        return _get_cpp_fallback_definition(line)
    end

    return nil, nil
end

--- Get source highlight segments only when the buffer is small enough.
---
---@param buffer integer The source buffer.
---@param line_count integer Total source-buffer line count.
---@param line integer The 1-or-more source line.
---@param start_column integer The 0-or-more inclusive source start column.
---@param end_column integer The 0-or-more exclusive source end column.
---@return _my.aerial.HighlightSegment[] # Highlight segments, if cheap enough.
local function _get_fallback_highlight_segments(buffer, line_count, line, start_column, end_column)
    if line_count > _FALLBACK_HIGHLIGHT_MAX_LINES then
        return {}
    end

    return M.get_highlight_segments(buffer, line, start_column, end_column)
end

--- Build a stable key for an outline symbol.
---
---@param kind _my.aerial.SymbolKind The symbol kind.
---@param line integer The 1-or-more source line.
---@param name string The symbol name.
---@return string # The fold-state key.
local function _get_symbol_key(kind, line, name)
    return table.concat({ kind, tostring(line), name }, "\t")
end

--- Create an outline symbol.
---
---@param kind _my.aerial.SymbolKind The symbol kind.
---@param name string The symbol display name.
---@param line integer The 1-or-more start line.
---@param column integer The 0-or-more start column.
---@param end_line integer The 1-or-more end line.
---@param level integer The nesting depth.
---@param highlights _my.aerial.HighlightSegment[]? Highlight groups copied from source text.
---@return _my.aerial.Symbol # The created symbol.
local function _make_symbol(kind, name, line, column, end_line, level, highlights)
    return {
        children = {},
        column = column,
        end_line = end_line,
        highlights = highlights or {},
        key = _get_symbol_key(kind, line, name),
        kind = kind,
        level = level,
        line = line,
        name = name,
    }
end

--- Get the best visible highlight group at a source position.
---
---@param buffer integer The source buffer.
---@param row integer The 0-or-more source row.
---@param column integer The 0-or-more source column.
---@return string? # The highlight group at the position, if one exists.
function M.get_position_highlight_group(buffer, row, column)
    if vim.inspect_pos == nil then
        return nil
    end

    local ok, data = pcall(vim.inspect_pos, buffer, row, column)

    if not ok or data == nil then
        return nil
    end

    for index = #(data.treesitter or {}), 1, -1 do
        local item = data.treesitter[index]

        if item.hl_group ~= nil then
            return item.hl_group
        end
    end

    for index = #(data.syntax or {}), 1, -1 do
        local item = data.syntax[index]

        if item.hl_group ~= nil then
            return item.hl_group
        end
    end

    for index = #(data.extmarks or {}), 1, -1 do
        local item = data.extmarks[index]
        local group = item.opts and item.opts.hl_group

        if type(group) == "string" then
            return group
        elseif type(group) == "table" then
            return group[#group]
        end
    end

    return nil
end

--- Get contiguous highlight segments from a source text range.
---
---@param buffer integer The source buffer.
---@param line integer The 1-or-more source line.
---@param start_column integer The 0-or-more inclusive source start column.
---@param end_column integer The 0-or-more exclusive source end column.
---@return _my.aerial.HighlightSegment[] # Highlight segments relative to `start_column`.
function M.get_highlight_segments(buffer, line, start_column, end_column)
    ---@type _my.aerial.HighlightSegment[]
    local segments = {}
    ---@type string?
    local current_group = nil
    local current_start = nil

    for column = start_column, end_column - 1 do
        local group = M.get_position_highlight_group(buffer, line - 1, column)

        if group ~= current_group then
            if current_group ~= nil and current_start ~= nil then
                table.insert(segments, {
                    end_column = column - start_column,
                    group = current_group,
                    start_column = current_start - start_column,
                })
            end

            current_group = group
            current_start = column
        end
    end

    if current_group ~= nil and current_start ~= nil then
        table.insert(segments, {
            end_column = end_column - start_column,
            group = current_group,
            start_column = current_start - start_column,
        })
    end

    return segments
end

--- Convert a source filetype to a Tree-sitter language.
---
---@param filetype string The source filetype.
---@return string # The Tree-sitter language name.
local function _get_language(filetype)
    local core_helpers = require("modules.utilities.core_helpers")

    return core_helpers._FILETYPE_TO_TREESITTER[filetype] or filetype
end

--- Check whether `buffer` can use a Tree-sitter parser for `language`.
---
---@param buffer integer The source buffer.
---@param language string The Tree-sitter language.
---@return boolean # Whether parsing should be attempted.
local function _has_treesitter_parser(buffer, language)
    if language == "" then
        return false
    end

    local ok, parser = pcall(vim.treesitter.get_parser, buffer, language)

    return ok and parser ~= nil
end

--- Get this module's Tree-sitter query for `language`.
---
---@param language string The Tree-sitter language.
---@return vim.treesitter.Query? # The parsed query, if supported.
local function _get_treesitter_query(language)
    if _TREESITTER_QUERY_CACHE[language] ~= nil then
        local cached = _TREESITTER_QUERY_CACHE[language]

        if cached == false then
            return nil
        end

        return cached
    end

    local query_text = _TREESITTER_QUERIES[language]

    if query_text == nil then
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

--- Get the first node captured as `capture_name`.
---
---@param match table<integer, TSNode[]|TSNode> Tree-sitter match data.
---@param query vim.treesitter.Query The query that produced `match`.
---@param capture_name string The capture name to find.
---@return TSNode? # The matched node, if any.
local function _get_capture_node(match, query, capture_name)
    for id, nodes in pairs(match) do
        if query.captures[id] == capture_name then
            if type(nodes) == "table" then
                return nodes[1]
            end

            return nodes
        end
    end

    return nil
end

--- Get a capture node's cleaned source text.
---
---@param node TSNode The node to read.
---@param buffer integer The source buffer.
---@return string # The cleaned node text.
local function _get_node_text(node, buffer)
    return _clean_text(vim.treesitter.get_node_text(node, buffer))
end

--- Sort symbols by source range.
---
---@param left _my.aerial.Symbol The left symbol.
---@param right _my.aerial.Symbol The right symbol.
---@return boolean # Whether `left` should sort before `right`.
local function _sort_symbols(left, right)
    if left.line ~= right.line then
        return left.line < right.line
    end

    if left.column ~= right.column then
        return left.column < right.column
    end

    return left.end_line > right.end_line
end

--- Check whether `parent` contains `child`.
---
---@param parent _my.aerial.Symbol The possible parent symbol.
---@param child _my.aerial.Symbol The possible child symbol.
---@return boolean # Whether `child` is nested inside `parent`.
local function _contains_symbol(parent, child)
    return parent.line <= child.line and parent.end_line >= child.end_line and parent.key ~= child.key
end

--- Convert flat symbols into a nested tree.
---
---@param symbols _my.aerial.Symbol[] Flat source-ordered symbols.
---@return _my.aerial.Symbol[] # Root symbols with children assigned.
function M.nest_symbols(symbols)
    table.sort(symbols, _sort_symbols)

    ---@type _my.aerial.Symbol[]
    local roots = {}
    ---@type _my.aerial.Symbol[]
    local stack = {}

    for _, symbol in ipairs(symbols) do
        ---@type _my.aerial.Symbol[]
        symbol.children = {}

        while #stack > 0 and not _contains_symbol(stack[#stack], symbol) do
            table.remove(stack)
        end

        symbol.level = #stack

        if #stack == 0 then
            table.insert(roots, symbol)
        else
            table.insert(stack[#stack].children, symbol)
        end

        table.insert(stack, symbol)
    end

    return roots
end

--- Build outline symbols from Tree-sitter, if available.
---
---@param buffer integer The source buffer.
---@return _my.aerial.Symbol[]? # Root symbols, or `nil` if Tree-sitter cannot be used.
function M.get_treesitter_symbols(buffer)
    local language = _get_language(vim.bo[buffer].filetype)
    local query = _get_treesitter_query(language)

    if query == nil or not _has_treesitter_parser(buffer, language) then
        return nil
    end

    local parser_ok, parser = pcall(vim.treesitter.get_parser, buffer, language)

    if not parser_ok or parser == nil then
        return nil
    end

    ---@cast parser vim.treesitter.LanguageTree
    local parse_ok, trees = pcall(function()
        return parser:parse()
    end)

    if not parse_ok or trees == nil or trees[1] == nil then
        return nil
    end

    ---@type _my.aerial.Symbol[]
    local symbols = {}

    for _, match, _ in query:iter_matches(trees[1]:root(), buffer, 0, -1) do
        for _, kind in ipairs({ "class", "function" }) do
            local scope = _get_capture_node(match, query, kind .. ".scope")
            local name = _get_capture_node(match, query, kind .. ".name")

            if scope ~= nil and name ~= nil then
                local start_row, start_column, end_row, _ = scope:range()
                local name_start_row, name_start_column, name_end_row, name_end_column = name:range()
                local text = _get_node_text(name, buffer)
                ---@type _my.aerial.HighlightSegment[]
                local highlights = {}

                if text ~= "" then
                    if name_start_row == name_end_row then
                        highlights =
                            M.get_highlight_segments(buffer, name_start_row + 1, name_start_column, name_end_column)
                    end

                    table.insert(
                        symbols,
                        _make_symbol(kind, text, start_row + 1, start_column, end_row + 1, 0, highlights)
                    )
                end
            end
        end
    end

    return M.nest_symbols(symbols)
end

--- Build indentation fallback symbols.
---
---@param buffer integer The source buffer.
---@return _my.aerial.Symbol[] # Root fallback symbols.
function M.get_indentation_symbols(buffer)
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    local line_count = #lines
    local tabstop = vim.bo[buffer].tabstop
    local fallback_language = _get_fallback_language(buffer)
    local comment_prefixes = _get_comment_prefixes(buffer)
    local use_unknown_language_definitions = fallback_language == nil
        and _has_unknown_language_definitions(lines, comment_prefixes)
    local use_language_definitions = fallback_language ~= nil or use_unknown_language_definitions
    local previous_indent = nil
    local blank_since_previous = true
    ---@type {indent: integer, symbol: _my.aerial.Symbol}[]
    local stack = {}
    ---@type _my.aerial.Symbol[]
    local roots = {}

    for index, line in ipairs(lines) do
        local start_column = _get_first_nonspace_column(line)

        if start_column == nil then
            blank_since_previous = true
        elseif not _is_comment_line(line, comment_prefixes) then
            local indent = _get_indent(line, tabstop)
            ---@type _my.aerial.SymbolKind?
            local kind = "fallback"
            ---@type string?
            local name = _clean_text(line)

            if fallback_language ~= nil then
                kind, name = _get_language_fallback_definition(assert(fallback_language), line)

                if kind == nil or name == nil then
                    goto continue
                end
            elseif use_unknown_language_definitions then
                kind, name = _get_unknown_language_fallback_definition(line)

                if kind == nil or name == nil then
                    goto continue
                end
            end

            local should_create = use_language_definitions
                or previous_indent == nil
                or indent ~= previous_indent
                or blank_since_previous

            if should_create then
                while #stack > 0 and stack[#stack].indent >= indent do
                    table.remove(stack)
                end

                local symbol_kind = assert(kind)
                local symbol_name = assert(name)
                local symbol = _make_symbol(
                    symbol_kind,
                    symbol_name,
                    index,
                    0,
                    line_count,
                    #stack,
                    _get_fallback_highlight_segments(
                        buffer,
                        line_count,
                        index,
                        start_column,
                        start_column + #symbol_name
                    )
                )

                if #stack == 0 then
                    table.insert(roots, symbol)
                else
                    table.insert(stack[#stack].symbol.children, symbol)
                end

                table.insert(stack, { indent = indent, symbol = symbol })
            end

            previous_indent = indent
            blank_since_previous = false
        end

        ::continue::
    end

    return roots
end

--- Get all outline symbols for `buffer`.
---
---@param buffer integer The source buffer.
---@return _my.aerial.Symbol[] # Root outline symbols.
function M.get_symbols(buffer)
    return M.get_treesitter_symbols(buffer) or M.get_indentation_symbols(buffer)
end

--- Get the visible prefix for a symbol kind.
---
---@param kind _my.aerial.SymbolKind The symbol kind.
---@return string # The kind prefix.
local function _get_kind_prefix(kind)
    local fonts = require("modules.utilities.fonts")

    if kind == "class" then
        return fonts.get_icon(fonts.Icon.aerial_class)
    end

    if kind == "function" then
        return fonts.get_icon(fonts.Icon.aerial_function)
    end

    return fonts.get_icon(fonts.Icon.aerial_fallback)
end

--- Render a single symbol into aerial row text.
---
---@param symbol _my.aerial.Symbol The symbol to render.
---@param collapsed table<string, boolean> Collapsed symbol keys.
---@return string # The rendered row text.
---@return integer # The 0-or-more column where the symbol name starts.
local function _render_symbol_text(symbol, collapsed)
    local icon = "  "

    if #symbol.children > 0 and collapsed[symbol.key] then
        icon = "> "
    end

    local prefix = string.rep("  ", symbol.level) .. icon .. _get_kind_prefix(symbol.kind) .. " "

    return prefix .. symbol.name, #prefix
end

--- Flatten symbols into visible rows.
---
---@param symbols _my.aerial.Symbol[] The symbols to render.
---@param collapsed table<string, boolean> Collapsed symbol keys.
---@return _my.aerial.Row[] # Visible rows.
function M.get_rows(symbols, collapsed)
    ---@type _my.aerial.Row[]
    local rows = {}

    --- Add `symbol` and its visible descendants.
    ---
    ---@param symbol _my.aerial.Symbol The symbol to add.
    local function _add_symbol(symbol)
        local text, name_column = _render_symbol_text(symbol, collapsed)

        table.insert(rows, { name_column = name_column, symbol = symbol, text = text })

        if not collapsed[symbol.key] then
            for _, child in ipairs(symbol.children) do
                _add_symbol(child)
            end
        end
    end

    for _, symbol in ipairs(symbols) do
        _add_symbol(symbol)
    end

    return rows
end

--- Find the deepest symbol containing `line`.
---
---@param symbols _my.aerial.Symbol[] The symbols to search.
---@param line integer The 1-or-more source line.
---@return _my.aerial.Symbol? # The containing symbol, if any.
function M.find_symbol_at_line(symbols, line)
    ---@type _my.aerial.Symbol?
    local found = nil

    --- Search `symbol` and its children.
    ---
    ---@param symbol _my.aerial.Symbol The symbol to inspect.
    local function _search(symbol)
        if symbol.line <= line and symbol.end_line >= line then
            found = symbol

            for _, child in ipairs(symbol.children) do
                _search(child)
            end
        end
    end

    for _, symbol in ipairs(symbols) do
        _search(symbol)
    end

    return found
end

--- Find the rendered row for `symbol`.
---
---@param rows _my.aerial.Row[] Rendered rows.
---@param symbol _my.aerial.Symbol? The active source symbol.
---@return integer? # The 1-or-more aerial row.
local function _find_row_for_symbol(rows, symbol)
    if symbol == nil then
        return nil
    end

    for index, row in ipairs(rows) do
        if row.symbol.key == symbol.key then
            return index
        end
    end

    return nil
end

--- Get the active state for the current aerial buffer.
---
---@return _my.aerial.State? # The active state, if any.
local function _get_current_aerial_state()
    local aerial_buffer = vim.api.nvim_get_current_buf()
    local state = _STATE_BY_AERIAL_BUFFER[aerial_buffer]

    if state ~= nil then
        return state
    end

    local source_buffer = vim.b[aerial_buffer].aerial_source_buffer

    if type(source_buffer) == "number" then
        return _STATE_BY_SOURCE_BUFFER[source_buffer]
    end

    return nil
end

--- Get the source window for the current aerial buffer.
---
---@return integer? # The source window, if the current buffer is an aerial buffer.
function M.get_current_source_window()
    local state = _get_current_aerial_state()

    if state == nil or not vim.api.nvim_win_is_valid(state.source_window) then
        return nil
    end

    return state.source_window
end

--- Set the contents of an aerial buffer.
---
---@param state _my.aerial.State The state to render.
local function _set_aerial_lines(state)
    ---@type string[]
    local lines = {}

    for _, row in ipairs(state.rows) do
        table.insert(lines, row.text)
    end

    vim.bo[state.aerial_buffer].modifiable = true
    vim.api.nvim_buf_set_lines(state.aerial_buffer, 0, -1, false, lines)
    vim.bo[state.aerial_buffer].modifiable = false
    vim.api.nvim_buf_clear_namespace(state.aerial_buffer, _SOURCE_HIGHLIGHT_NAMESPACE, 0, -1)

    for row_index, row in ipairs(state.rows) do
        for _, segment in ipairs(row.symbol.highlights or {}) do
            local end_column = row.name_column + math.min(segment.end_column, #row.symbol.name)

            if end_column <= row.name_column + segment.start_column then
                end_column = row.name_column + segment.start_column + 1
            end

            vim.api.nvim_buf_set_extmark(
                state.aerial_buffer,
                _SOURCE_HIGHLIGHT_NAMESPACE,
                row_index - 1,
                row.name_column + segment.start_column,
                {
                    end_col = end_column,
                    hl_group = segment.group,
                }
            )
        end
    end
end

--- Highlight the row that contains the source cursor.
---
---@param state _my.aerial.State The state to update.
---@param move_aerial_cursor boolean? If true, move the aerial cursor to the active row.
function M.update_active_row(state, move_aerial_cursor)
    if not vim.api.nvim_win_is_valid(state.source_window) or not vim.api.nvim_buf_is_valid(state.aerial_buffer) then
        return
    end

    vim.api.nvim_buf_clear_namespace(state.aerial_buffer, state.namespace, 0, -1)

    local line = vim.api.nvim_win_get_cursor(state.source_window)[1]
    local symbol = M.find_symbol_at_line(state.symbols, line)
    local row = _find_row_for_symbol(state.rows, symbol)

    if row == nil then
        return
    end

    vim.api.nvim_buf_set_extmark(state.aerial_buffer, state.namespace, row - 1, 0, {
        hl_group = "Visual",
        line_hl_group = "Visual",
    })

    if move_aerial_cursor ~= false and vim.api.nvim_win_is_valid(state.aerial_window) then
        pcall(vim.api.nvim_win_set_cursor, state.aerial_window, { row, 0 })
    end
end

--- Refresh one source buffer's outline.
---
---@param source_buffer integer The source buffer to refresh.
function M.refresh_source_buffer(source_buffer)
    local state = _STATE_BY_SOURCE_BUFFER[source_buffer]

    if state == nil or not vim.api.nvim_buf_is_valid(state.aerial_buffer) then
        return
    end

    _stop_refresh_timer(state)
    state.symbols = M.get_symbols(source_buffer)
    state.rows = M.get_rows(state.symbols, state.collapsed)
    _set_aerial_lines(state)
    M.update_active_row(state)
end

--- Debounce an outline refresh for a changed source buffer.
---
---@param source_buffer integer The source buffer to refresh later.
function M.schedule_refresh_source_buffer(source_buffer)
    local state = _STATE_BY_SOURCE_BUFFER[source_buffer]

    if state == nil or not vim.api.nvim_buf_is_valid(state.aerial_buffer) then
        return
    end

    state.refresh_generation = state.refresh_generation + 1

    local generation = state.refresh_generation

    if state.refresh_timer == nil then
        state.refresh_timer = assert(vim.uv.new_timer())
    else
        state.refresh_timer:stop()
    end

    state.refresh_timer:start(_REFRESH_DEBOUNCE_MS, 0, function()
        vim.schedule(function()
            local current = _STATE_BY_SOURCE_BUFFER[source_buffer]

            if current == nil or current ~= state or current.refresh_generation ~= generation then
                return
            end

            M.refresh_source_buffer(source_buffer)
        end)
    end)
end

--- Create a configured aerial buffer.
---
---@param source_buffer integer The buffer being outlined.
---@return integer # The created aerial buffer.
local function _create_aerial_buffer(source_buffer)
    local buffer = vim.api.nvim_create_buf(false, true)
    local source_name = vim.api.nvim_buf_get_name(source_buffer)

    require("modules.utilities.core_helpers").with_file_messages_suppressed(function()
        vim.api.nvim_buf_set_name(buffer, _AERIAL_BUFFER_PREFIX .. (source_name ~= "" and source_name or "[No Name]"))
    end)
    vim.bo[buffer].buftype = "nofile"
    vim.bo[buffer].bufhidden = "wipe"
    vim.bo[buffer].filetype = _AERIAL_FILETYPE
    vim.bo[buffer].modifiable = false
    vim.bo[buffer].swapfile = false

    return buffer
end

--- Rename the aerial buffer for a new source buffer.
---
---@param aerial_buffer integer The aerial buffer to rename.
---@param source_buffer integer The source buffer being outlined.
local function _rename_aerial_buffer(aerial_buffer, source_buffer)
    local source_name = vim.api.nvim_buf_get_name(source_buffer)
    local name = _AERIAL_BUFFER_PREFIX .. (source_name ~= "" and source_name or "[No Name]")

    require("modules.utilities.core_helpers").with_file_messages_suppressed(function()
        pcall(vim.api.nvim_buf_set_name, aerial_buffer, name)
    end)
end

--- Open the right-side aerial split.
---
---@param state _my.aerial.State The state to display.
local function _open_aerial_window(state)
    local source_window = state.source_window

    vim.api.nvim_set_current_win(source_window)
    require("modules.utilities.core_helpers").with_file_messages_suppressed(function()
        vim.cmd("botright " .. tostring(_SIDEBAR_WIDTH) .. "vsplit")
        vim.api.nvim_win_set_buf(0, state.aerial_buffer)
    end)
    state.aerial_window = vim.api.nvim_get_current_win()
    vim.wo[state.aerial_window].winfixbuf = true
    vim.wo[state.aerial_window].number = false
    vim.wo[state.aerial_window].relativenumber = false
    vim.wo[state.aerial_window].signcolumn = "no"
    vim.wo[state.aerial_window].foldcolumn = "0"
    vim.api.nvim_win_set_width(state.aerial_window, _SIDEBAR_WIDTH)
end

--- Close one aerial state.
---
---@param state _my.aerial.State The state to close.
function M.close_state(state)
    _stop_refresh_timer(state)

    if vim.api.nvim_win_is_valid(state.aerial_window) then
        vim.api.nvim_win_close(state.aerial_window, true)
    end

    _SOURCE_BUFFER_BY_AERIAL_BUFFER[state.aerial_buffer] = nil
    _STATE_BY_AERIAL_BUFFER[state.aerial_buffer] = nil
    _STATE_BY_SOURCE_BUFFER[state.source_buffer] = nil
end

--- Close every open aerial state.
function M.close_all()
    ---@type _my.aerial.State[]
    local states = {}

    for _, state in pairs(_STATE_BY_AERIAL_BUFFER) do
        table.insert(states, state)
    end

    for _, state in ipairs(states) do
        M.close_state(state)
    end
end

--- Make an existing aerial state follow a new source buffer.
---
---@param state _my.aerial.State The state to reassign.
---@param source_buffer integer The new source buffer to outline.
function M.follow_source_buffer(state, source_buffer)
    if source_buffer == state.source_buffer or vim.bo[source_buffer].filetype == _AERIAL_FILETYPE then
        return
    end

    local existing = _STATE_BY_SOURCE_BUFFER[source_buffer]

    if existing ~= nil and existing ~= state then
        M.close_state(existing)
    end

    _STATE_BY_SOURCE_BUFFER[state.source_buffer] = nil
    state.source_buffer = source_buffer
    ---@type table<string, boolean>
    state.collapsed = {}
    _STATE_BY_SOURCE_BUFFER[source_buffer] = state
    _SOURCE_BUFFER_BY_AERIAL_BUFFER[state.aerial_buffer] = source_buffer
    vim.b[state.aerial_buffer].aerial_source_buffer = source_buffer
    _rename_aerial_buffer(state.aerial_buffer, source_buffer)
    M.refresh_source_buffer(source_buffer)
end

--- Open the aerial sidebar for a source window.
---
---@param source_window integer The source window to outline.
---@param focus_aerial boolean? If false, restore the previously-current window after opening.
function M.open_for_window(source_window, focus_aerial)
    if not vim.api.nvim_win_is_valid(source_window) then
        return
    end

    local previous_window = vim.api.nvim_get_current_win()
    local source_buffer = vim.api.nvim_win_get_buf(source_window)
    local aerial_buffer = _create_aerial_buffer(source_buffer)
    ---@type _my.aerial.State
    local state = {
        aerial_buffer = aerial_buffer,
        aerial_window = -1,
        collapsed = {},
        namespace = _HIGHLIGHT_NAMESPACE,
        refresh_generation = 0,
        refresh_timer = nil,
        rows = {},
        source_buffer = source_buffer,
        source_window = source_window,
        symbols = {},
    }

    _STATE_BY_SOURCE_BUFFER[source_buffer] = state
    _STATE_BY_AERIAL_BUFFER[aerial_buffer] = state
    _SOURCE_BUFFER_BY_AERIAL_BUFFER[aerial_buffer] = source_buffer
    vim.b[aerial_buffer].aerial_source_buffer = source_buffer
    _open_aerial_window(state)
    state.source_window = source_window
    M.refresh_source_buffer(source_buffer)

    if focus_aerial == false and vim.api.nvim_win_is_valid(previous_window) then
        vim.api.nvim_set_current_win(previous_window)
    end
end

--- Open the aerial sidebar for the current buffer.
function M.open()
    M.open_for_window(vim.api.nvim_get_current_win(), true)
end

--- Toggle the aerial sidebar for the current source buffer.
function M.toggle()
    local current_aerial_state = _get_current_aerial_state()

    if current_aerial_state ~= nil then
        M.close_state(current_aerial_state)

        return
    end

    local state = _STATE_BY_SOURCE_BUFFER[vim.api.nvim_get_current_buf()]

    if state ~= nil then
        M.close_state(state)

        return
    end

    M.open()
end

--- Jump the source window to the selected aerial row.
---
---@param keep_aerial_focus boolean If true, keep the cursor in aerial after jumping.
function M.jump_to_selected(keep_aerial_focus)
    local state = _get_current_aerial_state()
    local aerial_window = vim.api.nvim_get_current_win()

    if state == nil or not vim.api.nvim_win_is_valid(state.source_window) then
        return
    end

    local row_number = vim.api.nvim_win_get_cursor(0)[1]
    local row = state.rows[row_number]

    if row == nil then
        return
    end

    vim.api.nvim_win_call(state.source_window, function()
        vim.api.nvim_win_set_cursor(state.source_window, { row.symbol.line, row.symbol.column })
    end)

    if not keep_aerial_focus then
        vim.api.nvim_set_current_win(state.source_window)
    elseif vim.api.nvim_win_is_valid(aerial_window) then
        vim.api.nvim_set_current_win(aerial_window)
    end

    M.update_active_row(state)
end

--- Collapse the selected aerial row, if it has children.
function M.collapse_selected()
    local state = _get_current_aerial_state()

    if state == nil then
        return
    end

    local row = state.rows[vim.api.nvim_win_get_cursor(0)[1]]

    if row == nil or #row.symbol.children == 0 then
        return
    end

    state.collapsed[row.symbol.key] = true
    state.rows = M.get_rows(state.symbols, state.collapsed)
    _set_aerial_lines(state)
    M.update_active_row(state, false)
end

--- Remove collapsed state for `symbol` and its descendants.
---
---@param collapsed table<string, boolean> The collapsed lookup to mutate.
---@param symbol _my.aerial.Symbol The symbol subtree to expand.
local function _expand_symbol_recursive(collapsed, symbol)
    collapsed[symbol.key] = nil

    for _, child in ipairs(symbol.children) do
        _expand_symbol_recursive(collapsed, child)
    end
end

--- Expand the selected aerial row recursively.
function M.expand_selected()
    local state = _get_current_aerial_state()

    if state == nil then
        return
    end

    local row = state.rows[vim.api.nvim_win_get_cursor(0)[1]]

    if row == nil then
        return
    end

    _expand_symbol_recursive(state.collapsed, row.symbol)
    state.rows = M.get_rows(state.symbols, state.collapsed)
    _set_aerial_lines(state)
    M.update_active_row(state, false)
end

--- Refresh every open aerial window for a source buffer, if needed.
---
---@param buffer integer The source buffer that changed.
local function _refresh_if_open(buffer)
    if _STATE_BY_SOURCE_BUFFER[buffer] ~= nil then
        M.schedule_refresh_source_buffer(buffer)
    end
end

--- Check if `window` can be treated as a normal source-code window.
---
---@param window integer The window to inspect.
---@return boolean # If this is a regular, non-floating window, return `true`.
local function _is_regular_source_window(window)
    return vim.api.nvim_win_is_valid(window) and vim.api.nvim_win_get_config(window).relative == ""
end

--- Update active-row highlighting for the current source window.
local function _sync_current_source_window()
    local window = vim.api.nvim_get_current_win()

    if not _is_regular_source_window(window) then
        return
    end

    local buffer = vim.api.nvim_win_get_buf(window)
    local state = _STATE_BY_SOURCE_BUFFER[buffer]

    if vim.bo[buffer].filetype == _AERIAL_FILETYPE then
        return
    end

    if state == nil then
        for _, candidate in pairs(_STATE_BY_AERIAL_BUFFER) do
            if candidate.source_window == window then
                state = candidate
                M.follow_source_buffer(state, buffer)

                return
            end
        end

        return
    end

    state.source_window = window
    M.update_active_row(state)
end

--- Get aerial sidebars that should survive a session write.
---
---@return _my.aerial.SessionEntry[] # Restorable sidebars keyed by source file path.
function M.get_session_entries()
    ---@type _my.aerial.SessionEntry[]
    local entries = {}
    ---@type table<string, boolean>
    local seen = {}

    for _, state in pairs(_STATE_BY_AERIAL_BUFFER) do
        if vim.api.nvim_buf_is_valid(state.source_buffer) and vim.api.nvim_win_is_valid(state.aerial_window) then
            local source_name = vim.api.nvim_buf_get_name(state.source_buffer)

            if source_name ~= "" and not seen[source_name] then
                table.insert(entries, { source_name = source_name })
                seen[source_name] = true
            end
        end
    end

    table.sort(entries, function(left, right)
        return left.source_name < right.source_name
    end)

    return entries
end

--- Find a visible regular window showing `source_name`.
---
---@param source_name string The source buffer path to find.
---@return integer? # The matching window, if visible.
local function _find_visible_source_window(source_name)
    local target = vim.fn.fnamemodify(source_name, ":p")

    for _, window in ipairs(vim.api.nvim_list_wins()) do
        if _is_regular_source_window(window) then
            local buffer = vim.api.nvim_win_get_buf(window)

            if not _is_aerial_buffer(buffer) then
                local candidate = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer), ":p")

                if candidate == target then
                    return window
                end
            end
        end
    end

    return nil
end

--- Close stale aerial windows restored by `:mksession`.
local function _close_visible_aerial_windows()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)

        if _is_aerial_buffer(buffer) then
            pcall(vim.api.nvim_win_close, window, true)
            pcall(vim.api.nvim_buf_delete, buffer, { force = true })
        end
    end
end

--- Get stale aerial session entries from windows restored by `:mksession`.
---
---@return _my.aerial.SessionEntry[] # Restorable sidebars found in visible stale aerial buffers.
function M.get_stale_session_entries()
    ---@type _my.aerial.SessionEntry[]
    local entries = {}
    ---@type table<string, boolean>
    local seen = {}

    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)
        local name = vim.api.nvim_buf_get_name(buffer)

        if vim.bo[buffer].filetype ~= _AERIAL_FILETYPE and vim.startswith(name, _AERIAL_BUFFER_PREFIX) then
            local source_name = name:sub(#_AERIAL_BUFFER_PREFIX + 1)

            if source_name ~= "" and not seen[source_name] then
                table.insert(entries, { source_name = source_name })
                seen[source_name] = true
            end
        end
    end

    table.sort(entries, function(left, right)
        return left.source_name < right.source_name
    end)

    return entries
end

--- Reopen aerial sidebars after a session has restored source windows.
---
---@param entries _my.aerial.SessionEntry[] The session sidebars to restore.
function M.restore_session(entries)
    local previous_window = vim.api.nvim_get_current_win()

    _close_visible_aerial_windows()

    for _, entry in ipairs(entries) do
        if type(entry.source_name) == "string" then
            local source_window = _find_visible_source_window(entry.source_name)

            if source_window ~= nil then
                local source_buffer = vim.api.nvim_win_get_buf(source_window)
                local state = _STATE_BY_SOURCE_BUFFER[source_buffer]

                if state == nil then
                    M.open_for_window(source_window, false)
                else
                    state.source_window = source_window

                    if not vim.api.nvim_win_is_valid(state.aerial_window) then
                        _open_aerial_window(state)
                    end

                    M.refresh_source_buffer(source_buffer)
                end
            end
        end
    end

    if vim.api.nvim_win_is_valid(previous_window) then
        vim.api.nvim_set_current_win(previous_window)
    end
end

--- Reopen sidebars from stale `aerial://` windows created by `:mksession`.
function M.restore_stale_session_windows()
    local entries = M.get_stale_session_entries()

    if #entries == 0 then
        return
    end

    M.restore_session(entries)
end

--- Serialize the current aerial sidebars as Lua session restore code.
---
---@return string # Lua code to restore aerial sidebars after a session load.
function M.serialize_session_restore()
    local entries = M.get_session_entries()

    if #entries == 0 then
        return ""
    end

    return 'require("modules.plugins.aerial").restore_session(' .. vim.inspect(entries) .. ")"
end

--- Define highlights, keymaps, and autocommands.
function M.setup()
    vim.api.nvim_set_hl(0, "AerialClass", { default = true, link = "Type" })
    vim.api.nvim_set_hl(0, "AerialFunction", { default = true, link = "Function" })

    vim.keymap.set("n", "<Space>SS", M.toggle, { desc = "Toggle the current buffer outline sidebar." })

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinEnter", "BufEnter" }, {
        group = _GROUP,
        desc = "Update the active aerial row for the current source cursor.",
        callback = _sync_current_source_window,
    })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = _GROUP,
        desc = "Refresh an open aerial outline after source edits.",
        callback = function(event)
            _refresh_if_open(event.buf)
        end,
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
        group = _GROUP,
        desc = "Forget aerial state for deleted buffers.",
        callback = function(event)
            local source_buffer = _SOURCE_BUFFER_BY_AERIAL_BUFFER[event.buf]

            if source_buffer ~= nil then
                local state = _STATE_BY_AERIAL_BUFFER[event.buf]

                if state ~= nil then
                    _stop_refresh_timer(state)
                end

                _SOURCE_BUFFER_BY_AERIAL_BUFFER[event.buf] = nil
                _STATE_BY_AERIAL_BUFFER[event.buf] = nil
                _STATE_BY_SOURCE_BUFFER[source_buffer] = nil

                return
            end

            local state = _STATE_BY_SOURCE_BUFFER[event.buf]

            if state ~= nil then
                _stop_refresh_timer(state)
                _SOURCE_BUFFER_BY_AERIAL_BUFFER[state.aerial_buffer] = nil
                _STATE_BY_AERIAL_BUFFER[state.aerial_buffer] = nil
                _STATE_BY_SOURCE_BUFFER[event.buf] = nil
            end
        end,
    })

    local core_editor_setup = require("modules.features.core_editor_setup")

    core_editor_setup._SESSION_MANAGER:register_session_write_pre_callback(".aerial.lua", function()
        local code = M.serialize_session_restore()

        if code == "" then
            return ""
        end

        return code
    end)

    vim.api.nvim_create_autocmd("SessionLoadPost", {
        group = _GROUP,
        desc = "Restore aerial sidebars from session-created buffers.",
        callback = function()
            vim.schedule(M.restore_stale_session_windows)
        end,
    })

    vim.api.nvim_create_autocmd("VimEnter", {
        group = _GROUP,
        desc = "Restore aerial sidebars after startup session loading.",
        callback = function()
            if vim.v.this_session ~= "" then
                vim.schedule(M.restore_stale_session_windows)
            end
        end,
    })

    vim.api.nvim_create_autocmd("FileType", {
        group = _GROUP,
        pattern = _AERIAL_FILETYPE,
        desc = "Configure aerial buffer mappings.",
        callback = function(event)
            local options = { buffer = event.buf }

            vim.keymap.set("n", "<CR>", function()
                M.jump_to_selected(false)
            end, vim.tbl_extend("force", options, { desc = "Jump to the selected outline item." }))
            vim.keymap.set("n", "<Space>", function()
                M.jump_to_selected(true)
            end, vim.tbl_extend("force", options, { desc = "Preview the selected outline item." }))
            vim.keymap.set(
                "n",
                "h",
                M.collapse_selected,
                vim.tbl_extend("force", options, {
                    desc = "Collapse the selected outline item.",
                })
            )
            vim.keymap.set(
                "n",
                "l",
                M.expand_selected,
                vim.tbl_extend("force", options, {
                    desc = "Expand the selected outline item.",
                })
            )
        end,
    })
end

M.setup()

return M
