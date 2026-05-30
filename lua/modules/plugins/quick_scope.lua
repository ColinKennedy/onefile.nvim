--- Highlight useful `f`, `F`, `t`, and `T` jump targets on the current line.

local M = {}

---@class _my.quick_scope.Highlight
---@field line integer The 1-or-more buffer line to highlight.
---@field column integer The 1-or-more byte column to highlight.
---@field length integer The byte length to highlight.

---@class _my.quick_scope.HighlightResults
---@field primary _my.quick_scope.Highlight[] First occurrence highlights.
---@field secondary _my.quick_scope.Highlight[] Second occurrence highlights.

---@alias _my.quick_scope.Direction "backward" | "forward"

---@type string[]
local _DEFAULT_ACCEPTED_CHARS = {
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z",
    "A",
    "B",
    "C",
    "D",
    "E",
    "F",
    "G",
    "H",
    "I",
    "J",
    "K",
    "L",
    "M",
    "N",
    "O",
    "P",
    "Q",
    "R",
    "S",
    "T",
    "U",
    "V",
    "W",
    "X",
    "Y",
    "Z",
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
}

---@type string[]
local _DEFAULT_BUFTYPE_BLACKLIST = { "terminal" }
---@type table<integer, integer[]>
local _MATCH_IDS_BY_WINDOW = {}
local _TIMER = nil

--- Get a global option, initializing it with `default` if it has not been set.
---
---@generic T
---@param name string The `vim.g` option name without the `g:` prefix.
---@param default T The default value.
---@return T # The configured or default value.
local function _get_option(name, default)
    if vim.g[name] == nil then
        vim.g[name] = default
    end

    return vim.g[name]
end

--- Get the list of accepted single-character targets.
---
---@return string[] # The accepted target characters.
local function _get_accepted_chars()
    return _get_option("qs_accepted_chars", _DEFAULT_ACCEPTED_CHARS)
end

--- Build a set from a list of strings.
---
---@param values string[] The strings to include in the set.
---@return table<string, boolean> # A lookup table for `values`.
local function _make_set(values)
    ---@type table<string, boolean>
    local result = {}

    for _, value in ipairs(values) do
        result[value] = true
    end

    return result
end

--- Get a string key, respecting `g:qs_ignorecase`.
---
---@param character string The character to normalize.
---@param ignorecase boolean Whether case should be ignored.
---@return string # The normalized key.
local function _get_character_key(character, ignorecase)
    if ignorecase then
        return character:lower()
    end

    return character
end

--- Check whether `character` should be treated as part of a Vim-ish word.
---
---@param character string The character to inspect.
---@return boolean # Whether `character` is a word character.
local function _is_keyword_character(character)
    return character:match("^[%w_]$") ~= nil
end

--- Add one word's best highlight candidate to `result`.
---
---@param result _my.quick_scope.HighlightResults The result table to mutate.
---@param primary _my.quick_scope.Highlight? The primary candidate, if any.
---@param secondary _my.quick_scope.Highlight? The secondary candidate, if any.
local function _add_word_highlight(result, primary, secondary)
    if primary ~= nil then
        table.insert(result.primary, primary)
    elseif secondary ~= nil and _get_option("qs_second_highlight", 1) == 1 then
        table.insert(result.secondary, secondary)
    end
end

--- Decide whether a candidate should replace the current word candidate.
---
---@param direction _my.quick_scope.Direction The scan direction.
---@param current _my.quick_scope.Highlight? The current candidate.
---@return boolean # Whether the candidate should be stored.
local function _should_store_candidate(direction, current)
    return current == nil or direction == "backward"
end

--- Find quick-scope targets in one direction from the cursor.
---
---@param line string The line text to scan.
---@param line_number integer The 1-or-more line number for highlight positions.
---@param cursor_column integer The 1-or-more byte column under the cursor.
---@param direction _my.quick_scope.Direction The direction to scan.
---@param accepted table<string, boolean> The accepted target characters.
---@param ignorecase boolean Whether case should be ignored for target counts.
---@return _my.quick_scope.HighlightResults # The highlights found in `direction`.
local function _get_directional_highlights(line, line_number, cursor_column, direction, accepted, ignorecase)
    local step = direction == "forward" and 1 or -1
    local column = cursor_column
    local end_column = direction == "forward" and #line or 1
    local is_first_character = true
    local is_first_word = true
    ---@type table<string, integer>
    local occurrences = {}
    ---@type _my.quick_scope.Highlight?
    local primary = nil
    ---@type _my.quick_scope.Highlight?
    local secondary = nil
    ---@type table<string, _my.quick_scope.Highlight[]>
    local result = { primary = {}, secondary = {} }

    while
        column >= 1
        and column <= #line
        and (direction == "forward" and column <= end_column or column >= end_column)
    do
        local character = line:sub(column, column)
        local lookup_character = _get_character_key(character, ignorecase)

        if is_first_character then
            is_first_character = false
        elseif not _is_keyword_character(character) then
            if not is_first_word then
                _add_word_highlight(result, primary, secondary)
            end

            primary = nil
            secondary = nil
            is_first_word = false
        elseif accepted[character] or accepted[lookup_character] then
            occurrences[lookup_character] = (occurrences[lookup_character] or 0) + 1

            if not is_first_word then
                local count = occurrences[lookup_character]

                if count == 1 and _should_store_candidate(direction, primary) then
                    primary = { line = line_number, column = column, length = 1 }
                elseif count == 2 and _should_store_candidate(direction, secondary) then
                    secondary = { line = line_number, column = column, length = 1 }
                end
            end
        end

        column = column + step
    end

    _add_word_highlight(result, primary, secondary)

    return result
end

--- Append all highlights from `source` into `target`.
---
---@param target _my.quick_scope.HighlightResults The result table to mutate.
---@param source _my.quick_scope.HighlightResults The result table to append.
local function _append_highlights(target, source)
    for _, primary in ipairs(source.primary) do
        table.insert(target.primary, primary)
    end

    for _, secondary in ipairs(source.secondary) do
        table.insert(target.secondary, secondary)
    end
end

--- Determine whether Quick Scope should skip the current buffer.
---
---@param buffer integer The buffer to inspect.
---@return boolean # Whether highlighting should be skipped.
local function _should_skip_buffer(buffer)
    if _get_option("qs_enable", 1) == 0 then
        return true
    end

    local buftype_blacklist = _make_set(_get_option("qs_buftype_blacklist", _DEFAULT_BUFTYPE_BLACKLIST))
    local filetype_blacklist = _make_set(_get_option("qs_filetype_blacklist", {}))
    local buftype = vim.bo[buffer].buftype
    local filetype = vim.bo[buffer].filetype

    return buftype_blacklist[buftype] == true or filetype_blacklist[filetype] == true
end

--- Set the highlight groups used by Quick Scope.
---
function M.set_highlight_colors()
    vim.g.qs_hi_priority = _get_option("qs_hi_priority", 1)
    vim.g.qs_hi_group_primary = "QuickScopePrimary"
    vim.g.qs_hi_group_secondary = "QuickScopeSecondary"
    vim.g.qs_hi_group_cursor = "QuickScopeCursor"

    vim.api.nvim_set_hl(0, vim.g.qs_hi_group_primary, { default = true, link = "Function" })
    vim.api.nvim_set_hl(0, vim.g.qs_hi_group_secondary, { default = true, link = "Define" })
    vim.api.nvim_set_hl(0, vim.g.qs_hi_group_cursor, { default = true, link = "Cursor" })
end

--- Find first and second accepted-character occurrences for a line.
---
---@param line string The line text to scan.
---@param line_number integer The 1-or-more line number for highlight positions.
---@param cursor_column integer? The 1-or-more cursor byte column to scan from.
---@return _my.quick_scope.HighlightResults # The highlights for the line.
function M.get_line_highlights(line, line_number, cursor_column)
    local max_chars = _get_option("qs_max_chars", 1000)

    if max_chars > 0 and #line > max_chars then
        return { primary = {}, secondary = {} }
    end

    local accepted = _make_set(_get_accepted_chars())
    local ignorecase = _get_option("qs_ignorecase", 0) == 1
    local normalized_cursor_column = math.max(1, math.min(cursor_column or 1, math.max(#line, 1)))
    ---@type table<string, _my.quick_scope.Highlight[]>
    local result = { primary = {}, secondary = {} }
    local forward =
        _get_directional_highlights(line, line_number, normalized_cursor_column, "forward", accepted, ignorecase)
    local backward =
        _get_directional_highlights(line, line_number, normalized_cursor_column, "backward", accepted, ignorecase)

    _append_highlights(result, forward)
    _append_highlights(result, backward)

    return result
end

--- Stop any pending delayed highlight timer.
local function _stop_timer()
    if _TIMER ~= nil then
        vim.fn.timer_stop(_TIMER)
        _TIMER = nil
    end
end

--- Delete any Quick Scope matches in `window`.
---
---@param window integer The window whose matches should be cleared.
function M.unhighlight_window(window)
    for _, match_id in ipairs(_MATCH_IDS_BY_WINDOW[window] or {}) do
        pcall(vim.fn.matchdelete, match_id, window)
    end

    ---@type integer[]
    _MATCH_IDS_BY_WINDOW[window] = {}
end

--- Delete Quick Scope matches in the current window.
function M.unhighlight_line()
    M.unhighlight_window(vim.api.nvim_get_current_win())
end

--- Add highlight matches for `positions`.
---
---@param group string The highlight group to use.
---@param positions _my.quick_scope.Highlight[] The positions to highlight.
---@return integer? # The match id, if one was added.
local function _add_match(group, positions)
    if #positions == 0 then
        return nil
    end

    ---@type integer[][]
    local match_positions = {}

    for _, position in ipairs(positions) do
        table.insert(match_positions, { position.line, position.column, position.length })
    end

    return tonumber(vim.fn.matchaddpos(group, match_positions, _get_option("qs_hi_priority", 1)))
end

--- Highlight the current line in the current window.
function M.highlight_line()
    local buffer = vim.api.nvim_get_current_buf()
    local window = vim.api.nvim_get_current_win()

    M.unhighlight_window(window)

    if _should_skip_buffer(buffer) then
        return
    end

    local line_number = vim.api.nvim_win_get_cursor(window)[1]
    local cursor_column = vim.api.nvim_win_get_cursor(window)[2] + 1
    local line = vim.api.nvim_buf_get_lines(buffer, line_number - 1, line_number, false)[1] or ""
    local highlights = M.get_line_highlights(line, line_number, cursor_column)
    ---@type integer[]
    local match_ids = {}
    local primary_match = _add_match(vim.g.qs_hi_group_primary, highlights.primary)
    local secondary_match = _add_match(vim.g.qs_hi_group_secondary, highlights.secondary)

    if primary_match ~= nil then
        table.insert(match_ids, primary_match)
    end

    if secondary_match ~= nil then
        table.insert(match_ids, secondary_match)
    end

    _MATCH_IDS_BY_WINDOW[window] = match_ids
end

--- Highlight the current line after `g:qs_delay`.
function M.highlight_line_delay()
    _stop_timer()

    local delay = _get_option("qs_delay", vim.fn.has("timers") == 1 and 50 or 0)

    if delay <= 0 then
        M.highlight_line()
        return
    end

    _TIMER = vim.fn.timer_start(delay, function()
        _TIMER = nil
        M.highlight_line()
    end)
end

--- Toggle Quick Scope on or off.
function M.toggle()
    vim.g.qs_enable = _get_option("qs_enable", 1) == 1 and 0 or 1

    if vim.g.qs_enable == 1 then
        M.highlight_line_delay()
    else
        _stop_timer()
        M.unhighlight_line()
    end
end

--- Create Quick Scope autocommands, commands, mappings, and highlight groups.
function M.setup()
    M.set_highlight_colors()
    _get_option("qs_enable", 1)
    _get_option("qs_lazy_highlight", 0)
    _get_option("qs_second_highlight", 1)
    _get_option("qs_ignorecase", 0)
    _get_option("qs_max_chars", 1000)
    _get_accepted_chars()
    _get_option("qs_buftype_blacklist", _DEFAULT_BUFTYPE_BLACKLIST)
    _get_option("qs_filetype_blacklist", {})
    _get_option("qs_augrp_clean", { "EasyMotionPromptBegin" })
    _get_option("qs_delay", vim.fn.has("timers") == 1 and 50 or 0)

    local group = vim.api.nvim_create_augroup("quick_scope_lua", { clear = true })
    local movement_events = _get_option("qs_lazy_highlight", 0) == 1
            and { "CursorHold", "InsertLeave", "ColorScheme", "WinEnter", "BufEnter", "FocusGained" }
        or { "CursorMoved", "InsertLeave", "ColorScheme", "WinEnter", "BufEnter", "FocusGained" }

    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        desc = "Refresh Quick Scope highlight groups.",
        callback = M.set_highlight_colors,
    })

    vim.api.nvim_create_autocmd(movement_events, {
        group = group,
        desc = "Highlight Quick Scope targets on the current line.",
        callback = function()
            if _get_option("qs_lazy_highlight", 0) == 1 then
                M.highlight_line()
            else
                M.highlight_line_delay()
            end
        end,
    })

    vim.api.nvim_create_autocmd({ "InsertEnter", "BufLeave", "TabLeave", "WinLeave", "FocusLost" }, {
        group = group,
        desc = "Clear Quick Scope targets when leaving the active line context.",
        callback = function()
            _stop_timer()
            M.unhighlight_line()
        end,
    })

    vim.api.nvim_create_user_command("QuickScopeToggle", M.toggle, {
        desc = "Toggle Quick Scope current-line jump target highlighting.",
        nargs = 0,
    })

    vim.keymap.set({ "n", "x" }, "<Plug>(QuickScopeToggle)", M.toggle, {
        desc = "Toggle Quick Scope current-line jump target highlighting.",
    })
end

--- My personal settings that "feel good" with quick-scope.
function M.initialize()
    -- Stop quick-scope highlighting after 160 characters
    vim.g.qs_max_chars = 160

    vim.api.nvim_set_hl(0, "QuickScopePrimary", { fg = "#D7FFAF", ctermfg = 193, underline = true })
    vim.api.nvim_set_hl(0, "QuickScopeSecondary", { fg = "#5FFFFF", ctermfg = 189, underline = true })

    local display_group = vim.api.nvim_create_augroup("quick_scope_display_group", { clear = true })

    -- Disable quick-scope on Terminal buffers because it tends to be distracting
    --
    -- Reference: https://github.com/unblevable/quick-scope#toggle-highlighting
    --
    vim.api.nvim_create_autocmd({ "TermEnter", "TermOpen" }, {
        command = "let b:qs_local_disable=1",
        group = display_group,
        pattern = "*",
    })
end

M.setup()

M.initialize()

return M
