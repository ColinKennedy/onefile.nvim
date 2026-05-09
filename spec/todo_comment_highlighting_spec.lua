local tagged_comments = require("modules.plugins.todo_comment_highlighting")

--- Create a scratch buffer for tagged comment tests.
---
---@param lines string[] Buffer lines.
---@return integer # The created buffer.
local function make_buffer(lines)
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].commentstring = "# %s"

    return buffer
end

--- Get extmarks from a buffer.
---
---@param buffer integer The buffer to inspect.
---@return table[] # Extmark data.
local function get_extmarks(buffer)
    return vim.api.nvim_buf_get_extmarks(buffer, tagged_comments.get_namespace(), 0, -1, {
        details = true,
    })
end

--- Check whether a highlight exists on `line`.
---
---@param extmarks table[] Extmarks to inspect.
---@param line integer The 0-or-more line number.
---@param group string The expected highlight group.
---@return boolean # Whether the highlight exists.
local function has_highlight(extmarks, line, group)
    for _, extmark in ipairs(extmarks) do
        if extmark[2] == line and extmark[4].hl_group == group then
            return true
        end
    end

    return false
end

--- Find a highlight extmark.
---
---@param extmarks table[] Extmarks to inspect.
---@param line integer The 0-or-more line number.
---@param group string The expected highlight group.
---@return table? # The extmark, if found.
local function find_highlight(extmarks, line, group)
    for _, extmark in ipairs(extmarks) do
        if
            extmark[2] == line
            and extmark[4].hl_group == group
            and (extmark[4].end_col or 0) > extmark[3]
            and extmark[4].spell == false
        then
            return extmark
        end
    end

    return nil
end

describe("tagged comment highlighting", function()
    after_each(function()
        vim.cmd.enew({ bang = true })
    end)

    it("parses Python comments", function()
        local comment = tagged_comments.parse_comment_line("# TODO: Some text", "# %s")

        assert.are.same({
            text = "TODO: Some text",
            comment_start_column = 2,
        }, comment)
    end)

    it("finds known tags", function()
        local tag = tagged_comments.find_tag({
            text = "FIXME: Something important",
            comment_start_column = 2,
        })

        assert.is_not_nil(tag)
        tag = tag --[[@as _my.comment.TagMatch]]

        assert.equal("FIXME", tag.tag)
        assert.equal(2, tag.tag_start_column)
        assert.equal(7, tag.tag_end_column)
        assert.equal(8, tag.block_end_column)
    end)

    it("highlights multiline comment blocks until empty comments", function()
        local buffer = make_buffer({
            "# TODO: Some text here",
            "# with more lines",
            "#",
            "# blah",
        })

        tagged_comments.highlight_buffer(buffer)

        local extmarks = get_extmarks(buffer)

        assert.is_true(has_highlight(extmarks, 0, "MyTodoTodoTag"))
        assert.is_true(has_highlight(extmarks, 0, "MyTodoTodoTagPadding"))
        assert.is_true(has_highlight(extmarks, 0, "MyTodoTodoText"))
        assert.is_true(has_highlight(extmarks, 1, "MyTodoTodoText"))
        assert.is_false(has_highlight(extmarks, 2, "MyTodoTodoText"))
        assert.is_false(has_highlight(extmarks, 3, "MyTodoTodoText"))
    end)

    it("highlights the whitespace between the comment prefix and tag", function()
        local buffer = make_buffer({ "# TODO: Some text here" })

        tagged_comments.highlight_buffer(buffer)

        local extmark = find_highlight(get_extmarks(buffer), 0, "MyTodoTodoTagPadding")

        assert.is_not_nil(extmark)
        extmark = extmark --[[@as table]]
        assert.equal(1, extmark[3])
        assert.equal(2, extmark[4].end_col)
    end)

    it("highlights screenshot tags with their canonical groups", function()
        local buffer = make_buffer({
            "# FIXME: SOMETHING IMPORTANT",
            "# HACK: Another one",
            "# NOTE: More text here",
            "# WARNING: More and more text",
            "# XXX: Careful",
            "# PERF: Some more text",
            "# IMPORTANT: Some line",
            "# ISSUE: Some line",
            "# FIXIT: Some line",
            "# BUG: Some line",
        })

        tagged_comments.highlight_buffer(buffer)

        local extmarks = get_extmarks(buffer)

        assert.is_true(has_highlight(extmarks, 0, "MyTodoFixTag"))
        assert.is_true(has_highlight(extmarks, 1, "MyTodoHackTag"))
        assert.is_true(has_highlight(extmarks, 2, "MyTodoNoteTag"))
        assert.is_true(has_highlight(extmarks, 3, "MyTodoWarningTag"))
        assert.is_true(has_highlight(extmarks, 4, "MyTodoWarningTag"))
        assert.is_true(has_highlight(extmarks, 5, "MyTodoPerfTag"))
        assert.is_true(has_highlight(extmarks, 6, "MyTodoFixTag"))
        assert.is_true(has_highlight(extmarks, 7, "MyTodoFixTag"))
        assert.is_true(has_highlight(extmarks, 8, "MyTodoFixTag"))
        assert.is_true(has_highlight(extmarks, 9, "MyTodoFixTag"))
    end)
end)
