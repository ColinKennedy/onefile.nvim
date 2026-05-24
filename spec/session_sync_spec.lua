describe("session sync", function()
    local original_shortmess
    local original_more

    before_each(function()
        original_shortmess = vim.o.shortmess
        original_more = vim.o.more
    end)

    after_each(function()
        vim.o.shortmess = original_shortmess
        vim.o.more = original_more
    end)

    it("quiets noisy file messages while a session is loading", function()
        local session_sync = require("modules.features.session_sync")
        vim.o.shortmess = "filnxtToO"
        vim.o.more = true

        session_sync.start_quiet_session_load()

        assert.is_truthy(vim.o.shortmess:find("F", 1, true))
        assert.is_false(vim.o.more)

        session_sync.stop_quiet_session_load()
        vim.wait(1000, function()
            return vim.o.shortmess == "filnxtToO" and vim.o.more == true
        end, 20)

        assert.equal("filnxtToO", vim.o.shortmess)
        assert.is_true(vim.o.more)
    end)
end)
