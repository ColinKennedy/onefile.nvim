--- Enter a new scratch buffer containing `lines`.
---
---@param lines string[] The buffer text.
---@return integer # The buffer number.
local function enter_buffer(lines)
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buffer)

    return buffer
end

--- Count the search-highlight `CursorMoved` autocmds registered for `buffer`.
---
---@param buffer integer The buffer number.
---@return integer # The autocmd count.
local function count_autocmds(buffer)
    return #vim.api.nvim_get_autocmds({
        group = "my.highlighter.word_search",
        event = "CursorMoved",
        buffer = buffer,
    })
end

describe("search highlight", function()
    after_each(function()
        vim.cmd.enew({ bang = true })
        vim.cmd.nohlsearch()
    end)

    it("tracks the cursor in text buffers", function()
        assert.equal(1, count_autocmds(enter_buffer({ "abc" })))
    end)

    it("registers only once per buffer", function()
        local buffer = enter_buffer({ "abc" })
        vim.cmd.enew({ bang = true })
        vim.api.nvim_set_current_buf(buffer)

        assert.equal(1, count_autocmds(buffer))
    end)

    it("skips binary buffers and never errors on them", function()
        local buffer = enter_buffer({ "ab\0cd abc" })
        vim.fn.setreg("/", "abc")

        vim.v.errmsg = ""
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buffer })

        assert.equal(0, count_autocmds(buffer))
        assert.equal("", vim.v.errmsg)
    end)
end)
