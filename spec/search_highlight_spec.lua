describe("search highlight", function()
    after_each(function()
        vim.cmd.enew({ bang = true })
        vim.cmd.nohlsearch()
    end)

    it("does not error on lines containing NUL bytes", function()
        local buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(buffer)
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "ab\0cd abc" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.fn.setreg("/", "abc")

        vim.v.errmsg = ""
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buffer })

        assert.equal("", vim.v.errmsg)
    end)
end)
