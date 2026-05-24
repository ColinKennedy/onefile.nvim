local reflow = require("modules.features.reflow_visual_selection")

--- Create a scratch buffer with `lines`.
---
---@param lines string[] The buffer lines.
local function make_buffer(lines)
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo.textwidth = 38
end

--- Press normal-mode keys and wait for queued work.
---
---@param keys string The keys to press.
local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
    vim.wait(50)
end

describe("reflow visual selection", function()
    after_each(function()
        vim.cmd("silent enew!")
    end)

    --- Assert that visual formatting with `keys` makes `gv` select the reflowed paragraph.
    ---
    ---@param keys string The visual formatting keys to press.
    local function assert_reflowed_paragraph_is_reselected(keys)
        make_buffer({
            "a really long text block that just seems to extend to infinity and it just goes on and on",
        })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        press("V" .. keys)
        press("gv")

        local visual_start = vim.fn.getpos("v")[2]
        local cursor = vim.api.nvim_win_get_cursor(0)
        local line_count = vim.api.nvim_buf_line_count(0)

        assert.equal("V", vim.fn.mode())
        assert.equal(1, math.min(visual_start, cursor[1]))
        assert.equal(line_count, math.max(visual_start, cursor[1]))
    end

    it("makes gv select the paragraph created by visual gq", function()
        assert_reflowed_paragraph_is_reselected("gq")
    end)

    it("makes gv select the paragraph created by visual gw", function()
        assert_reflowed_paragraph_is_reselected("gw")
    end)

    it("finds the paragraph around a reflowed line", function()
        make_buffer({
            "",
            "alpha",
            "beta",
            "",
            "gamma",
        })

        local start_line, end_line = reflow._P.get_paragraph_range(3)

        assert.equal(2, start_line)
        assert.equal(3, end_line)
    end)
end)
