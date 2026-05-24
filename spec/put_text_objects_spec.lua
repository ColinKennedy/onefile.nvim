require("modules.features.put_text_objects")

--- Create a scratch buffer with one line and place the cursor.
---
---@param line string The buffer line.
---@param column integer The 0-or-more cursor column.
local function make_buffer(line, column)
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { line })
    vim.api.nvim_win_set_cursor(0, { 1, column })
end

--- Press normal-mode keys and wait for them to finish.
---
---@param keys string The normal-mode keys to press.
local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
    vim.wait(50)
end

--- Get the current buffer's first line.
---
---@return string # The first line.
local function get_line()
    return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
end

describe("put text objects", function()
    after_each(function()
        vim.cmd("silent enew!")
    end)

    it("replaces an inner word after a slash without moving the slash", function()
        vim.fn.setreg('"', "new", "c")
        make_buffer("foo/bar/xthing", #"foo/bar/")

        press("piw")

        assert.equal("foo/bar/new", get_line())
    end)
end)
