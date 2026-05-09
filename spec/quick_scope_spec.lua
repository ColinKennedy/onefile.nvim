local quick_scope = require("modules.plugins.quick_scope")

--- Save a global variable and return its current value.
---
---@param name string The global variable name without `g:`.
---@return any # The previous value.
local function save_global(name)
    return vim.g[name]
end

--- Restore a global variable to a previous value.
---
---@param name string The global variable name without `g:`.
---@param value any The value to restore.
local function restore_global(name, value)
    vim.g[name] = value
end

--- Get sorted highlight columns from a result list.
---
---@param highlights _my.quick_scope.Highlight[] Highlight positions.
---@return integer[] # Sorted 1-or-more columns.
local function get_columns(highlights)
    ---@type integer[]
    local columns = {}

    for _, highlight in ipairs(highlights) do
        table.insert(columns, highlight.column)
    end

    table.sort(columns)

    return columns
end

--- Get the columns from a match result.
---
---@param match table The match returned by `getmatches()`.
---@return integer[] # Sorted 1-or-more columns.
local function get_match_columns(match)
    ---@type integer[]
    local columns = {}

    for name, position in pairs(match) do
        if type(name) == "string" and name:match("^pos%d+$") and type(position) == "table" then
            table.insert(columns, position[2])
        end
    end

    table.sort(columns)

    return columns
end

describe("quick scope", function()
    ---@type table<string, any>
    local saved_options = {}

    before_each(function()
        for _, option in ipairs({
            "qs_enable",
            "qs_max_chars",
            "qs_accepted_chars",
            "qs_second_highlight",
            "qs_ignorecase",
            "qs_buftype_blacklist",
            "qs_filetype_blacklist",
        }) do
            saved_options[option] = save_global(option)
        end

        vim.g.qs_enable = 1
        vim.g.qs_max_chars = 1000
        vim.g.qs_accepted_chars = {
            "a",
            "b",
            "c",
            "d",
            "e",
            "f",
            "g",
            "h",
            "i",
            "j",
            "k",
            "l",
            "m",
            "n",
            "o",
            "p",
            "q",
            "r",
            "s",
            "t",
            "u",
            "v",
            "w",
            "x",
            "y",
            "z",
            "0",
            "1",
            "2",
            "3",
            "4",
            "5",
            "6",
            "7",
            "8",
            "9",
        }
        vim.g.qs_second_highlight = 1
        vim.g.qs_ignorecase = 0
        ---@type string[]
        vim.g.qs_buftype_blacklist = {}
        ---@type string[]
        vim.g.qs_filetype_blacklist = {}
    end)

    after_each(function()
        for option, value in pairs(saved_options) do
            restore_global(option, value)
        end

        quick_scope.unhighlight_line()
    end)

    it("chooses one cheap target per word from the cursor outward", function()
        local line = 'items = [item.split("_")[0] for item in os.listdir(directory)]'

        local highlights = quick_scope.get_line_highlights(line, 1, 11)

        assert.are.same({ 2, 15, 26, 29, 39, 48, 56 }, get_columns(highlights.primary))
        assert.are.same({ 33, 41 }, get_columns(highlights.secondary))
    end)

    it("excludes the current word from highlights", function()
        local highlights = quick_scope.get_line_highlights('items = [item.split("_")[0]', 1, 11)

        assert.is_false(vim.tbl_contains(get_columns(highlights.primary), 10))
        assert.is_false(vim.tbl_contains(get_columns(highlights.primary), 11))
        assert.is_false(vim.tbl_contains(get_columns(highlights.primary), 12))
        assert.is_false(vim.tbl_contains(get_columns(highlights.primary), 13))
        assert.is_false(vim.tbl_contains(get_columns(highlights.secondary), 10))
        assert.is_false(vim.tbl_contains(get_columns(highlights.secondary), 11))
        assert.is_false(vim.tbl_contains(get_columns(highlights.secondary), 12))
        assert.is_false(vim.tbl_contains(get_columns(highlights.secondary), 13))
    end)

    it("does not highlight syntax punctuation", function()
        local highlights = quick_scope.get_line_highlights('items = [item.split("_")[0]', 1, 11)
        local primary_columns = get_columns(highlights.primary)

        assert.is_false(vim.tbl_contains(primary_columns, 14))
        assert.is_false(vim.tbl_contains(primary_columns, 20))
        assert.is_false(vim.tbl_contains(primary_columns, 25))
        assert.is_false(vim.tbl_contains(primary_columns, 27))
    end)

    it("can disable second occurrence highlights", function()
        vim.g.qs_second_highlight = 0

        local line = 'items = [item.split("_")[0] for item in os.listdir(directory)]'
        local highlights = quick_scope.get_line_highlights(line, 1, 11)

        assert.are.same({}, highlights.secondary)
    end)

    it("does not compute highlights on overlong lines", function()
        vim.g.qs_max_chars = 3

        local highlights = quick_scope.get_line_highlights("abc1", 1, 1)

        assert.are.same({}, highlights.primary)
        assert.are.same({}, highlights.secondary)
    end)

    it("can highlight the current line with match positions", function()
        local line = 'items = [item.split("_")[0] for item in os.listdir(directory)]'
        local buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(buffer)
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { line })
        vim.api.nvim_win_set_cursor(0, { 1, 10 })

        quick_scope.highlight_line()

        local matches = vim.fn.getmatches()

        assert.equal("QuickScopePrimary", matches[1].group)
        assert.equal("QuickScopeSecondary", matches[2].group)
        assert.are.same({ 2, 15, 26, 29, 39, 48, 56 }, get_match_columns(matches[1]))
        assert.are.same({ 33, 41 }, get_match_columns(matches[2]))
    end)

    it("does not highlight terminal buffers by default", function()
        vim.g.qs_buftype_blacklist = nil

        local buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(buffer)
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "foo bar baz" })
        vim.api.nvim_open_term(buffer, {})
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        quick_scope.highlight_line()

        local matches = vim.fn.getmatches()

        assert.are.same(
            {},
            vim.tbl_filter(function(match)
                return match.group == "QuickScopePrimary" or match.group == "QuickScopeSecondary"
            end, matches)
        )
    end)
end)
