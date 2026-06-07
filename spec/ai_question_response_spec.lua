local ai_question_response = require("modules.features.ai_question_response")

local function close_extra_tabs()
    if vim.fn.tabpagenr("$") > 1 then
        vim.cmd.tabonly({ bang = true })
    end
end

describe("AI question response formatter", function()
    local original_system
    local original_notify
    local original_command
    local notifications

    before_each(function()
        original_system = vim.system
        original_notify = vim.notify
        original_command = vim.env[ai_question_response.command_environment_variable]
        notifications = {}
        ai_question_response.original_buffers_by_tab = {}
        ai_question_response.answer_links_by_buf = {}
        vim.notify = function(message, level)
            table.insert(notifications, { message = message, level = level })
        end
        vim.env[ai_question_response.command_environment_variable] = nil
        close_extra_tabs()
        vim.cmd.enew({ bang = true })
    end)

    after_each(function()
        vim.system = original_system
        vim.notify = original_notify
        vim.env[ai_question_response.command_environment_variable] = original_command
        ai_question_response.original_buffers_by_tab = {}
        ai_question_response.answer_links_by_buf = {}
        close_extra_tabs()
        vim.cmd.enew({ bang = true })
    end)

    it("opens a linked scratch answer buffer in a new tab", function()
        local source_tab = vim.fn.tabpagenr()
        local source_buf = vim.api.nvim_get_current_buf()

        vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "1. What changed?" })

        local answer_buf = ai_question_response.start()

        assert.equal(source_buf, ai_question_response.original_buffers_by_tab[source_tab])
        assert.equal(2, vim.fn.tabpagenr("$"))
        assert.equal(answer_buf, vim.api.nvim_get_current_buf())
        assert.equal("nofile", vim.bo[answer_buf].buftype)
        assert.equal("markdown", vim.bo[answer_buf].filetype)
        assert.same({
            source_tab = source_tab,
            source_buf = source_buf,
        }, ai_question_response.answer_links_by_buf[answer_buf])
    end)

    it("submits answers asynchronously and overwrites the original question buffer", function()
        local captured_command
        local captured_stdin

        vim.system = function(command, options, callback)
            if options and options.stdin then
                captured_command = command
                captured_stdin = options.stdin
                callback({ code = 0, stdout = "1. What changed?\n\n   I fixed it.\n", stderr = "" })
            end
            return {}
        end

        local source_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "1. What changed?" })

        local answer_buf = ai_question_response.start()
        vim.api.nvim_buf_set_lines(answer_buf, 0, -1, false, { "fixed it" })

        assert.True(ai_question_response.toggle())
        vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)[2] == ""
        end)

        assert.same({ "claude", "-p" }, captured_command)
        assert.matches("Original questions:", captured_stdin, 1, true)
        assert.matches("1. What changed?", captured_stdin, 1, true)
        assert.matches("My unstructured response:", captured_stdin, 1, true)
        assert.matches("fixed it", captured_stdin, 1, true)
        assert.same({ "1. What changed?", "", "   I fixed it." }, vim.api.nvim_buf_get_lines(source_buf, 0, -1, false))
        assert.equal(1, vim.fn.tabpagenr("$"))
        assert.equal("Formatting succeeded.", notifications[#notifications].message)
    end)

    it("uses the configured formatter command through the shell", function()
        vim.env[ai_question_response.command_environment_variable] = "custom-ai --format"

        assert.same(
            { vim.o.shell, vim.o.shellcmdflag, "custom-ai --format" },
            ai_question_response.get_formatter_command()
        )
    end)

    it("maps Space-A to the formatter toggle", function()
        local mapping = vim.fn.maparg("<Space>A", "n", false, true)

        assert.is_function(mapping.callback)
        assert.equal("Answer AI questions in a scratch buffer, then format them.", mapping.desc)
    end)
end)
