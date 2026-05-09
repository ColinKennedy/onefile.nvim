local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
mouse=a-- Reference: https://github.com/vim/vim/issues/17187#issuecomment-2820531752
_GROUP = vim.api.nvim_create_augroup("my.highlighter.word_search", { clear = true })
_PLUG_MAPPING = "<Plug>(StopHL)"

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

    -- match() returns 0-based index, or -1
    local pos = vim.fn.match(line, pattern, col - 1) + 1

    if pos ~= col then
        _P.stop_highlighting_search_text()
    end
end

vim.api.nvim_create_autocmd("CursorMoved", {
    group = _GROUP,
    callback = _P.highlight_search_text,
})

vim.api.nvim_create_autocmd("InsertEnter", {
    group = _GROUP,
    callback = _P.stop_highlighting_search_text,
})
end)
