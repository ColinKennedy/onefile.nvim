package.path = "lua/?.lua;" .. package.path

describe("modules.plugins.tiny_cmdline", function()
    local columns
    local lines
    local cmdheight
    local wildoptions
    local ui_cmdline_pos

    before_each(function()
        columns = vim.o.columns
        lines = vim.o.lines
        cmdheight = vim.o.cmdheight
        wildoptions = vim.o.wildoptions
        ui_cmdline_pos = vim.g.ui_cmdline_pos
        package.loaded["modules.plugins.tiny_cmdline"] = nil
    end)

    after_each(function()
        vim.o.columns = columns
        vim.o.lines = lines
        vim.o.cmdheight = cmdheight
        vim.o.wildoptions = wildoptions
        vim.g.ui_cmdline_pos = ui_cmdline_pos
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

    it("uses ui2 instead of a hand-rolled ext_cmdline renderer", function()
        local source = table.concat(vim.fn.readfile("lua/modules/plugins/tiny_cmdline.lua"), "\n")

        assert.is_not_nil(source:find("vim._core.ui2", 1, true))
        assert.is_not_nil(source:find("ui2.enable", 1, true))
        assert.is_not_nil(source:find("enable_ui2", 1, true))
        assert.is_nil(source:find("vim.ui_attach(_P.namespace", 1, true))
    end)

    it("keeps command-line completion in popupmenu mode", function()
        local cmdline = require("modules.plugins.tiny_cmdline")
        vim.o.wildoptions = ""

        cmdline._P.ensure_popupmenu_completion()

        assert.is_true(vim.tbl_contains(vim.opt.wildoptions:get(), "pum"))
    end)

    it("routes noisy long print-style messages to the ui2 pager", function()
        local cmdline = require("modules.plugins.tiny_cmdline")

        assert.equal("cmd", cmdline.config.msg.target)
        assert.equal("pager", cmdline.config.msg.targets.typed_cmd)
        assert.equal("pager", cmdline.config.msg.targets.list_cmd)
        assert.equal("pager", cmdline.config.msg.targets.lua_print)
    end)

    it("does not force cmdheight to zero", function()
        local source = table.concat(vim.fn.readfile("lua/modules/plugins/tiny_cmdline.lua"), "\n")
        local cmdline = require("modules.plugins.tiny_cmdline")
        local ui2 = {}
        cmdline._P.ui2 = ui2
        vim.o.cmdheight = 2

        cmdline._P.keep_configured_cmdheight()

        assert.equal(2, vim.o.cmdheight)
        assert.equal(2, ui2.cmdheight)
        assert.is_nil(source:find("vim.o.cmdheight = 0", 1, true))
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

    it("centers the ui2 cmdline window and exposes the completion anchor", function()
        local cmdline = require("modules.plugins.tiny_cmdline")
        local buffer = vim.api.nvim_create_buf(false, true)
        local window = vim.api.nvim_open_win(buffer, false, {
            relative = "editor",
            row = 39,
            col = 0,
            width = 120,
            height = 1,
            style = "minimal",
        })
        local ui2 = {
            wins = { cmd = window },
        }
        cmdline._P.ui2 = ui2
        cmdline._P.cmdline_type = ":"
        vim.o.columns = 120
        vim.o.lines = 40
        cmdline.config.width = { value = "60%", min = 40, max = 80 }
        cmdline.config.position = { x = "50%", y = "50%" }
        cmdline.config.border = "rounded"
        cmdline.config.menu_col_offset = 3

        cmdline._P.reposition()

        local config = vim.api.nvim_win_get_config(window)
        assert.equal("editor", config.relative)
        assert.equal(18, config.row)
        assert.equal(23, config.col)
        assert.equal(72, config.width)
        assert.same({ 21, 27 }, vim.g.ui_cmdline_pos)

        vim.api.nvim_win_close(window, true)
    end)

    it("restores native/search cmdline types to a bottom position", function()
        local cmdline = require("modules.plugins.tiny_cmdline")
        local buffer = vim.api.nvim_create_buf(false, true)
        local window = vim.api.nvim_open_win(buffer, false, {
            relative = "editor",
            row = 10,
            col = 10,
            width = 20,
            height = 1,
            style = "minimal",
        })
        cmdline._P.ui2 = { wins = { cmd = window } }
        cmdline._P.cmdline_type = "/"
        vim.o.columns = 120
        vim.o.lines = 40

        cmdline._P.reposition()

        local config = vim.api.nvim_win_get_config(window)
        assert.equal(39, config.row)
        assert.equal(0, config.col)
        assert.equal(120, config.width)

        vim.api.nvim_win_close(window, true)
    end)
end)
