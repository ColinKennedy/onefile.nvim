package.path = "lua/?.lua;" .. package.path

describe("modules.plugins.tiny_cmdline", function()
    local columns
    local lines
    local cmdheight

    before_each(function()
        columns = vim.o.columns
        lines = vim.o.lines
        cmdheight = vim.o.cmdheight
        package.loaded["modules.plugins.tiny_cmdline"] = nil
    end)

    after_each(function()
        vim.o.columns = columns
        vim.o.lines = lines
        vim.o.cmdheight = cmdheight
    end)

    it("uses local _my.cmdline LuaCATS annotations", function()
        local source = table.concat(vim.fn.readfile("lua/modules/plugins/tiny_cmdline.lua"), "\n")

        assert.is_not_nil(source:find("_my.cmdline.WidthConfiguration", 1, true))
        assert.is_not_nil(source:find("_my.cmdline.PositionConfiguration", 1, true))
        assert.is_not_nil(source:find("_my.cmdline.Configuration", 1, true))
        assert.is_nil(source:find("TinyCmdlineWidthConfig", 1, true))
        assert.is_nil(source:find("TinyCmdlinePositionConfig", 1, true))
        assert.is_nil(source:find("TinyCmdlineConfig", 1, true))
    end)

    it("attaches only to the cmdline UI and leaves messages native", function()
        local source = table.concat(vim.fn.readfile("lua/modules/plugins/tiny_cmdline.lua"), "\n")

        assert.is_not_nil(source:find("ext_cmdline = true", 1, true))
        assert.is_nil(source:find("ext_messages", 1, true))
        assert.is_nil(source:find("vim._core.ui2", 1, true))
    end)

    it("keeps a message row for native printouts and :messages", function()
        vim.o.cmdheight = 2

        local cmdline = require("modules.plugins.tiny_cmdline")
        cmdline._P.ensure_message_row()

        assert.equal(1, vim.o.cmdheight)
    end)

    it("resolves percent dimensions and clamps configured width", function()
        local cmdline = require("modules.plugins.tiny_cmdline")
        vim.o.columns = 100
        vim.o.lines = 40
        cmdline.config.width = { value = "60%", min = 40, max = 80 }
        cmdline.config.position = { x = "50%", y = "50%" }
        cmdline.config.border = "rounded"

        local width, row, column, border_width = cmdline._P.get_geometry(1)

        assert.equal(60, width)
        assert.equal(18, row)
        assert.equal(19, column)
        assert.equal(1, border_width)
    end)

    it("schedules cmdline drawing outside the ui callback", function()
        local cmdline = require("modules.plugins.tiny_cmdline")
        cmdline._P.schedule_show_cmdline({ { 0, "write" } }, 5, ":", "", 0)

        assert.is_true(vim.wait(1000, function()
            return cmdline._P.window ~= nil and vim.api.nvim_win_is_valid(cmdline._P.window)
        end, 20))
        assert.equal(":write", vim.api.nvim_buf_get_lines(cmdline._P.get_buffer(), 0, 1, false)[1])

        cmdline._P.close_window()
    end)

    it("renders command chunks with prefixes and prompt indentation", function()
        local cmdline = require("modules.plugins.tiny_cmdline")

        local line = cmdline._P.render_line({ { 0, "write" } }, ":", "", 0)
        local prompted = cmdline._P.render_line({ { 0, "value" } }, "=", "Input: ", 2)

        assert.equal(":write", line)
        assert.equal("=Input:   value", prompted)
    end)
end)
