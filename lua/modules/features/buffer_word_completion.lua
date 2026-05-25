--- Provide lightweight current-buffer completion when no LSP completion exists.

local M = {}
local _P = {}

local _AUGROUP = vim.api.nvim_create_augroup("my.buffer_word_completion", { clear = true })
local _MIN_PREFIX_LENGTH = 2
local _MAX_WORDS = 5000
local _MAX_LINE_LENGTH = 1000
local _DEBOUNCE_MS = 60

---@type uv.uv_timer_t?
local _TIMER = nil

--- Return true when the current buffer should not use buffer-word completion.
---
---@param buffer integer The buffer to inspect.
---@return boolean # Whether buffer-word completion should be skipped.
function _P.should_skip_buffer(buffer)
    local buftype = vim.bo[buffer].buftype

    if buftype ~= "" then
        return true
    end

    if not vim.bo[buffer].modifiable or vim.bo[buffer].readonly then
        return true
    end

    return false
end

--- Return true if any attached LSP client already provides completion.
---
---@param buffer integer The buffer to inspect.
---@return boolean # Whether an attached LSP client supports completion.
function _P.has_lsp_completion(buffer)
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = buffer })) do
        if client:supports_method("textDocument/completion") then
            return true
        end
    end

    return false
end

--- Find the completion prefix immediately before the cursor.
---
---@param line string The current line.
---@param column integer The zero-based cursor column.
---@return integer start_column The one-based completion start column.
---@return string prefix The text that should be completed.
function _P.get_prefix(line, column)
    local before_cursor = line:sub(1, column)
    local prefix = before_cursor:match("[%w_]+$") or ""
    local start_column = column - #prefix + 1

    return start_column, prefix
end

--- Score a matching word by its closest line distance to the cursor.
---
---@param word string The candidate word.
---@param line_number integer The one-based line where the word appears.
---@param cursor_line integer The one-based cursor line.
---@param scores table<string, integer> The best known score per word.
local function _record_word_score(word, line_number, cursor_line, scores)
    local score = math.abs(line_number - cursor_line)
    local existing = scores[word]

    if not existing or score < existing then
        scores[word] = score
    end
end

--- Collect matching completion entries from the current buffer.
---
---@param buffer integer The buffer to scan.
---@param prefix string The already-typed completion prefix.
---@param cursor_line integer The one-based cursor line.
---@return _my.completion.Entry[] # Completion entries ordered by nearby usage first.
function _P.collect_matches(buffer, prefix, cursor_line)
    local escaped_prefix = vim.pesc(prefix)
    local scores = {}
    local seen_count = 0

    for line_number, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
        if #line <= _MAX_LINE_LENGTH then
            for word in line:gmatch("[%w_]+") do
                if word ~= prefix and word:find("^" .. escaped_prefix) then
                    if scores[word] == nil then
                        seen_count = seen_count + 1
                    end

                    _record_word_score(word, line_number, cursor_line, scores)

                    if seen_count >= _MAX_WORDS then
                        break
                    end
                end
            end
        end

        if seen_count >= _MAX_WORDS then
            break
        end
    end

    ---@type {score: integer, word: string}[]
    local ranked_words = {}

    for word, score in pairs(scores) do
        table.insert(ranked_words, { score = score, word = word })
    end

    table.sort(ranked_words, function(left, right)
        if left.score == right.score then
            return left.word < right.word
        end

        return left.score < right.score
    end)

    ---@type _my.completion.Entry[]
    local matches = {}

    for _, ranked_word in ipairs(ranked_words) do
        table.insert(matches, {
            kind = "Text",
            menu = "buffer",
            word = ranked_word.word,
        })
    end

    return matches
end

--- Return true if Neovim is currently in insert mode.
---
---@return boolean # Whether buffer-word completion may run.
function _P.is_insert_mode()
    return vim.api.nvim_get_mode().mode == "i"
end

--- Trigger buffer-word completion if no stronger completion source is active.
function _P.complete_current_buffer_words()
    local buffer = vim.api.nvim_get_current_buf()

    if not _P.is_insert_mode() then
        return
    end

    if vim.fn.pumvisible() == 1 or _P.should_skip_buffer(buffer) or _P.has_lsp_completion(buffer) then
        return
    end

    local cursor_line, cursor_column = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local start_column, prefix = _P.get_prefix(line, cursor_column)

    if #prefix < _MIN_PREFIX_LENGTH then
        return
    end

    local matches = _P.collect_matches(buffer, prefix, cursor_line)

    if vim.tbl_isempty(matches) then
        return
    end

    vim.opt_local.completeopt = { "fuzzy", "menuone", "noinsert", "noselect" }
    vim.fn.complete(start_column, matches)
end

--- Schedule a debounced buffer-word completion attempt.
function _P.schedule_completion()
    if _TIMER then
        _TIMER:stop()
    else
        _TIMER = assert((vim.uv or vim.loop).new_timer())
    end

    _TIMER:start(_DEBOUNCE_MS, 0, function()
        vim.schedule(_P.complete_current_buffer_words)
    end)
end

vim.api.nvim_create_autocmd("TextChangedI", {
    group = _AUGROUP,
    callback = _P.schedule_completion,
    desc = "Trigger buffer-word completion when no LSP completion is available.",
})

M._P = _P

return M
