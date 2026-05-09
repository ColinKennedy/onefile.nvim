--- Highlight tagged inline comments such as TODO, NOTE, and FIXME without plugins.
---
--- Inspired by https://github.com/folke/todo-comments.nvim.

local M = {}

---@class _my.comment.HighlightGroup
---@field tag_highlight_name string The highlight group for the tag text.
---@field tag_padding_highlight_name string The solid-color group around the tag.
---@field text_highlight_name string The highlight group for comment text.

---@class _my.comment.TagMatch
---@field tag string The matched tag.
---@field highlight_groups _my.comment.HighlightGroup The groups to apply.
---@field comment_start_column integer The 0-or-more column where comment text begins.
---@field tag_start_column integer The 0-or-more tag start column.
---@field tag_end_column integer The exclusive tag end column.
---@field block_end_column integer The exclusive solid-color tag block end column.
---@field text_start_column integer The 0-or-more column where post-tag text starts.

---@class _my.comment.CommentLine
---@field text string The comment text after the comment prefix.
---@field comment_start_column integer The 0-or-more column where comment text begins.

---@type table<string, {canonical: string, color: string}>
local _TAG_DETAILS = {
    BUG = { canonical = "FIX", color = "error" },
    FIX = { canonical = "FIX", color = "error" },
    FIXME = { canonical = "FIX", color = "error" },
    FIXIT = { canonical = "FIX", color = "error" },
    IMPORTANT = { canonical = "FIX", color = "error" },
    ISSUE = { canonical = "FIX", color = "error" },
    HACK = { canonical = "HACK", color = "warning" },
    WARNING = { canonical = "WARNING", color = "warning" },
    WARN = { canonical = "WARNING", color = "warning" },
    XXX = { canonical = "WARNING", color = "warning" },
    NOTE = { canonical = "NOTE", color = "default" },
    PERF = { canonical = "PERF", color = "default" },
    PERFORMANCE = { canonical = "PERF", color = "default" },
    OPTIM = { canonical = "PERF", color = "default" },
    OPTIMIZE = { canonical = "PERF", color = "default" },
    TODO = { canonical = "TODO", color = "info" },
}

---@type table<string, string[]>
local _COLOR_LINKS = {
    default = { "Comment", "NonText", "#B8BCC8" },
    error = { "DiagnosticError", "ErrorMsg", "#DC2626" },
    info = { string.format("#%06x", vim.api.nvim_get_hl(0, { name = "TermCursor" }).bg) },
    warning = { "DiagnosticWarn", "WarningMsg", "#FBBF24" },
}

local _COMMENT_HIGHLIGHT = vim.api.nvim_create_namespace("my.comment.highlighter")
local _DEBOUNCE_MS = 120
---@type table<integer, any>
local _TIMER_BY_BUFFER = {}
---@type table<integer, integer>
local _UPDATE_GENERATION_BY_BUFFER = {}

--- Get this module's extmark namespace.
---
---@return integer # The namespace id.
function M.get_namespace()
    return _COMMENT_HIGHLIGHT
end

--- Get a highlight color from existing groups before falling back to hex.
---
---@param color string A key in `_COLOR_LINKS`.
---@return integer|string # The resolved color.
local function _get_color(color)
    for _, candidate in ipairs(_COLOR_LINKS[color] or _COLOR_LINKS.default) do
        if candidate:sub(1, 1) == "#" then
            return candidate
        end

        local ok, highlight = pcall(vim.api.nvim_get_hl, 0, { name = candidate })

        if ok and highlight.fg ~= nil then
            return highlight.fg
        end
    end

    return "#B8BCC8"
end

--- Get the Normal background color.
---
---@return integer|string # The normal background, or black.
local function _get_normal_background()
    local ok, highlight = pcall(vim.api.nvim_get_hl, 0, { name = "Normal" })

    if ok and highlight.bg ~= nil then
        return highlight.bg
    end

    return "#000000"
end

--- Get a canonical tag highlight suffix.
---
---@param tag string The canonical tag.
---@return string # A title-cased suffix.
local function _get_tag_suffix(tag)
    return tag:sub(1, 1) .. tag:sub(2):lower()
end

--- Get the highlight groups for `tag`.
---
---@param tag string The raw tag.
---@return _my.comment.HighlightGroup # The highlight groups.
local function _get_highlight_groups(tag)
    local details = _TAG_DETAILS[tag]
    local suffix = _get_tag_suffix(details.canonical)

    return {
        tag_highlight_name = "MyTodo" .. suffix .. "Tag",
        tag_padding_highlight_name = "MyTodo" .. suffix .. "TagPadding",
        text_highlight_name = "MyTodo" .. suffix .. "Text",
    }
end

--- Define all tag highlight groups.
function M.define_highlights()
    local normal_background = _get_normal_background()

    for _, details in pairs(_TAG_DETAILS) do
        local suffix = _get_tag_suffix(details.canonical)
        local color = _get_color(details.color)

        vim.api.nvim_set_hl(0, "MyTodo" .. suffix .. "Text", { fg = color })
        vim.api.nvim_set_hl(0, "MyTodo" .. suffix .. "Tag", { bg = color, fg = normal_background, bold = true })
        vim.api.nvim_set_hl(0, "MyTodo" .. suffix .. "TagPadding", { bg = color, fg = color, bold = true })
    end
end

--- Escape Lua pattern magic in `text`.
---
---@param text string The text to escape.
---@return string # Escaped text.
local function _pattern_escape(text)
    return (text:gsub("([^%w])", "%%%1"))
end

--- Build a comment parser from `commentstring`.
---
---@param commentstring string The buffer commentstring.
---@return string # The Lua pattern.
---@return integer # The prefix length in bytes.
local function _get_comment_pattern(commentstring)
    local before = commentstring:match("^(.-)%%s") or "# "
    local prefix = before:gsub("%s+$", "")

    return "^(%s*)" .. _pattern_escape(prefix) .. "%s?(.*)$", #prefix
end

--- Parse a raw line into comment text and comment start column.
---
---@param line string The raw line.
---@param commentstring string The buffer commentstring.
---@return _my.comment.CommentLine? # The parsed comment line, if any.
function M.parse_comment_line(line, commentstring)
    local pattern, prefix_length = _get_comment_pattern(commentstring)
    local indent, text = line:match(pattern)

    if indent == nil or text == nil then
        return nil
    end

    return {
        text = text,
        comment_start_column = #indent + prefix_length + 1,
    }
end

--- Check whether comment text is empty.
---
---@param comment _my.comment.CommentLine The parsed comment.
---@return boolean # Whether the comment has no content.
local function _is_empty_comment(comment)
    return comment.text:match("^%s*$") ~= nil
end

--- Find a todo tag in a parsed comment.
---
---@param comment _my.comment.CommentLine The parsed comment line.
---@return _my.comment.TagMatch? # The matched tag, if any.
function M.find_tag(comment)
    local tag_start, tag_end, tag = comment.text:find("(%u+)%s*:")

    if tag_start == nil or tag_end == nil or tag == nil or _TAG_DETAILS[tag] == nil then
        return nil
    end

    local tag_start_column = comment.comment_start_column + tag_start - 1
    local tag_end_column = comment.comment_start_column + tag_start - 1 + #tag

    return {
        tag = tag,
        highlight_groups = _get_highlight_groups(tag),
        comment_start_column = comment.comment_start_column,
        tag_start_column = tag_start_column,
        tag_end_column = tag_end_column,
        block_end_column = comment.comment_start_column + tag_end,
        text_start_column = comment.comment_start_column + tag_end,
    }
end

--- Add an extmark safely when the range is nonempty.
---
---@param buffer integer The buffer to highlight.
---@param line integer The 0-or-more line number.
---@param start_column integer The 0-or-more start column.
---@param end_column integer The exclusive end column.
---@param highlight_group string The highlight group to apply.
local function _set_extmark(buffer, line, start_column, end_column, highlight_group)
    if end_column <= start_column then
        return
    end

    vim.api.nvim_buf_set_extmark(buffer, _COMMENT_HIGHLIGHT, line, start_column, {
        end_col = end_column,
        hl_group = highlight_group,
        priority = 200,
        spell = false,
    })
end

--- Highlight a tagged comment line.
---
---@param buffer integer The buffer to highlight.
---@param line integer The 0-or-more line number.
---@param raw_line string The raw line text.
---@param match _my.comment.TagMatch The tag match details.
local function _highlight_tag_line(buffer, line, raw_line, match)
    _set_extmark(
        buffer,
        line,
        match.comment_start_column - 1,
        match.tag_start_column,
        match.highlight_groups.tag_padding_highlight_name
    )
    _set_extmark(buffer, line, match.tag_start_column, match.tag_end_column, match.highlight_groups.tag_highlight_name)
    _set_extmark(
        buffer,
        line,
        match.tag_end_column,
        match.block_end_column,
        match.highlight_groups.tag_padding_highlight_name
    )
    _set_extmark(buffer, line, match.text_start_column, #raw_line, match.highlight_groups.text_highlight_name)
end

--- Highlight a continuation comment line.
---
---@param buffer integer The buffer to highlight.
---@param line integer The 0-or-more line number.
---@param raw_line string The raw line text.
---@param comment _my.comment.CommentLine The parsed comment.
---@param highlight_group string The text highlight group.
local function _highlight_continuation_line(buffer, line, raw_line, comment, highlight_group)
    _set_extmark(buffer, line, comment.comment_start_column, #raw_line, highlight_group)
end

--- Highlight tagged comment blocks in `buffer`.
---
---@param buffer integer The buffer to highlight.
function M.highlight_buffer(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end

    local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    local commentstring = vim.bo[buffer].commentstring
    local line_index = 1

    vim.api.nvim_buf_clear_namespace(buffer, _COMMENT_HIGHLIGHT, 0, -1)

    while line_index <= #lines do
        local raw_line = lines[line_index]
        local comment = M.parse_comment_line(raw_line, commentstring)
        local match = comment ~= nil and M.find_tag(comment) or nil

        if comment ~= nil and match ~= nil then
            _highlight_tag_line(buffer, line_index - 1, raw_line, match)
            line_index = line_index + 1

            while line_index <= #lines do
                local continuation_raw = lines[line_index]
                local continuation = M.parse_comment_line(continuation_raw, commentstring)

                if continuation == nil or _is_empty_comment(continuation) or M.find_tag(continuation) ~= nil then
                    break
                end

                _highlight_continuation_line(
                    buffer,
                    line_index - 1,
                    continuation_raw,
                    continuation,
                    match.highlight_groups.text_highlight_name
                )
                line_index = line_index + 1
            end
        else
            line_index = line_index + 1
        end
    end
end

--- Schedule an async-ish debounced highlight update for `buffer`.
---
---@param buffer integer The buffer to update.
function M.schedule_highlight(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) or vim.bo[buffer].buftype == "terminal" then
        return
    end

    _UPDATE_GENERATION_BY_BUFFER[buffer] = (_UPDATE_GENERATION_BY_BUFFER[buffer] or 0) + 1

    local generation = _UPDATE_GENERATION_BY_BUFFER[buffer]
    local timer = _TIMER_BY_BUFFER[buffer]

    if timer ~= nil then
        pcall(function()
            timer:stop()
            timer:close()
        end)
    end

    _TIMER_BY_BUFFER[buffer] = vim.defer_fn(function()
        if _UPDATE_GENERATION_BY_BUFFER[buffer] ~= generation then
            return
        end

        vim.schedule(function()
            if _UPDATE_GENERATION_BY_BUFFER[buffer] == generation then
                M.highlight_buffer(buffer)
            end
        end)
    end, _DEBOUNCE_MS)
end

--- Create highlight groups and autocmds.
function M.setup()
    M.define_highlights()

    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("todo_comment_highlighting_colors", { clear = true }),
        desc = "Refresh todo comment highlight groups.",
        callback = M.define_highlights,
    })

    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "TextChanged", "TextChangedI", "InsertLeave" }, {
        group = vim.api.nvim_create_augroup("todo_comment_highlighting", { clear = true }),
        desc = "Debounce todo comment highlighting.",
        callback = function(event)
            M.schedule_highlight(event.buf)
        end,
    })
end

M.setup()

return M
