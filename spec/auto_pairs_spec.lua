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

    return text:gsub("|", ""), column - 1
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

--- Press insert-mode keys and wait for Neovim to process them.
---
---@param keys string The keys to press.
local function press_insert(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("i" .. keys .. "<Esc>", true, false, true), "mx", false)
    vim.wait(100)
end

--- Get the current scratch buffer line.
---
---@return string # The current line.
local function get_line()
    return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
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

            assert.equal(character .. character, get_line())
        end)

        it(string.format("deletes an empty symmetric %s pair with backspace", character), function()
            prepare_buffer(character .. "|" .. character)
            press_insert("<BS>")

            assert.equal("", get_line())
        end)

        it(string.format("keeps the closing %s when deleting a non-empty pair", character), function()
            prepare_buffer(character .. "|a" .. character)
            press_insert("<BS>")

            assert.equal("a" .. character, get_line())
        end)
    end
end)
