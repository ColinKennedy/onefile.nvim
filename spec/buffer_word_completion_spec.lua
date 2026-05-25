local buffer_word_completion = require("modules.features.buffer_word_completion")

local _GET_CLIENTS
local _COMPLETE

describe("modules.features.buffer_word_completion", function()
    before_each(function()
        _GET_CLIENTS = vim.lsp.get_clients
        _COMPLETE = vim.fn.complete
        ---@diagnostic disable-next-line: duplicate-set-field
        buffer_word_completion._P.is_insert_mode = function()
            return true
        end
    end)

    after_each(function()
        vim.lsp.get_clients = _GET_CLIENTS
        vim.fn.complete = _COMPLETE
        ---@diagnostic disable-next-line: duplicate-set-field
        buffer_word_completion._P.is_insert_mode = function()
            return vim.api.nvim_get_mode().mode == "i"
        end
        pcall(vim.cmd.stopinsert)
        vim.cmd.enew({ bang = true })
    end)

    it("extracts the word prefix before the cursor", function()
        local start_column, prefix = buffer_word_completion._P.get_prefix("alpha beta_ga", 13)

        assert.equal(7, start_column)
        assert.equal("beta_ga", prefix)
    end)

    it("sorts matching buffer words by closest line to the cursor", function()
        local buffer = vim.api.nvim_create_buf(false, false)
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
            "alpha_alpine",
            "albatross",
            "unrelated",
            "alphabet",
        })

        local matches = buffer_word_completion._P.collect_matches(buffer, "al", 4)

        assert.are.same({ "alphabet", "albatross", "alpha_alpine" }, vim.tbl_map(function(match)
            return match.word
        end, matches))
    end)

    it("completes from buffer words when no LSP completion client is attached", function()
        local buffer = vim.api.nvim_create_buf(false, false)
        vim.api.nvim_set_current_buf(buffer)
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
            "nearby_result",
            "ne",
        })
        vim.api.nvim_win_set_cursor(0, { 2, 2 })

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.lsp.get_clients = function()
            return {}
        end

        ---@type {start_column: integer, words: string[]}?
        local complete_call = nil
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.complete = function(start_column, matches)
            complete_call = {
                start_column = start_column,
                words = vim.tbl_map(function(match)
                    return match.word
                end, matches),
            }
        end

        vim.cmd.startinsert({ bang = true })
        buffer_word_completion._P.complete_current_buffer_words()

        assert.are.same({ start_column = 1, words = { "nearby_result" } }, complete_call)
    end)

    it("does not complete from buffer words when LSP completion is attached", function()
        local buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(buffer)
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "nearby_result", "ne" })
        vim.api.nvim_win_set_cursor(0, { 2, 2 })

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.lsp.get_clients = function()
            return {
                {
                    supports_method = function(_, method)
                        return method == "textDocument/completion"
                    end,
                },
            }
        end

        local was_called = false
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.complete = function()
            was_called = true
        end

        vim.cmd.startinsert({ bang = true })
        buffer_word_completion._P.complete_current_buffer_words()

        assert.is_false(was_called)
    end)
end)
