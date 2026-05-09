local M = {}

--- Add an automated winbar title to the Quickfix window.
---@return string # The recommended Quickfix window title, if any is defined.
function M.get_quickfix_winbar_title()
    local info = vim.fn.getqflist({ title = 0 })

    return info.title or "Quickfix"
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = "qf",
    callback = function(args)
        local window = vim.fn.bufwinid(args.buf)

        if window == -1 then
            return
        end

        vim.wo[window].winbar =
            "%{luaeval('require(\"modules.features.quickfix_winbar\").get_quickfix_winbar_title()')}"
    end,
})

return M
