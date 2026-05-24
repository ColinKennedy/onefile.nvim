package.path = "lua/?.lua;" .. package.path
describe("modules.plugins.tiny_cmdline", function()
    local columns
    local lines

    before_each(function()
        columns = vim.o.columns
        lines = vim.o.lines
        package.loaded["modules.plugins.tiny_cmdline"] = nil
    end)

    after_each(function()
        vim.o.columns = columns
        vim.o.lines = lines
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

    it("routes regular ui2 messages away from the pager-prone cmd target", function()
        local source = table.concat(vim.fn.readfile("lua/modules/plugins/tiny_cmdline.lua"), "\n")

        assert.is_not_nil(source:find("target = \"msg\"", 1, true))
        assert.is_not_nil(source:find("timeout = 2500", 1, true))
    end)

    it("keeps a message row to avoid ui2 pager/statusline churn", function()
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
end)
