require("modules.features.auto_pairs")

--- Parse a cursor marker from one test line.
---
---@param text string The test text containing `|`.
---@return string # The text without the marker.
---@return integer # The zero-indexed cursor column.
local function parse_cursor(text)
    local column = text:find("|", 1, true)

    if not column then
        error("No cursor marker was found.", 0)
    end

    local line = text:gsub("|", "")

    return line, column - 1
end

--- Prepare a scratch buffer with one marked cursor position.
---
---@param text string The line text with a `|` cursor marker.
local function prepare_buffer(text)
    local line, column = parse_cursor(text)
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { line })
    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_win_set_cursor(0, { 1, column })
end

--- Prepare a scratch buffer with raw text and cursor.
---
---@param lines string[] The lines to place in the buffer.
---@param cursor integer[] The 1-indexed row and 0-indexed column cursor position.
local function prepare_raw_buffer(lines, cursor)
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_win_set_cursor(0, cursor)
end

--- Press insert-mode keys and wait for Neovim to process them.
---
---@param keys string The keys to press.
local function press_insert(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("i" .. keys .. "<Esc>", true, false, true), "mx", false)
    vim.wait(100)
end

--- Get the current scratch buffer lines.
---
---@return string[] # The current lines.
local function get_lines()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

--- Get the current 1-indexed cursor position.
---
---@return integer[]
local function get_cursor()
    local row, column = unpack(vim.api.nvim_win_get_cursor(0))

    return { row, column }
end

describe("auto pairs", function()
    after_each(function()
        pcall(vim.cmd.stopinsert)
        vim.cmd.enew({ bang = true })
    end)

    for _, character in ipairs({ '"', "'", "`" }) do
        it(string.format("creates a symmetric %s pair", character), function()
            prepare_buffer("|")
            press_insert(character)

            assert.are.same({ character .. character }, get_lines())
        end)

        it(string.format("deletes an empty symmetric %s pair with backspace", character), function()
            prepare_buffer(character .. "|" .. character)
            press_insert("<BS>")

            assert.are.same({ "" }, get_lines())
        end)

        it(string.format("keeps the closing %s when deleting a non-empty pair", character), function()
            prepare_buffer(character .. "|a" .. character)
            press_insert("<BS>")

            assert.are.same({ "a" .. character }, get_lines())
        end)
    end

    it("splits braces with one normal indentation level in Python", function()
        prepare_buffer("|")
        vim.bo.filetype = "python"
        vim.bo.expandtab = true
        vim.bo.shiftwidth = 4
        vim.bo.tabstop = 4

        press_insert("{<CR>")

        assert.are.same({
            "{",
            "    ",
            "}",
        }, get_lines())
        assert.are.same({ 2, 3 }, get_cursor())
    end)

    it("splits nested braces with one extra indentation level", function()
        prepare_raw_buffer({ "    {}" }, { 1, 5 })
        vim.bo.expandtab = true
        vim.bo.shiftwidth = 4
        vim.bo.tabstop = 4

        press_insert("<CR>")

        assert.are.same({
            "    {",
            "        ",
            "    }",
        }, get_lines())
        assert.are.same({ 2, 7 }, get_cursor())
    end)
end)
