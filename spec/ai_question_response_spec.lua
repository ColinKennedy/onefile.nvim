local ai_question_response = require("modules.features.ai_question_response")

local function close_extra_tabs()
    if vim.fn.tabpagenr("$") > 1 then
        vim.cmd.tabonly({ bang = true })
    end
end

describe("AI question response formatter", function()
    ---@type fun(cmd: string[], opts: vim.SystemOpts?, on_exit: (fun(out: vim.SystemCompleted): nil)?): vim.SystemObj
    local original_system
    ---@type fun(message: string, level: integer?): nil
    local original_notify
    ---@type string?
    local original_command
    ---@type fun(expression: string): integer
    local original_executable
    ---@type {message: string, level: integer?}[]
    local notifications

    before_each(function()
        original_system = vim.system
        original_notify = vim.notify
        original_command = vim.env[ai_question_response._command_environment_variable]
        original_executable = vim.fn.executable
        notifications = {}
        ai_question_response._original_buffers_by_tab = {}
        ai_question_response._answer_links_by_buf = {}
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.notify = function(message, level)
            table.insert(notifications, { message = message, level = level })
        end
        vim.env[ai_question_response._command_environment_variable] = nil
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.executable = function(command)
            return command == "claude" and 1 or original_executable(command)
        end
        close_extra_tabs()
        vim.cmd.enew({ bang = true })
    end)

    after_each(function()
        vim.system = original_system
        vim.notify = original_notify
        vim.fn.executable = original_executable
        vim.env[ai_question_response._command_environment_variable] = original_command
        ai_question_response._original_buffers_by_tab = {}
        ai_question_response._answer_links_by_buf = {}
        close_extra_tabs()
        vim.cmd.enew({ bang = true })
    end)

    it("opens linked question and answer buffers as vertical splits in a new tab", function()
        local source_tab = vim.fn.tabpagenr()
        local source_buf = vim.api.nvim_get_current_buf()

        vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "1. What changed?" })

        local answer_buf = ai_question_response._start()

        assert.equal(source_buf, ai_question_response._original_buffers_by_tab[source_tab])
        assert.equal(2, vim.fn.tabpagenr("$"))
        assert.equal(answer_buf, vim.api.nvim_get_current_buf())
        ---@type table<integer, boolean>
        local window_buffers = {}
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            window_buffers[vim.api.nvim_win_get_buf(window)] = true
        end

        assert.equal(2, vim.tbl_count(window_buffers))
        assert.True(window_buffers[source_buf])
        assert.True(window_buffers[answer_buf])
        assert.equal("nofile", vim.bo[answer_buf].buftype)
        assert.equal("markdown", vim.bo[answer_buf].filetype)
        assert.same(
            { ai_question_response._answer_sheet_hint, "" },
            vim.api.nvim_buf_get_lines(answer_buf, 0, -1, false)
        )
        assert.same({
            source_tab = source_tab,
            source_buf = source_buf,
        }, ai_question_response._answer_links_by_buf[answer_buf])
    end)

    it("submits answers asynchronously and overwrites the original question buffer", function()
        ---@type string[]
        local captured_command
        ---@type string
        local captured_stdin

        ---@diagnostic disable-next-line: duplicate-set-field
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

        local answer_buf = ai_question_response._start()
        vim.api.nvim_buf_set_lines(
            answer_buf,
            0,
            -1,
            false,
            { ai_question_response._answer_sheet_hint, "", "fixed it" }
        )

        assert.True(ai_question_response._toggle())
        vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)[2] == ""
        end)

        assert.same({ "claude", "-p" }, captured_command)
        assert.matches("Original questions:", captured_stdin, 1, true)
        assert.matches("1. What changed?", captured_stdin, 1, true)
        assert.matches("My unstructured response:", captured_stdin, 1, true)
        assert.matches("fixed it", captured_stdin, 1, true)
        ---@diagnostic disable-next-line: undefined-field
        assert.not_matches(ai_question_response._answer_sheet_hint, captured_stdin, 1, true)
        assert.same({ "1. What changed?", "", "   I fixed it." }, vim.api.nvim_buf_get_lines(source_buf, 0, -1, false))
        assert.equal(1, vim.fn.tabpagenr("$"))
        assert.equal("Formatting succeeded.", notifications[#notifications].message)
    end)

    it("aborts early when the fallback formatter is not available", function()
        local called = false
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.executable = function()
            return 0
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.system = function()
            called = true
            return {}
        end

        local answer_buf = ai_question_response._start()

        assert.False(ai_question_response._submit(answer_buf))
        assert.False(called)
        assert.equal(
            "Cannot format answers because `claude -p` is not available.",
            notifications[#notifications].message
        )
        assert.equal(2, vim.fn.tabpagenr("$"))
    end)

    it("uses the configured formatter command through the shell", function()
        vim.env[ai_question_response._command_environment_variable] = "custom-ai --format"

        assert.same(
            { vim.o.shell, vim.o.shellcmdflag, "custom-ai --format" },
            ai_question_response._get_formatter_command()
        )
    end)

    it("maps leader-aa to the formatter toggle", function()
        local mapping = vim.fn.maparg("<leader>aa", "n", false, true)

        assert.is_function(mapping.callback)
        assert.equal(
            "[a]sk [a]i questions in a scratch buffer, then add the responses to the current buffer.",
            mapping.desc
        )
    end)
end)
