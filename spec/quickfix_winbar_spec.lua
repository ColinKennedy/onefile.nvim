local quickfix_winbar = require("modules.features.quickfix_winbar")

--- Close the quickfix and location list windows, if they are open.
local function close_quickfix()
    pcall(vim.cmd.cclose)
    pcall(vim.cmd.lclose)
end

--- Get the rendered winbar text of `window`.
---
---@param window integer The window to inspect.
---@return string # The visible winbar text.
local function get_rendered_winbar(window)
    return vim.api.nvim_eval_statusline(vim.wo[window].winbar, { winid = window, use_winbar = true }).str
end

describe("quickfix winbar", function()
    before_each(function()
        close_quickfix()
        vim.cmd.enew({ bang = true })
    end)

    after_each(function()
        close_quickfix()
        vim.cmd.enew({ bang = true })
    end)

    it("shows the quickfix title in the quickfix winbar", function()
        vim.fn.setqflist({}, " ", {
            items = { { bufnr = vim.api.nvim_get_current_buf(), lnum = 1, col = 1, text = "some entry" } },
            title = "Some Quickfix Title",
        })
        vim.cmd.copen({ mods = { silent = true } })

        local window = vim.fn.getqflist({ winid = true }).winid

        assert.equal(quickfix_winbar.WINBAR_EXPRESSION, vim.wo[window].winbar)
        assert.equal(" Some Quickfix Title", get_rendered_winbar(window))
    end)

    it("follows the quickfix title when it changes", function()
        vim.fn.setqflist({}, " ", {
            items = { { bufnr = vim.api.nvim_get_current_buf(), lnum = 1, col = 1, text = "some entry" } },
            title = "First Title",
        })
        vim.cmd.copen({ mods = { silent = true } })

        local window = vim.fn.getqflist({ winid = true }).winid

        vim.fn.setqflist({}, "r", { title = "Second Title" })

        assert.equal(" Second Title", get_rendered_winbar(window))
    end)

    it("falls back to a default title when the quickfix list has no title", function()
        vim.fn.setqflist({}, " ", {
            items = { { bufnr = vim.api.nvim_get_current_buf(), lnum = 1, col = 1, text = "some entry" } },
            title = "",
        })
        vim.cmd.copen({ mods = { silent = true } })

        local window = vim.fn.getqflist({ winid = true }).winid

        assert.equal(" Quickfix", get_rendered_winbar(window))
    end)

    it("shows the location list title in a location list window", function()
        local source_window = vim.api.nvim_get_current_win()

        vim.fn.setloclist(source_window, {}, " ", {
            items = { { bufnr = vim.api.nvim_get_current_buf(), lnum = 1, col = 1, text = "some entry" } },
            title = "Some Location Title",
        })
        vim.cmd.lopen({ mods = { silent = true } })

        local window = vim.api.nvim_get_current_win()

        assert.equal(" Some Location Title", get_rendered_winbar(window))
    end)
end)
