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

    --- Get the current visual selection's selected line range.
    ---
    ---@return integer # The first selected line.
    ---@return integer # The last selected line.
    local function get_visual_line_range()
        local visual_start = vim.fn.getpos("v")[2]
        local cursor = vim.api.nvim_win_get_cursor(0)

        return math.min(visual_start, cursor[1]), math.max(visual_start, cursor[1])
    end

    --- Assert that visual formatting with `keys` makes `gv` select only touched lines.
    ---
    ---@param keys string The visual formatting keys to press.
    local function assert_reflowed_selection_is_reselected(keys)
        make_buffer({
            "untouched text above the selected region",
            "  example, each module's private functions don't need to be defined in the same modules as the public functions. They could be moved and defer-eval required into the relevant spots. This could make startup time faster, but by how much I don't know", -- luacheck: ignore
            "untouched text below the selected region",
        })
        vim.api.nvim_win_set_cursor(0, { 2, 2 })

        press("v$" .. keys)
        press("gv")

        local start_line, end_line = get_visual_line_range()

        assert.equal("v", vim.fn.mode())
        assert.equal(2, start_line)
        assert.is_true(end_line < vim.api.nvim_buf_line_count(0))
    end

    it("makes gv select only the lines touched by visual gq", function()
        assert_reflowed_selection_is_reselected("gq")
    end)

    it("makes gv select only the lines touched by visual gw", function()
        assert_reflowed_selection_is_reselected("gw")
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
