---@class _BeforeOptions Details that explain how to set up a unittest buffer.
---@field text string The text to set on the buffer.
---@field options fun(buffer: integer): nil Extra details to call on the buffer, if anything.

---@class _Cursor The row and column of some Neovim cursor position.
---@field [1] integer The row. A 1-or-more value.
---@field [2] integer The column. A 0-or-more value.

local _P = {}
local _LINE_SEPARATOR = "\n"

--- Remove all common, leading whitespace for all of `lines`.
---
---@param lines string[] Some multi-line string that we assume has leading indents.
---@return string[] # The stripped text.
---
function _P.dedent_lines(lines)
    local indent_size = math.huge
    ---@type string[]
    local output = {}

    for _, line in ipairs(lines) do
        local _, left_indent = line:find("^%s*[^%s]")

        if left_indent and left_indent < indent_size then
            indent_size = left_indent
        end
    end

    for _, line in ipairs(lines) do
        table.insert(output, line:sub(indent_size, -1))
    end

    return output
end

--- Remove all common, leading whitespace for all lines in `text`.
---
---@param text string Some multi-line string that we assume has leading indents.
---@return string # The stripped text.
---
function _P.dedent(text)
    return vim.fn.join(_P.dedent_lines(vim.split(text, _LINE_SEPARATOR)), _LINE_SEPARATOR)
end

--- Create a new buffer + window and fill it with `text`.
---
---@param text string All of the text to fill in the buffer.
---@return integer # The 1-or-more value of the created buffer.
---
function _P.make_temporary_buffer(text)
    local buffer = vim.api.nvim_create_buf(false, true)

    local lines = vim.split(text, _LINE_SEPARATOR)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)

    return buffer
end

--- Find a `"|cursor|"` marker in `lines`, remove it, and then return everything.
---
--- Raises:
---     If no `"|cursor|"` marker was found.
---
---@param text string[] The raw line data to check.
---@return string[] # The modified `text`, with the `"|cursor|"` removed.
---@return _Cursor[] # The found row (1-or-more) and column (0-or-more) positions.
---
function _P.parse_cursor(text)
    local found_row
    local found_column

    ---@type string[]
    local lines = {}
    ---@type _Cursor[]
    local cursors = {}

    for row, line in ipairs(text) do
        local start_column = line:find("|cursor|", 1, true)

        if start_column then
            -- NOTE: Neovim API columns are 0-or-more values
            local column = start_column - 1
            found_column = column
            found_row = row

            table.insert(lines, (line:gsub("|cursor|", "")))
            table.insert(cursors, { found_row, found_column })
        else
            table.insert(lines, line)
        end
    end

    if vim.tbl_isempty(cursors) then
        error("No |cursor| marker was found. Cannot continue.", 0)
    end

    return lines, cursors
end

--- Parse `text` for a |cursor| marker, remove it, and then return everything.
---
---@param text string Some raw unittest string like `"foo|cursor|bar"`.
---@return string # The modified `text`, with the `"|cursor|"` removed.
---@return _Cursor[] # The found row (1-or-more) and column (0-or-more) positions.
---
function _P.setup_cursor_text(text)
    local lines = _P.dedent_lines(vim.split(text, _LINE_SEPARATOR))
    local cursors
    lines, cursors = _P.parse_cursor(lines)
    text = vim.fn.join(lines, _LINE_SEPARATOR)

    return text, cursors
end

--- Test that `before` become `expected` after `callback` runs.
---
---@param callbacks (fun(): nil)[] | fun(): nil
---    The behavior that we're trying to test.
---@param before_options string | _BeforeOptions
---    Some buffer text to test with.
---@param expected string
---    The buffer result after `callback` runs.
---@param strict boolean?
---    If `true`, the number of cursors in `before` must match `callbacks`.
---
function _P.assert_keys_with_buffer(callbacks, before_options, expected, strict)
    if type(callbacks) == "function" then
        callbacks = { callbacks }
    end

    if type(before_options) == "string" then
        before_options = { text = before_options, options = function() end }
    end

    local before, cursors = _P.setup_cursor_text(before_options.text)
    expected = _P.dedent(expected)

    local buffer = _P.make_temporary_buffer(before)
    vim.api.nvim_set_current_buf(buffer)
    local window = vim.api.nvim_get_current_win()
    before_options.options(buffer)

    if strict and #callbacks ~= #cursors then
        error(
            string.format(
                'Found "%s" cursors but only "%s" callbacks. These two numbers must match.',
                #cursors,
                #callbacks
            ),
            0
        )
    end

    for index, callback in ipairs(callbacks) do
        local cursor = cursors[index]

        if cursor then
            vim.api.nvim_win_set_cursor(window, cursor)
        end

        callback()
    end

    local found_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    local found = vim.fn.join(found_lines, _LINE_SEPARATOR)

    assert.equal(expected, found)
end

describe("p text-operator", function()
    describe("piw text-motion", function()
        it("single-line", function()
            _P.assert_keys_with_buffer(
                function()
                    vim.fn.setreg('"', "some text here", "c")
                    vim.cmd("normal piw")
                end,
                [[
                foo |cursor|bar.

                another line
                ]],
                [[
                foo some text here.

                another line
                ]]
            )
        end)

        it("multi-line", function()
            _P.assert_keys_with_buffer(
                function()
                    vim.fn.setreg('"', "some text here\nand more text\n    here and there", "c")
                    vim.cmd("normal piw")
                end,
                [[
                foo b|cursor|ar.

                another line
                ]],
                [[
                foo some text here
                and more text
                    here and there.

                another line
                ]]
            )
        end)
    end)

    describe("bugfixes", function()
        it("works with lines containing newlines", function()
            _P.assert_keys_with_buffer(
                {
                    function()
                        vim.cmd("silent normal d3d")
                    end,
                    function()
                        vim.api.nvim_win_set_cursor(0, { 2, 6 })
                        vim.cmd("silent normal piw")
                    end,
                },
                [[
                foo |cursor|bar.

                more lines.
                another line
                and more lines
                last line
                ]],
                [[
                another line
                foo bar.

                more lines.
                and  lines
                last line
                ]]
            )
        end)
    end)
end)
