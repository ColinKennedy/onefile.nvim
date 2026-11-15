--- Manage search highlighting so matches clear when the cursor leaves them.

local _P = {}

-- Reference: https://github.com/vim/vim/issues/17187#issuecomment-2820531752
local _GROUP = vim.api.nvim_create_augroup("my.highlighter.word_search", { clear = true })
local _PLUG_MAPPING = "<Plug>(StopHL)"

vim.keymap.set({ "n", "i" }, _PLUG_MAPPING, function()
    vim.cmd("nohlsearch")
end, { desc = "Cancel search highlights.", expr = false })

--- Stop highlighting search results, if needed. Basically it's a fancier `:nohlsearch`.
function _P.stop_highlighting_search_text()
    if vim.v.hlsearch == 0 or vim.api.nvim_get_mode().mode ~= "n" then
        return
    end

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(_PLUG_MAPPING, true, false, true), "m", false)
end

--- Highlight searched text until the cursor moves away from one of the matches.
function _P.highlight_search_text()
    local line = vim.api.nvim_get_current_line()
    local col = vim.fn.col(".")
    local pattern = vim.fn.getreg("/")

    -- A pattern with NUL bytes becomes a Blob in vim.fn, and `match()` rejects those.
    if pattern:find("\0", 1, true) then
        return
    end

    -- match() returns 0-based index, or -1
    local pos = vim.fn.match(line, pattern, col - 1) + 1

    if pos ~= col then
        _P.stop_highlighting_search_text()
    end
end

--- Track the cursor in `buffer`, unless it looks binary (NUL bytes become Blobs in `vim.fn.match`, E976).
---
---@param buffer integer A 0-or-more buffer number.
---
function _P.register_cursor_tracking(buffer)
    local first_line = vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] or ""

    if first_line:find("\0", 1, true) then
        return
    end

    if #vim.api.nvim_get_autocmds({ group = _GROUP, event = "CursorMoved", buffer = buffer }) > 0 then
        return
    end

    vim.api.nvim_create_autocmd("CursorMoved", {
        group = _GROUP,
        buffer = buffer,
        callback = _P.highlight_search_text,
    })
end

vim.api.nvim_create_autocmd("BufEnter", {
    group = _GROUP,
    callback = function(event)
        _P.register_cursor_tracking(event.buf)
    end,
})

vim.api.nvim_create_autocmd("InsertEnter", {
    group = _GROUP,
    callback = _P.stop_highlighting_search_text,
})
