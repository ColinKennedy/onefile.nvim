--- Show git deletions as virtual lines and highlight added / changed lines in-place.
---
--- Added lines get a whole-line highlight, changed lines show their previous text
--- as a virtual line and only highlight the parts that actually differ.
---
--- The view belongs to a window, not to a buffer, so it keeps showing whichever
--- file that window displays until it is toggled off again.
---
--- The comparison follows Neovim's own `diffopt` so `algorithm:`, `linematch:`,
--- `inline:`, and the `iwhite*` flags behave the same as `:help diff-mode`.

local M = {}
local _P = {}

local _AUGROUP = vim.api.nvim_create_augroup("my.git_diff_view", { clear = true })
local _NAMESPACE = vim.api.nvim_create_namespace("my.git_diff_view")

local _ADD_HIGHLIGHT = "MyGitDiffViewAdd"
local _CHANGE_TEXT_HIGHLIGHT = "MyGitDiffViewChangeText"
local _DELETE_HIGHLIGHT = "MyGitDiffViewDelete"
local _DELETE_TEXT_HIGHLIGHT = "MyGitDiffViewDeleteText"

--- Lines longer than this skip character-level comparison, for speed.
local _MAXIMUM_INLINE_LENGTH = 2000

---@alias _my.git_diff_view.DiffOptions table<string, boolean | integer | string>

--- Neovim renamed `vim.diff` to `vim.text.diff`. Prefer the newer name.
---
---@type fun(old_text: string, new_text: string, options: _my.git_diff_view.DiffOptions): integer[][]?
---@diagnostic disable-next-line: undefined-field
local _diff = vim.text and vim.text.diff or vim.diff

---@class _my.git_diff_view.Region A changed byte range within a single line.
---@field start_column integer The 0-based, inclusive byte column.
---@field end_column integer The 0-based, exclusive byte column.

---@class _my.git_diff_view.Token One comparable piece of a line.
---@field start_column integer The 0-based, inclusive byte column.
---@field end_column integer The 0-based, exclusive byte column.

---@class _my.git_diff_view.Segment Some line text that shares one highlight group.
---@field text string The raw line text.
---@field highlight string The highlight group to draw `text` with.

---@alias _my.git_diff_view.Chunk [string, string] Virtual text plus its highlight group.

---@class _my.git_diff_view.Mark One git diff view extmark.
---@field row integer The 0-based buffer row that the extmark attaches to.
---@field line_highlight string? The highlight group for all of `row`.
---@field regions _my.git_diff_view.Region[]? The changed byte ranges within `row`.
---@field virtual_lines _my.git_diff_view.Chunk[][]? The deleted lines to display.
---@field virtual_lines_above boolean? If `true`, show `virtual_lines` above `row`.

---@alias _my.git_diff_view.InlineMode "char" | "none" | "simple" | "word"

--- The windows that currently display the git diff view.
---
---@type table<integer, boolean>
local _ENABLED_WINDOWS = {}

--- The buffers that currently have git diff view extmarks drawn in them.
---
---@type table<integer, boolean>
local _DRAWN_BUFFERS = {}

--- Tracks the newest async update request per buffer so stale callbacks cannot draw.
---
---@type table<integer, integer>
local _UPDATE_GENERATION_BY_BUFFER = {}

--- How long to wait after the last keystroke before recomputing the view.
local _TEXT_CHANGED_I_DEBOUNCE_MS = 100

--- Per-buffer timers used to debounce `TextChangedI` updates.
---
---@type table<integer, uv.uv_timer_t>
local _TIMERS_BY_BUFFER = {}

--- Stop and free the debounce timer for `buffer`, if any.
---
---@param buffer integer The buffer whose timer should be cleared.
local function _clear_timer(buffer)
    local timer = _TIMERS_BY_BUFFER[buffer]

    if not timer then
        return
    end

    timer:stop()
    timer:close()
    _TIMERS_BY_BUFFER[buffer] = nil
end

--- Define the git diff view highlight groups.
function _P.define_highlights()
    vim.api.nvim_set_hl(0, _ADD_HIGHLIGHT, { default = true, link = "DiffAdd" })
    vim.api.nvim_set_hl(0, _CHANGE_TEXT_HIGHLIGHT, { default = true, link = "DiffText" })
    vim.api.nvim_set_hl(0, _DELETE_HIGHLIGHT, { default = true, link = "DiffDelete" })
    vim.api.nvim_set_hl(0, _DELETE_TEXT_HIGHLIGHT, { default = true, link = "DiffText" })
end

--- Get each comma-separated entry from Neovim's `diffopt`.
---
---@return string[] # The raw values, e.g. `{"internal", "linematch:40"}`.
---
function _P.get_diff_option_values()
    return vim.split(vim.o.diffopt, ",", { plain = true, trimempty = true })
end

--- Convert Neovim's `diffopt` into options for the built-in diff function.
---
---@return _my.git_diff_view.DiffOptions # The options to pass to `vim.diff` / `vim.text.diff`.
---
function _P.get_diff_options()
    ---@type _my.git_diff_view.DiffOptions
    local options = { ctxlen = 0, result_type = "indices" }

    for _, value in ipairs(_P.get_diff_option_values()) do
        if value == "iblank" then
            options.ignore_blank_lines = true
        elseif value == "iwhite" then
            options.ignore_whitespace_change = true
        elseif value == "iwhiteall" then
            options.ignore_whitespace = true
        elseif value == "iwhiteeol" then
            options.ignore_whitespace_change_at_eol = true
        elseif value == "indent-heuristic" then
            options.indent_heuristic = true
        else
            local algorithm = value:match("^algorithm:(%a+)$")

            if algorithm then
                options.algorithm = algorithm
            else
                local linematch = tonumber(value:match("^linematch:(%d+)$") or "")

                if linematch then
                    options.linematch = linematch
                end
            end
        end
    end

    return options
end

--- Get the `inline:` part of Neovim's `diffopt`.
---
--- Neovim only added `inline:` in a later release so this falls back to the most
--- precise mode, which is what this feature wants anyway.
---
---@return _my.git_diff_view.InlineMode # How changed lines should be compared.
---
function _P.get_inline_mode()
    for _, value in ipairs(_P.get_diff_option_values()) do
        local mode = value:match("^inline:(%a+)$")

        if mode == "char" or mode == "none" or mode == "simple" or mode == "word" then
            return mode
        end
    end

    return "char"
end

--- Strip trailing carriage returns so CRLF blobs compare against buffer lines.
---
---@param lines string[] The lines to normalize.
---@return string[] # The normalized lines.
---
function _P.normalize_lines(lines)
    ---@type string[]
    local output = {}

    for _, line in ipairs(lines) do
        table.insert(output, (line:gsub("\r$", "")))
    end

    return output
end

--- Join `lines` into diff-ready text.
---
---@param lines string[] The lines to join.
---@return string # The text, always ending in a newline unless it is empty.
---
function _P.join_lines(lines)
    if #lines == 0 then
        return ""
    end

    return table.concat(lines, "\n") .. "\n"
end

--- Compute line-level hunks between `old_lines` and `new_lines`.
---
---@param old_lines string[] The original lines.
---@param new_lines string[] The current lines.
---@return integer[][] # Each `{old_start, old_count, new_start, new_count}` hunk.
---
function _P.compute_hunks(old_lines, new_lines)
    local success, hunks = pcall(_diff, _P.join_lines(old_lines), _P.join_lines(new_lines), _P.get_diff_options())

    if not success or type(hunks) ~= "table" then
        return {}
    end

    return hunks
end

--- Get the text that `token` covers within `line`.
---
---@param line string The line that `token` came from.
---@param token _my.git_diff_view.Token The token to read.
---@return string # The token text.
---
function _P.get_token_text(line, token)
    return line:sub(token.start_column + 1, token.end_column)
end

--- Split `line` into one token per character.
---
---@param line string The line to split.
---@return _my.git_diff_view.Token[] # The character tokens.
---
function _P.get_character_tokens(line)
    local positions = vim.str_utf_pos(line)
    ---@type _my.git_diff_view.Token[]
    local tokens = {}

    for index, position in ipairs(positions) do
        table.insert(tokens, {
            end_column = (positions[index + 1] or #line + 1) - 1,
            start_column = position - 1,
        })
    end

    return tokens
end

--- Split `line` into keyword, whitespace, and single-character tokens.
---
---@param line string The line to split.
---@return _my.git_diff_view.Token[] # The word tokens.
---
function _P.get_word_tokens(line)
    ---@type _my.git_diff_view.Token[]
    local tokens = {}
    local index = 1

    while index <= #line do
        local _, last = line:find("^[%w_]+", index)

        if not last then
            _, last = line:find("^%s+", index)
        end

        if not last then
            last = index + vim.str_utf_end(line, index)
        end

        table.insert(tokens, { end_column = last, start_column = index - 1 })
        index = last + 1
    end

    return tokens
end

--- Split `line` into the tokens that `mode` compares.
---
---@param line string The line to split.
---@param mode _my.git_diff_view.InlineMode The `diffopt` inline mode.
---@return _my.git_diff_view.Token[] # The tokens to diff.
---
function _P.get_tokens(line, mode)
    if mode == "word" then
        return _P.get_word_tokens(line)
    end

    return _P.get_character_tokens(line)
end

--- Get the region that covers all of `line`.
---
---@param line string The line to cover.
---@return _my.git_diff_view.Region[] # The whole-line region, if `line` has text.
---
function _P.get_whole_line_regions(line)
    if line == "" then
        return {}
    end

    return { { end_column = #line, start_column = 0 } }
end

--- Get one region per changed run of tokens.
---
---@param old_line string The original line.
---@param new_line string The current line.
---@param mode _my.git_diff_view.InlineMode The `diffopt` inline mode.
---@return _my.git_diff_view.Region[] # The removed regions within `old_line`.
---@return _my.git_diff_view.Region[] # The added regions within `new_line`.
---
function _P.get_token_regions(old_line, new_line, mode)
    local old_tokens = _P.get_tokens(old_line, mode)
    local new_tokens = _P.get_tokens(new_line, mode)

    ---@type string[]
    local old_texts = {}
    ---@type string[]
    local new_texts = {}

    for _, token in ipairs(old_tokens) do
        table.insert(old_texts, _P.get_token_text(old_line, token))
    end

    for _, token in ipairs(new_tokens) do
        table.insert(new_texts, _P.get_token_text(new_line, token))
    end

    local success, hunks = pcall(_diff, _P.join_lines(old_texts), _P.join_lines(new_texts), {
        ctxlen = 0,
        result_type = "indices",
    })

    if not success or type(hunks) ~= "table" then
        return _P.get_whole_line_regions(old_line), _P.get_whole_line_regions(new_line)
    end

    ---@type _my.git_diff_view.Region[]
    local old_regions = {}
    ---@type _my.git_diff_view.Region[]
    local new_regions = {}

    for _, hunk in ipairs(hunks) do
        local old_start, old_count, new_start, new_count = hunk[1], hunk[2], hunk[3], hunk[4]

        if old_count > 0 then
            table.insert(old_regions, {
                end_column = old_tokens[old_start + old_count - 1].end_column,
                start_column = old_tokens[old_start].start_column,
            })
        end

        if new_count > 0 then
            table.insert(new_regions, {
                end_column = new_tokens[new_start + new_count - 1].end_column,
                start_column = new_tokens[new_start].start_column,
            })
        end
    end

    return old_regions, new_regions
end

--- Get the single region between the common prefix and common suffix.
---
---@param old_line string The original line.
---@param new_line string The current line.
---@return _my.git_diff_view.Region[] # The removed region within `old_line`.
---@return _my.git_diff_view.Region[] # The added region within `new_line`.
---
function _P.get_simple_regions(old_line, new_line)
    local old_tokens = _P.get_character_tokens(old_line)
    local new_tokens = _P.get_character_tokens(new_line)
    local first = 1

    while
        first <= #old_tokens
        and first <= #new_tokens
        and _P.get_token_text(old_line, old_tokens[first]) == _P.get_token_text(new_line, new_tokens[first])
    do
        first = first + 1
    end

    local old_last = #old_tokens
    local new_last = #new_tokens

    while
        old_last >= first
        and new_last >= first
        and _P.get_token_text(old_line, old_tokens[old_last]) == _P.get_token_text(new_line, new_tokens[new_last])
    do
        old_last = old_last - 1
        new_last = new_last - 1
    end

    --- Convert an inclusive token range into a byte region.
    ---
    ---@param tokens _my.git_diff_view.Token[] The tokens to read from.
    ---@param last integer The last token index to include.
    ---@return _my.git_diff_view.Region[] # The region, if the range is not empty.
    local function _to_regions(tokens, last)
        if last < first then
            return {}
        end

        return { { end_column = tokens[last].end_column, start_column = tokens[first].start_column } }
    end

    return _to_regions(old_tokens, old_last), _to_regions(new_tokens, new_last)
end

--- Find the parts of `old_line` and `new_line` that differ.
---
---@param old_line string The original line.
---@param new_line string The current line.
---@param mode _my.git_diff_view.InlineMode The `diffopt` inline mode.
---@return _my.git_diff_view.Region[] # The removed regions within `old_line`.
---@return _my.git_diff_view.Region[] # The added regions within `new_line`.
---
function _P.get_changed_regions(old_line, new_line, mode)
    if old_line == new_line then
        return {}, {}
    end

    if mode == "none" or #old_line > _MAXIMUM_INLINE_LENGTH or #new_line > _MAXIMUM_INLINE_LENGTH then
        return _P.get_whole_line_regions(old_line), _P.get_whole_line_regions(new_line)
    end

    if mode == "simple" then
        return _P.get_simple_regions(old_line, new_line)
    end

    return _P.get_token_regions(old_line, new_line, mode)
end

--- Cut `line` into highlight-able pieces using `regions`.
---
---@param line string The line to split.
---@param regions _my.git_diff_view.Region[] The changed byte ranges within `line`.
---@param base string The highlight group for unchanged text.
---@param changed string The highlight group for changed text.
---@return _my.git_diff_view.Segment[] # The pieces, in display order.
---
function _P.get_segments(line, regions, base, changed)
    ---@type _my.git_diff_view.Segment[]
    local segments = {}
    local cursor = 0

    for _, region in ipairs(regions) do
        if region.start_column > cursor then
            table.insert(segments, { highlight = base, text = line:sub(cursor + 1, region.start_column) })
        end

        table.insert(segments, { highlight = changed, text = line:sub(region.start_column + 1, region.end_column) })
        cursor = region.end_column
    end

    if cursor < #line then
        table.insert(segments, { highlight = base, text = line:sub(cursor + 1) })
    end

    return segments
end

--- Replace the tabs in `text` with the spaces that they display as.
---
--- Virtual lines do not follow the buffer's tab stops so deleted lines have to
--- be expanded by hand or they will not line up with the code around them.
---
---@param text string The text to expand.
---@param column integer The 0-based display column that `text` starts at.
---@param tabstop integer The buffer's tab width.
---@return string # The expanded text.
---@return integer # The display column just after `text`.
---
function _P.expand_tabs(text, column, tabstop)
    ---@type string[]
    local output = {}
    local index = 1

    while index <= #text do
        local tab = text:find("\t", index, true)

        if not tab then
            break
        end

        if tab > index then
            local before = text:sub(index, tab - 1)
            table.insert(output, before)
            column = column + vim.fn.strdisplaywidth(before)
        end

        local width = tabstop - (column % tabstop)
        table.insert(output, string.rep(" ", width))
        column = column + width
        index = tab + 1
    end

    local rest = text:sub(index)
    table.insert(output, rest)

    return table.concat(output), column + vim.fn.strdisplaywidth(rest)
end

--- Render one deleted line as virtual text.
---
---@param line string The deleted line.
---@param regions _my.git_diff_view.Region[] The removed byte ranges within `line`.
---@param tabstop integer The buffer's tab width.
---@return _my.git_diff_view.Chunk[] # The virtual line to display.
---
function _P.get_virtual_line(line, regions, tabstop)
    ---@type _my.git_diff_view.Chunk[]
    local chunks = {}
    local column = 0

    for _, segment in ipairs(_P.get_segments(line, regions, _DELETE_HIGHLIGHT, _DELETE_TEXT_HIGHLIGHT)) do
        ---@type string
        local text

        text, column = _P.expand_tabs(segment.text, column, tabstop)
        table.insert(chunks, { text, segment.highlight })
    end

    if #chunks == 0 then
        -- NOTE: An empty deleted line still needs a cell or nothing is drawn.
        table.insert(chunks, { " ", _DELETE_HIGHLIGHT })
    end

    return chunks
end

--- Find where a hunk's deleted lines should be drawn.
---
---@param new_start integer The hunk's 1-based current-buffer start line.
---@param new_count integer The number of current-buffer lines in the hunk.
---@return integer # The 0-based row to attach the extmark to.
---@return boolean # If `true`, draw the virtual lines above that row.
---
function _P.get_virtual_line_row(new_start, new_count)
    if new_count > 0 then
        return new_start - 1, true
    end

    if new_start < 1 then
        return 0, true
    end

    return new_start - 1, false
end

--- Describe every git diff view extmark for a buffer.
---
---@param old_lines string[] The git index (or HEAD) version of the file.
---@param new_lines string[] The current buffer lines.
---@param tabstop integer The buffer's tab width.
---@return _my.git_diff_view.Mark[] # The extmarks to draw.
---
function M.compute_marks(old_lines, new_lines, tabstop)
    old_lines = _P.normalize_lines(old_lines)
    new_lines = _P.normalize_lines(new_lines)

    local mode = _P.get_inline_mode()
    ---@type _my.git_diff_view.Mark[]
    local marks = {}

    for _, hunk in ipairs(_P.compute_hunks(old_lines, new_lines)) do
        local old_start, old_count, new_start, new_count = hunk[1], hunk[2], hunk[3], hunk[4]

        ---@type _my.git_diff_view.Chunk[][]
        local virtual_lines = {}
        ---@type _my.git_diff_view.Mark[]
        local line_marks = {}

        for offset = 0, math.max(old_count, new_count) - 1 do
            local removed = offset < old_count and old_lines[old_start + offset] or nil
            local added = offset < new_count and new_lines[new_start + offset] or nil
            local row = new_start + offset - 1
            ---@type _my.git_diff_view.Region[]
            local old_regions = {}
            ---@type _my.git_diff_view.Region[]
            local new_regions = {}

            if removed and added then
                old_regions, new_regions = _P.get_changed_regions(removed, added, mode)
            end

            if removed then
                table.insert(virtual_lines, _P.get_virtual_line(removed, old_regions, tabstop))
            end

            if added and not removed then
                -- NOTE: The whole line is new so there is no "before" text to compare with.
                table.insert(line_marks, { line_highlight = _ADD_HIGHLIGHT, row = row })
            elseif added and #new_regions > 0 then
                table.insert(line_marks, { regions = new_regions, row = row })
            end
        end

        if #virtual_lines > 0 then
            local row, above = _P.get_virtual_line_row(new_start, new_count)
            table.insert(marks, { row = row, virtual_lines = virtual_lines, virtual_lines_above = above })
        end

        vim.list_extend(marks, line_marks)
    end

    return marks
end

--- Check if `buffer` can show the git diff view.
---
---@param buffer integer The buffer to inspect.
---@return boolean # If the view is allowed, return `true`.
---
function _P.is_supported_buffer(buffer)
    return vim.api.nvim_buf_is_valid(buffer)
        and vim.api.nvim_buf_get_name(buffer) ~= ""
        and vim.bo[buffer].buftype == ""
        and vim.bo[buffer].modifiable
end

--- Get a real window number for `window`.
---
---@param window integer? The window to resolve. Defaults to the current window.
---@return integer # The resolved window.
---
function _P.get_window(window)
    if not window or window == 0 then
        return vim.api.nvim_get_current_win()
    end

    return window
end

--- Get every buffer that an enabled window currently displays.
---
--- Windows that no longer exist are forgotten along the way.
---
---@return table<integer, boolean> # The buffers that should show the git diff view.
---
function _P.get_wanted_buffers()
    ---@type table<integer, boolean>
    local buffers = {}

    for window, _ in pairs(_ENABLED_WINDOWS) do
        if vim.api.nvim_win_is_valid(window) then
            buffers[vim.api.nvim_win_get_buf(window)] = true
        else
            _ENABLED_WINDOWS[window] = nil
        end
    end

    return buffers
end

--- Check if `buffer` should show the git diff view.
---
---@param buffer integer The buffer to inspect.
---@return boolean # If some enabled window displays `buffer`, return `true`.
---
function _P.is_wanted_buffer(buffer)
    return _P.get_wanted_buffers()[buffer] == true
end

--- Remove every git diff view extmark from `buffer`.
---
---@param buffer integer The buffer to clear.
---
function _P.clear(buffer)
    if vim.api.nvim_buf_is_valid(buffer) then
        vim.api.nvim_buf_clear_namespace(buffer, _NAMESPACE, 0, -1)
    end
end

--- Draw `marks` in `buffer`, replacing whatever was drawn before.
---
---@param buffer integer The buffer to draw into.
---@param marks _my.git_diff_view.Mark[] The extmarks to draw.
---
function _P.apply(buffer, marks)
    _P.clear(buffer)
    _DRAWN_BUFFERS[buffer] = true

    local line_count = vim.api.nvim_buf_line_count(buffer)

    for _, mark in ipairs(marks) do
        local row = math.max(0, math.min(mark.row, line_count - 1))

        if mark.virtual_lines then
            vim.api.nvim_buf_set_extmark(buffer, _NAMESPACE, row, 0, {
                virt_lines = mark.virtual_lines,
                virt_lines_above = mark.virtual_lines_above,
            })
        end

        if mark.line_highlight then
            vim.api.nvim_buf_set_extmark(buffer, _NAMESPACE, row, 0, { line_hl_group = mark.line_highlight })
        end

        if mark.regions then
            local length = #(vim.api.nvim_buf_get_lines(buffer, row, row + 1, false)[1] or "")

            for _, region in ipairs(mark.regions) do
                local start_column = math.min(region.start_column, length)
                local end_column = math.min(region.end_column, length)

                if end_column > start_column then
                    vim.api.nvim_buf_set_extmark(buffer, _NAMESPACE, row, start_column, {
                        end_col = end_column,
                        hl_group = _CHANGE_TEXT_HIGHLIGHT,
                    })
                end
            end
        end
    end
end

--- Check if `window` currently shows the git diff view.
---
---@param window integer? The window to inspect. Defaults to the current window.
---@return boolean # If the view is on, return `true`.
---
function M.is_enabled(window)
    return _ENABLED_WINDOWS[_P.get_window(window)] == true
end

--- Redraw the git diff view for `buffer`, if some enabled window displays it.
---
---@param buffer integer? The buffer to update. Defaults to the current buffer.
---
function M.update(buffer)
    local current = buffer or vim.api.nvim_get_current_buf()

    if not _P.is_wanted_buffer(current) or not _P.is_supported_buffer(current) then
        return
    end

    _UPDATE_GENERATION_BY_BUFFER[current] = (_UPDATE_GENERATION_BY_BUFFER[current] or 0) + 1
    local generation = _UPDATE_GENERATION_BY_BUFFER[current]

    local git_diff = require("modules.utilities.git_diff")

    git_diff.get_file_details(current, function(details)
        if generation ~= _UPDATE_GENERATION_BY_BUFFER[current] then
            return
        end

        if not details then
            _P.clear(current)

            return
        end

        git_diff.get_index_lines(details, function(old_lines)
            if
                generation ~= _UPDATE_GENERATION_BY_BUFFER[current]
                or not _P.is_wanted_buffer(current)
                or not _P.is_supported_buffer(current)
            then
                return
            end

            local new_lines = vim.api.nvim_buf_get_lines(current, 0, -1, false)
            _P.apply(current, M.compute_marks(old_lines, new_lines, vim.bo[current].tabstop))
        end)
    end)
end

--- Stop drawing the git diff view in `buffer`.
---
---@param buffer integer The buffer to clear.
---
function _P.stop(buffer)
    _DRAWN_BUFFERS[buffer] = nil
    _UPDATE_GENERATION_BY_BUFFER[buffer] = (_UPDATE_GENERATION_BY_BUFFER[buffer] or 0) + 1
    _P.clear(buffer)
end

--- Redraw every enabled window and clear the buffers that they no longer show.
function _P.refresh()
    local wanted = _P.get_wanted_buffers()

    for buffer, _ in pairs(_DRAWN_BUFFERS) do
        if not wanted[buffer] then
            _P.stop(buffer)
        end
    end

    for buffer, _ in pairs(wanted) do
        M.update(buffer)
    end
end

--- Check if anything still needs the git diff view autocommands to do work.
---
---@return boolean # If some window is on or some buffer is drawn, return `true`.
---
function _P.is_active()
    return next(_ENABLED_WINDOWS) ~= nil or next(_DRAWN_BUFFERS) ~= nil
end

--- Turn the git diff view on or off for `window`.
---
---@param window integer? The window to toggle. Defaults to the current window.
---@return boolean # If the view is now on, return `true`.
---
function M.toggle(window)
    local current = _P.get_window(window)

    if _ENABLED_WINDOWS[current] then
        _ENABLED_WINDOWS[current] = nil
        _P.refresh()
        vim.notify("Git diff view is now disabled.", vim.log.levels.INFO)

        return false
    end

    _ENABLED_WINDOWS[current] = true
    vim.notify("Git diff view is now enabled.", vim.log.levels.INFO)
    _P.refresh()

    return true
end

_P.define_highlights()

vim.api.nvim_create_autocmd("ColorScheme", {
    callback = _P.define_highlights,
    desc = "Refresh the git diff view highlight groups.",
    group = _AUGROUP,
})

vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave", "TextChanged", "TextChangedI" }, {
    callback = function(event)
        if not _P.is_active() then
            return
        end

        local buffer = event.buf

        if event.event ~= "TextChangedI" then
            _clear_timer(buffer)
            vim.schedule(function()
                M.update(buffer)
            end)

            return
        end

        if not _TIMERS_BY_BUFFER[buffer] then
            _TIMERS_BY_BUFFER[buffer] = assert(vim.uv.new_timer())
        end

        _TIMERS_BY_BUFFER[buffer]:stop()
        _TIMERS_BY_BUFFER[buffer]:start(_TEXT_CHANGED_I_DEBOUNCE_MS, 0, function()
            vim.schedule(function()
                M.update(buffer)
            end)
        end)
    end,
    desc = "Redraw the git diff view after the buffer changes. `TextChangedI` is debounced.",
    group = _AUGROUP,
})

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "WinEnter" }, {
    callback = function()
        if not _P.is_active() then
            return
        end

        vim.schedule(_P.refresh)
    end,
    desc = "Follow the git diff view window when its displayed buffer changes.",
    group = _AUGROUP,
})

vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(event)
        local window = tonumber(event.match)

        if window then
            _ENABLED_WINDOWS[window] = nil
        end

        if not _P.is_active() then
            return
        end

        vim.schedule(_P.refresh)
    end,
    desc = "Forget git diff view state for closed windows.",
    group = _AUGROUP,
})

vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    callback = function(event)
        _DRAWN_BUFFERS[event.buf] = nil
        _UPDATE_GENERATION_BY_BUFFER[event.buf] = nil
        _clear_timer(event.buf)
    end,
    desc = "Forget git diff view state for deleted buffers.",
    group = _AUGROUP,
})

vim.api.nvim_create_autocmd("BufFilePost", {
    callback = function(event)
        require("modules.utilities.git_diff").invalidate_file_details(event.buf)
    end,
    desc = "Forget cached Git file details after a buffer is renamed.",
    group = _AUGROUP,
})

vim.api.nvim_create_user_command("ToggleGitDiffView", function()
    M.toggle()
end, {
    desc = "Toggle git added / deleted / changed line highlights for the current window.",
    nargs = 0,
})

return M
