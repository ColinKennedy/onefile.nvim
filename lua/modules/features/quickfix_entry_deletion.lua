--- Delete quickfix / location list entries with `dd`-style mappings.
---
--- Quickfix buffers are not modifiable so `d` is remapped to a function that
--- rewrites the underlying quickfix list instead of the buffer text.

local M = {}

local _P = {}

--- Check if `window` shows a location list instead of a quickfix list.
---
---@param window integer The quickfix-style window to inspect.
---@return boolean # If `window` shows a location list, return `true`.
function _P.is_location_list(window)
    local information = vim.fn.getwininfo(window)[1]

    return information ~= nil and information.loclist == 1
end

--- Get every entry shown in `window`, plus the metadata needed to restore it.
---
---@param window integer The quickfix-style window to inspect.
---@return table # The `getqflist()` / `getloclist()` dictionary.
function _P.get_list(window)
    if _P.is_location_list(window) then
        return vim.fn.getloclist(window, { all = 0 })
    end

    return vim.fn.getqflist({ all = 0 })
end

--- Replace the list shown in `window` with `data`.
---
---@param window integer The quickfix-style window to modify.
---@param data table The `setqflist()` / `setloclist()` dictionary to apply.
function _P.set_list(window, data)
    if _P.is_location_list(window) then
        vim.fn.setloclist(window, {}, "r", data)

        return
    end

    vim.fn.setqflist({}, "r", data)
end

--- Move the cursor of `window` onto `line`, as far as the buffer allows.
---
---@param window integer The quickfix-style window to modify.
---@param line integer The 1-or-more line to select.
function _P.restore_cursor(window, line)
    if not vim.api.nvim_win_is_valid(window) then
        return
    end

    local count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(window))

    vim.api.nvim_win_set_cursor(window, { math.max(math.min(line, count), 1), 0 })
end

--- Get the line range that a visual selection currently covers.
---
---@return integer # The first selected line.
---@return integer # The last selected line.
function _P.get_visual_range()
    local start_line = vim.fn.line("v")
    local end_line = vim.fn.line(".")

    if start_line > end_line then
        return end_line, start_line
    end

    return start_line, end_line
end

--- Read the rest of a `d{count}d` key sequence and return the requested count.
---
--- It's assumed that the user already pressed `d`. If they type anything other
--- than digits followed by another `d`, the sequence is cancelled.
---
---@return integer? # The number of lines to delete, if the sequence completed.
function _P.get_pending_delete_count()
    local count = vim.v.count1
    local digits = ""

    while true do
        local success, character = pcall(vim.fn.getcharstr)

        if not success or character == nil or character == "" then
            return nil
        end

        if character:match("^%d$") and not (character == "0" and digits == "") then
            digits = digits .. character
        elseif character == "d" then
            return count * math.max(tonumber(digits) or 1, 1)
        else
            return nil
        end
    end
end

--- Remove the entries on lines `start_line` to `end_line` from `window`.
---
--- The quickfix list itself is rewritten so the removal sticks even after the
--- quickfix window is closed and reopened.
---
---@param window integer The quickfix or location list window to modify.
---@param start_line integer The first 1-or-more entry line to remove.
---@param end_line integer The last 1-or-more entry line to remove.
---@return integer # The number of entries that were removed.
function M.delete_entries(window, start_line, end_line)
    if not vim.api.nvim_win_is_valid(window) then
        return 0
    end

    local data = _P.get_list(window)
    local items = data.items or {}

    start_line = math.max(start_line, 1)
    end_line = math.min(end_line, #items)

    if start_line > end_line then
        return 0
    end

    ---@type table[]
    local kept = {}

    for index, item in ipairs(items) do
        if index < start_line or index > end_line then
            table.insert(kept, item)
        end
    end

    local replacement = { items = kept, title = data.title }

    if data.context ~= nil and data.context ~= "" then
        replacement.context = data.context
    end

    if data.quickfixtextfunc ~= nil and data.quickfixtextfunc ~= "" then
        replacement.quickfixtextfunc = data.quickfixtextfunc
    end

    if not vim.tbl_isempty(kept) then
        replacement.idx = math.min(start_line, #kept)
    end

    _P.set_list(window, replacement)
    _P.restore_cursor(window, start_line)

    return end_line - start_line + 1
end

--- Delete the entries under the cursor, following a `{count}d{count}d` sequence.
function _P.delete_from_normal_mode()
    local count = _P.get_pending_delete_count()

    if not count then
        return
    end

    local window = vim.api.nvim_get_current_win()
    local line = vim.fn.line(".")

    M.delete_entries(window, line, line + count - 1)
end

--- Delete every entry that the current visual selection touches.
function _P.delete_from_visual_mode()
    local window = vim.api.nvim_get_current_win()
    local start_line, end_line = _P.get_visual_range()

    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)

    M.delete_entries(window, start_line, end_line)
end

--- Add the entry-deletion mappings to `buffer`.
---
---@param buffer integer The quickfix or location list buffer to modify.
function M.setup_mappings(buffer)
    vim.keymap.set("n", "d", _P.delete_from_normal_mode, {
        buffer = buffer,
        desc = "Delete [count] quickfix entries, as in `dd` or `d2d`.",
    })

    for _, key in ipairs({ "d", "x" }) do
        vim.keymap.set("x", key, _P.delete_from_visual_mode, {
            buffer = buffer,
            desc = "Delete the selected quickfix entries.",
        })
    end
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = "qf",
    callback = function(arguments)
        M.setup_mappings(arguments.buf)
    end,
})

return M
