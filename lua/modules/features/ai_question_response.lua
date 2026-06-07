--- Turn an AI question list plus rough answers into a formatted response.

local M = {}

---@class _my.ai_question_response.Link
---@field source_tab integer
---@field source_buf integer

---@type table<integer, integer>
M.original_buffers_by_tab = {}

---@type table<integer, _my.ai_question_response.Link>
M.answer_links_by_buf = {}

M.command_environment_variable = "NEOVIM_AI_QUESTION_RESPONSE_COMMAND"

M.answer_sheet_hint = "<!-- This is the answer sheet, write your responses here-->"

local INSTRUCTION = table.concat({
    "Here is a structured list of questions from an AI and an unstructured,",
    "stream-of-consciousness response from me. There could be many questions",
    "below and I may not answer everything but expect that I will roughly answer",
    "questions in the order that they were received from the AI. Please insert my",
    "responses back into the original list of questions. Apply markdown",
    "formatting and cleanup text as you do so. ONLY respond with JUST THIS - the",
    "original structured list of questions + responses.",
}, "\n")

---Get all lines from a buffer as one string.
---
---@param buffer integer
---@return string
function M.get_buffer_text(buffer)
    return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
end

---Get answer lines without the answer-sheet hint.
---
---@param buffer integer
---@return string
function M.get_answer_text(buffer)
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)

    if lines[1] == M.answer_sheet_hint then
        table.remove(lines, 1)
    end

    if lines[1] == "" then
        table.remove(lines, 1)
    end

    return table.concat(lines, "\n")
end

---Create the prompt sent to the formatter process.
---
---@param questions string
---@param answers string
---@return string
function M.build_prompt(questions, answers)
    return table.concat({
        INSTRUCTION,
        "",
        "Original questions:",
        "",
        questions,
        "",
        "My unstructured response:",
        "",
        answers,
    }, "\n")
end

---Return the argv used to run the AI formatter.
---
---@return string[]
function M.get_formatter_command()
    local command = vim.env[M.command_environment_variable]

    if command and command ~= "" then
        return { vim.o.shell, vim.o.shellcmdflag, command }
    end

    return { "claude", "-p" }
end

---Check whether the fallback formatter is available.
---
---@return boolean # If the fallback formatter is available, return `true`.
function M.is_fallback_formatter_available()
    return vim.fn.executable("claude") == 1
end

---Return whether the configured formatter can be started.
---
---@return boolean
function M.can_start_formatter()
    local command = vim.env[M.command_environment_variable]

    return command ~= nil and command ~= "" or M.is_fallback_formatter_available()
end

---Start an answer scratch buffer for the current buffer.
---
---@return integer # The answer buffer number.
function M.start()
    local source_tab = vim.fn.tabpagenr()
    local source_buf = vim.api.nvim_get_current_buf()

    M.original_buffers_by_tab[source_tab] = source_buf

    local answer_buf = vim.api.nvim_create_buf(false, true)
    M.answer_links_by_buf[answer_buf] = {
        source_tab = source_tab,
        source_buf = source_buf,
    }

    vim.bo[answer_buf].buftype = "nofile"
    vim.bo[answer_buf].bufhidden = "wipe"
    vim.bo[answer_buf].swapfile = false
    vim.bo[answer_buf].filetype = "markdown"
    vim.api.nvim_buf_set_name(answer_buf, "AI Question Responses")
    vim.api.nvim_buf_set_lines(answer_buf, 0, -1, false, { M.answer_sheet_hint, "" })

    vim.cmd.tabnew()
    vim.api.nvim_set_current_buf(source_buf)
    vim.cmd.vsplit()
    vim.api.nvim_set_current_buf(answer_buf)

    return answer_buf
end

---Overwrite a buffer with formatted response text.
---
---@param buffer integer
---@param text string
function M.replace_buffer_text(buffer, text)
    local lines = vim.split(text:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n", { plain = true })

    if #lines > 1 and lines[#lines] == "" then
        table.remove(lines)
    end

    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
end

---Submit the current answer buffer to the formatter process.
---
---@param answer_buf? integer
---@return boolean # If submission started, return `true`.
function M.submit(answer_buf)
    answer_buf = answer_buf or vim.api.nvim_get_current_buf()

    local link = M.answer_links_by_buf[answer_buf]
    if not link then
        return false
    end

    if not vim.api.nvim_buf_is_valid(link.source_buf) then
        vim.notify("Cannot format answers because the original buffer is gone.", vim.log.levels.ERROR)
        return false
    end

    if not M.can_start_formatter() then
        vim.notify("Cannot format answers because `claude -p` is not available.", vim.log.levels.ERROR)
        return false
    end

    local answers = M.get_answer_text(answer_buf)
    local questions = M.get_buffer_text(link.source_buf)
    local prompt = M.build_prompt(questions, answers)
    local command = M.get_formatter_command()

    M.answer_links_by_buf[answer_buf] = nil

    if vim.api.nvim_get_current_buf() == answer_buf then
        pcall(vim.cmd, "tabclose!")
    end

    vim.notify("Formatting with AI, please wait.", vim.log.levels.INFO)

    vim.system(command, { text = true, stdin = prompt }, function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                local message = vim.trim(result.stderr or result.stdout or "")
                if message == "" then
                    message = "Formatter process exited with code " .. tostring(result.code) .. "."
                end
                vim.notify("Formatting failed: " .. message, vim.log.levels.ERROR)
                return
            end

            if not vim.api.nvim_buf_is_valid(link.source_buf) then
                vim.notify("Formatting succeeded, but the original buffer is gone.", vim.log.levels.WARN)
                return
            end

            M.replace_buffer_text(link.source_buf, result.stdout or "")
            vim.notify("Formatting succeeded.", vim.log.levels.INFO)
        end)
    end)

    return true
end

---Start an answer buffer, or submit the current answer buffer.
---
---@return boolean # If the mapping handled the current buffer, return `true`.
function M.toggle()
    local current_buf = vim.api.nvim_get_current_buf()

    if M.answer_links_by_buf[current_buf] then
        return M.submit(current_buf)
    end

    M.start()
    return true
end

vim.keymap.set("n", "<leader>aa", M.toggle, {
    desc = "[a]sk [a]i questions in a scratch buffer, then add the responses to the current buffer.",
})

return M
