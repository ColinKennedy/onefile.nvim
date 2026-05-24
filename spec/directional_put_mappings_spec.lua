local directional_put = require("modules.features.directional_put_mappings")

--- Create a scratch buffer with `lines`.
---
---@param lines string[] Initial buffer lines.
---@return integer # The new scratch buffer.
---
local function make_buffer(lines)
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo.expandtab = true
    vim.bo.shiftwidth = 4
    vim.bo.tabstop = 4

    return buffer
end

--- Set the unnamed register to linewise `lines`.
---
---@param lines string[] Lines to make available to put mappings.
---
local function set_register(lines)
    vim.fn.setreg('"', lines, "l")
end

--- Get all lines in the current buffer.
---
---@return string[] # Buffer contents.
---
local function get_lines()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

describe("directional put mappings", function()
    after_each(function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    end)

    it("puts below at the current indentation and preserves internal indentation", function()
        make_buffer({ "    current", "done" })
        set_register({ "        alpha", "            beta" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        directional_put.put_linewise("below", "same")

        assert.same({
            "    current",
            "    alpha",
            "        beta",
            "done",
        }, get_lines())
    end)

    it("puts above at the current indentation", function()
        make_buffer({ "start", "    current" })
        set_register({ "        alpha", "            beta" })
        vim.api.nvim_win_set_cursor(0, { 2, 0 })

        directional_put.put_linewise("above", "same")

        assert.same({
            "start",
            "    alpha",
            "        beta",
            "    current",
        }, get_lines())
    end)

    it("adds one shiftwidth for indenting puts", function()
        make_buffer({ "    current", "done" })
        set_register({ "        alpha", "            beta" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        directional_put.put_linewise("below", "indent")

        assert.same({
            "    current",
            "        alpha",
            "            beta",
            "done",
        }, get_lines())
    end)

    it("removes one shiftwidth without breaking internal indentation", function()
        make_buffer({ "        current", "done" })
        set_register({ "        alpha", "            beta" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        directional_put.put_linewise("below", "dedent")

        assert.same({
            "        current",
            "    alpha",
            "        beta",
            "done",
        }, get_lines())
    end)

    it("dedents only to column zero", function()
        make_buffer({ "  current", "done" })
        set_register({ "        alpha", "            beta" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        directional_put.put_linewise("below", "dedent")

        assert.same({
            "  current",
            "alpha",
            "    beta",
            "done",
        }, get_lines())
    end)

    it("uses tabs for added indentation when the buffer does not expand tabs", function()
        make_buffer({ "\tcurrent", "done" })
        vim.bo.expandtab = false
        set_register({ "\t\talpha", "\t\t\tbeta" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        directional_put.put_linewise("below", "indent")

        assert.same({
            "\tcurrent",
            "\t\talpha",
            "\t\t\tbeta",
            "done",
        }, get_lines())
    end)

    it("selects the last custom put with gp", function()
        make_buffer({ "    current", "done" })
        set_register({ "        alpha", "            beta" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        directional_put.put_linewise("below", "same")

        directional_put.select_last_put()

        local visual_start = vim.fn.getpos("v")[2]
        local cursor = vim.api.nvim_win_get_cursor(0)
        assert.equal("V", vim.fn.mode())
        assert.equal(2, math.min(visual_start, cursor[1]))
        assert.equal(3, math.max(visual_start, cursor[1]))
    end)

    it("selects text inserted with an Ex put using Vim's native put marks", function()
        make_buffer({ "current", "done" })
        set_register({ "alpha", "beta" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        vim.cmd(":+put")
        assert.same({ "current", "done", "alpha", "beta" }, get_lines())
        directional_put.select_last_put()

        local visual_start = vim.fn.getpos("v")[2]
        local cursor = vim.api.nvim_win_get_cursor(0)
        assert.equal("V", vim.fn.mode())
        assert.equal(3, math.min(visual_start, cursor[1]))
        assert.equal(4, math.max(visual_start, cursor[1]))
    end)
end)
