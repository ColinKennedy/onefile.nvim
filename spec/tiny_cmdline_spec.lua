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
        assert.is_not_nil(source:find("ext_popupmenu = true", 1, true))
        assert.is_not_nil(source:find("ensure_popupmenu_completion", 1, true))
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
        local original_show_cmdline = cmdline._P.show_cmdline
        local original_flush_redraw = cmdline._P.flush_redraw
        local drew = false
        local flushed = false

        rawset(cmdline._P, "show_cmdline", function(content, position, firstc, prompt, indent)
            drew = true
            assert.same({ { 0, "write" } }, content)
            assert.equal(5, position)
            assert.equal(":", firstc)
            assert.equal("", prompt)
            assert.equal(0, indent)
        end)
        rawset(cmdline._P, "flush_redraw", function()
            flushed = true
        end)

        cmdline._P.schedule_show_cmdline({ { 0, "write" } }, 5, ":", "", 0)

        assert.is_true(vim.wait(1000, function()
            return drew and flushed
        end, 20))

        rawset(cmdline._P, "show_cmdline", original_show_cmdline)
        rawset(cmdline._P, "flush_redraw", original_flush_redraw)
    end)

    it("does not collapse popupmenu height when pumheight is unlimited", function()
        local cmdline = require("modules.plugins.tiny_cmdline")
        vim.o.lines = 40
        vim.o.cmdheight = 1
        vim.o.pumheight = 0

        assert.equal(5, cmdline._P.get_popupmenu_height(5))
    end)

    it("respects positive pumheight for popupmenu height", function()
        local cmdline = require("modules.plugins.tiny_cmdline")
        vim.o.lines = 40
        vim.o.cmdheight = 1
        vim.o.pumheight = 3

        assert.equal(3, cmdline._P.get_popupmenu_height(5))
    end)

    it("anchors completion popupmenu to the centered cmdline cursor", function()
        local cmdline = require("modules.plugins.tiny_cmdline")
        vim.o.columns = 120
        vim.o.lines = 40
        vim.o.cmdheight = 1
        vim.o.pumheight = 5
        cmdline.config.width = { value = "60%", min = 40, max = 80 }
        cmdline.config.position = { x = "50%", y = "50%" }
        cmdline.config.border = "rounded"
        cmdline._P.cursor_column = 7

        local row, column = cmdline._P.get_popupmenu_position(20, 3)

        assert.equal(20, row)
        assert.equal(31, column)
    end)

    it("renders multiple popupmenu entries", function()
        local cmdline = require("modules.plugins.tiny_cmdline")
        vim.o.columns = 120
        vim.o.lines = 40
        vim.o.cmdheight = 1
        vim.o.pumheight = 0
        cmdline.config.width = { value = "60%", min = 40, max = 80 }
        cmdline.config.position = { x = "50%", y = "50%" }
        cmdline.config.border = "rounded"
        cmdline._P.show_cmdline({ { 0, "e Session" } }, 9, ":", "", 0)

        cmdline._P.show_popupmenu({
            { "Session.vim", "", "", "" },
            { "Sessionx.vim", "", "", "" },
            { "Sessionz.vim", "", "", "" },
        }, 1)

        assert.equal(3, vim.api.nvim_win_get_height(cmdline._P.popup_window))
        assert.same({ "Session.vim", "Sessionx.vim", "Sessionz.vim" }, vim.api.nvim_buf_get_lines(cmdline._P.get_popup_buffer(), 0, -1, false))

        cmdline._P.close_window()
    end)

    it("draws a visible cursor block in the non-focusable cmdline float", function()
        local cmdline = require("modules.plugins.tiny_cmdline")
        cmdline._P.show_cmdline({ { 0, "e" } }, 1, ":", "", 0)

        local marks = vim.api.nvim_buf_get_extmarks(cmdline._P.get_buffer(), cmdline._P.namespace, 0, -1, { details = true })

        assert.equal(" ", cmdline._P.get_cursor_text())
        assert.equal(1, #marks)
        assert.same({ { " ", "TinyCmdlineCursor" } }, marks[1][4].virt_text)
        assert.equal("win_col", marks[1][4].virt_text_pos)
        assert.equal(2, marks[1][4].virt_text_win_col)

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
