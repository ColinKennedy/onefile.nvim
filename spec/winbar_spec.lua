local winbar = require("modules.plugins.winbar")

--- Create a scratch buffer with `lines`.
---
---@param lines string[] The lines to place into the buffer.
---@return integer # The created buffer.
local function make_buffer(lines)
    local buffer = vim.api.nvim_create_buf(true, false)
    local window = vim.api.nvim_get_current_win()
    local winfixbuf = vim.wo[window].winfixbuf

    if winfixbuf then
        vim.wo[window].winfixbuf = false
    end

    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buffer)

    if winfixbuf then
        vim.wo[window].winfixbuf = true
    end

    return buffer
end

describe("modules.plugins.winbar", function()
    after_each(function()
        vim.wo.winfixbuf = false
        vim.cmd.enew({ bang = true })
    end)

    it("gets parent indentation context from shallowest to deepest", function()
        local buffer = make_buffer({
            "foo bar fizz",
            "    more text here",
            "        blah",
        })

        assert.are.same({
            "foo bar fizz",
            "more text here",
        }, winbar.get_indentation_scope_names(buffer, 3))
    end)

    it("uses indentation context for buffers with no filetype", function()
        make_buffer({
            "ttttttttt",
            "   sss",
            "       aaaa",
        })

        vim.api.nvim_win_set_cursor(0, { 3, 0 })

        local path_text = "%#MyWinBarPath#tmp > %#MyWinBarFileName#unnkown.ggg"
        local symbols = winbar.strip_statusline_syntax(winbar.get_symbols_text(0, path_text, ""))

        assert.equal(" > ttttttttt > sss", symbols)
    end)

    it("uses tabstop display columns for indentation context", function()
        local buffer = make_buffer({
            "\t         t tttttt",
            "\t\t     asdfasdf",
        })

        vim.bo[buffer].tabstop = 8

        assert.are.same({ "t tttttt" }, winbar.get_indentation_scope_names(buffer, 2))
    end)

    it("simplifies noisy context sections", function()
        assert.equal(
            "func some_useful_name",
            winbar.simplify_context_text("func some_useful_name(lots, of, arguments, here, super long):")
        )
        assert.equal("if thing", winbar.simplify_context_text("if thing { with [many] noisy(parts) }:"))
    end)

    it("keeps unmatched bracket text while removing matched bracket contents", function()
        assert.equal("call unfinished(", winbar.simplify_context_text("call unfinished("))
        assert.equal("call unmatched)", winbar.simplify_context_text("call unmatched)"))
        assert.equal("call", winbar.simplify_context_text("call [matched]"))
    end)

    it("elides context names based on available width", function()
        assert.equal(
            "... fizz > ... here > blah",
            winbar.format_context_names({
                "foo bar fizz",
                "more text here",
                "blah",
            }, 26)
        )
    end)

    it("drops ancestors first when the context line is too long", function()
        assert.equal(
            "... > ... here > ... someth",
            winbar.format_context_names({
                "fooo bar",
                "fizz buzz",
                "more text here",
                "something something someth",
            }, 27)
        )
    end)
end)
