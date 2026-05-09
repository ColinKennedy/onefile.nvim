local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
    --- Add an automated winbar title to the Quickfix window.
    ---@return string # The recommended Quickfix window title, if any is defined.
    function _P.get_quickfix_winbar_title()
        local info = vim.fn.getqflist({ title = 0 })

        return info.title or "Quickfix"
    end

    _G.get_quickfix_winbar_title = _P.get_quickfix_winbar_title

    vim.api.nvim_create_autocmd("FileType", {
        pattern = "qf",
        callback = function(args)
            local window = vim.fn.bufwinid(args.buf)

            if window == -1 then
                return
            end

            vim.wo[window].winbar = "%{%v:lua.get_quickfix_winbar_title()%}"
        end,
    })
end)
