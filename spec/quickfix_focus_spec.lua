local core_editor_setup = require("modules.features.core_editor_setup")

local function close_quickfix()
    pcall(vim.cmd.cclose)
end

describe("quickfix focus mapping", function()
    before_each(function()
        close_quickfix()
        vim.cmd.enew({ bang = true })
    end)

    after_each(function()
        close_quickfix()
        vim.cmd.enew({ bang = true })
    end)

    it("switches to an open quickfix window", function()
        local source_window = vim.api.nvim_get_current_win()

        vim.fn.setqflist({
            {
                bufnr = vim.api.nvim_get_current_buf(),
                lnum = 1,
                col = 1,
                text = "test quickfix entry",
            },
        })
        vim.cmd.copen()

        local quickfix_window = vim.fn.getqflist({ winid = true }).winid
        vim.api.nvim_set_current_win(source_window)

        assert.True(core_editor_setup.focus_quickfix())
        assert.equal(quickfix_window, vim.api.nvim_get_current_win())
    end)

    it("does not open quickfix or move the cursor when quickfix is closed", function()
        local source_window = vim.api.nvim_get_current_win()

        close_quickfix()

        assert.False(core_editor_setup.focus_quickfix())
        assert.equal(source_window, vim.api.nvim_get_current_win())
        assert.equal(0, vim.fn.getqflist({ winid = true }).winid)
    end)

    it("maps Space-q to focus the quickfix window", function()
        require("modules.features.keymaps")

        local mapping = vim.fn.maparg("<Space>q", "n", false, true)

        assert.is_function(mapping.callback)
        assert.equal("Switch the cursor to the [q]uickfix window, if open.", mapping.desc)
    end)
end)
