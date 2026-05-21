--- Minimal Lua equivalent of vim-dispatch.

local M = {}
local _P = {}

---@class modules.plugins.native_dispatch.Options
---@field command string
---@field compiler string?
---@field errorformat string?
---@field mode "job" | "run" | "show-last-log"
---@field show_on_error boolean

---@type string[]
local _LAST_LOG_LINES = {}
local _LAST_LOG_TITLE = "Dispatch log"
local _DEFAULT_ERRORFORMAT = "%f:%l:%c: %m,%f:%l: %m,%m"

---@type table<string, fun()>
_P.extra_compilers = {
    vimgrep = function()
        vim.opt.errorformat = { "%f:%l:%c:%m", "%f:%l:%m" }
    end,
}

---@class modules.plugins.native_dispatch.Word
---@field text string
---@field finish integer

---@param text string
---@param start integer
---@return modules.plugins.native_dispatch.Word?
function _P.read_shell_word(text, start)
    local index = start
    local length = #text

    while index <= length and text:sub(index, index):match("%s") do
        index = index + 1
    end

    if index > length then
        return nil
    end

    local quote
    local word = {}

    while index <= length do
        local character = text:sub(index, index)

        if quote then
            if character == quote then
                quote = nil
            elseif character == "\\" and quote == '"' and index < length then
                index = index + 1
                table.insert(word, text:sub(index, index))
            else
                table.insert(word, character)
            end
        elseif character == "'" or character == '"' then
            quote = character
        elseif character:match("%s") then
            break
        elseif character == "\\" and index < length then
            index = index + 1
            table.insert(word, text:sub(index, index))
        else
            table.insert(word, character)
        end

        index = index + 1
    end

    return { text = table.concat(word), finish = index }
end

---@param args string
---@return modules.plugins.native_dispatch.Options
function _P.parse_args(args)
    ---@type modules.plugins.native_dispatch.Options
    local options = {
        command = "",
        compiler = nil,
        errorformat = nil,
        mode = "job",
        show_on_error = false,
    }

    local index = 1

    while true do
        local word = _P.read_shell_word(args, index)

        if not word then
            return options
        end

        if word.text == "run" then
            options.mode = "run"
            index = word.finish + 1
            break
        elseif word.text == "show-last-log" then
            options.mode = "show-last-log"
            index = word.finish + 1
            break
        elseif word.text == "--show-on-error" then
            options.show_on_error = true
            index = word.finish + 1
        else
            local compiler = word.text:match("^%-%-compiler=(.+)$")

            if compiler then
                options.compiler = compiler
                index = word.finish + 1
            else
                break
            end
        end
    end

    options.command = vim.trim(args:sub(index))

    return options
end

---@param command string
---@return string[]
function _P.to_shell_command(command)
    return { vim.o.shell, vim.o.shellcmdflag, command }
end

---@param lines string[]
---@return string[]
function _P.normalize_lines(lines)
    ---@type string[]
    local output = {}

    for _, line in ipairs(lines) do
        if line ~= "" then
            for part in (line .. "\n"):gmatch("(.-)\n") do
                table.insert(output, part)
            end
        end
    end

    return output
end

---@param title string
---@param lines string[]
function _P.remember_log(title, lines)
    _LAST_LOG_TITLE = title
    _LAST_LOG_LINES = vim.deepcopy(lines)
end

---@param title string
---@param lines string[]
---@return integer
function _P.create_log_buffer(title, lines)
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.bo[buffer].bufhidden = "wipe"
    vim.bo[buffer].buftype = "nofile"
    vim.bo[buffer].swapfile = false
    vim.api.nvim_buf_set_name(buffer, title)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.tbl_isempty(lines) and { "" } or lines)
    vim.bo[buffer].modifiable = false

    return buffer
end

---@param title string
---@param lines string[]
function _P.show_log(title, lines)
    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, _P.create_log_buffer(title, lines))
end

function M.show_last_log()
    _P.show_log(_LAST_LOG_TITLE, _LAST_LOG_LINES)
end

---@param command string
---@return string[]
function _P.get_parse_lines(command)
    if vim.tbl_isempty(_LAST_LOG_LINES) then
        return { string.format("Dispatch command produced no output: %s", command) }
    end

    return _LAST_LOG_LINES
end

---@return string
function _P.get_effective_errorformat()
    if vim.bo.errorformat ~= "" then
        return vim.bo.errorformat
    end

    return vim.o.errorformat
end
---@param command string
---@param lines string[]
---@param errorformat string?
function _P.load_quickfix(command, lines, errorformat)
    local efm = errorformat or _P.get_effective_errorformat()

    if efm == "" then
        efm = _DEFAULT_ERRORFORMAT
    end

    local ok, parsed = pcall(vim.fn.getqflist, {
        efm = efm,
        lines = lines,
        title = ":Dispatch " .. command,
    })

    if not ok then
        vim.notify(string.format("Could not parse :Dispatch output: %s", parsed), vim.log.levels.ERROR)
        parsed = { items = {} }
    end

    vim.fn.setqflist({}, "r", {
        items = parsed.items or {},
        title = ":Dispatch " .. command,
    })

    if parsed.items and not vim.tbl_isempty(parsed.items) then
        pcall(vim.cmd.cwindow)
    end
end

---@param compiler string
---@param callback fun(errorformat: string)
function _P.with_compiler(compiler, callback)
    local had_buffer_compiler = vim.b.current_compiler ~= nil
    local original_buffer_compiler = vim.b.current_compiler
    local had_global_compiler = vim.g.current_compiler ~= nil
    local original_global_compiler = vim.g.current_compiler
    local original_makeprg = vim.bo.makeprg
    local original_errorformat = vim.bo.errorformat
    local original_global_errorformat = vim.o.errorformat
    local ad_hoc_compiler = _P.extra_compilers[compiler]

    if ad_hoc_compiler then
        local ok, message = pcall(ad_hoc_compiler)

        if not ok then
            vim.notify(
                string.format('Could not load ad-hoc compiler "%s": %s', compiler, message),
                vim.log.levels.ERROR
            )

            return
        end
    else
        local ok, message = pcall(vim.cmd.compiler, compiler)

        if not ok then
            vim.notify(string.format('Could not load compiler "%s": %s', compiler, message), vim.log.levels.ERROR)

            return
        end
    end

    callback(_P.get_effective_errorformat())

    vim.bo.makeprg = original_makeprg
    vim.o.errorformat = original_global_errorformat
    vim.bo.errorformat = original_errorformat

    if had_buffer_compiler then
        vim.b.current_compiler = original_buffer_compiler
    else
        vim.b.current_compiler = nil
    end

    if had_global_compiler then
        vim.g.current_compiler = original_global_compiler
    else
        vim.g.current_compiler = nil
    end
end

---@param command string
---@param options modules.plugins.native_dispatch.Options
function _P.run_silent(command, options)
    local stdout = {}
    local stderr = {}

    vim.fn.jobstart(_P.to_shell_command(command), {
        stderr_buffered = true,
        stdout_buffered = true,
        on_stdout = function(_, data)
            vim.list_extend(stdout, _P.normalize_lines(data or {}))
        end,
        on_stderr = function(_, data)
            vim.list_extend(stderr, _P.normalize_lines(data or {}))
        end,
        on_exit = function(_, code)
            vim.schedule(function()
                local lines = {}

                vim.list_extend(lines, stdout)
                vim.list_extend(lines, stderr)
                _P.remember_log(":Dispatch " .. command, lines)
                _P.load_quickfix(command, _P.get_parse_lines(command), options.errorformat)

                if code ~= 0 then
                    vim.notify(string.format(':Dispatch exited with code %d: %s', code, command), vim.log.levels.ERROR)
                end
            end)
        end,
    })
end

---@param command string
---@param options modules.plugins.native_dispatch.Options
function _P.run_terminal(command, options)
    vim.cmd("botright split")
    local window = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_get_current_buf()

    vim.fn.jobstart(command, {
        term = true,
        on_exit = function(_, code)
            vim.defer_fn(function()
                local lines = vim.api.nvim_buf_is_valid(buffer)
                    and vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
                    or {}

                _P.remember_log(":Dispatch " .. command, lines)

                if vim.api.nvim_win_is_valid(window) then
                    vim.api.nvim_win_close(window, true)
                end

                if vim.api.nvim_buf_is_valid(buffer) then
                    vim.api.nvim_buf_delete(buffer, { force = true })
                end

                _P.load_quickfix(command, _P.get_parse_lines(command), options.errorformat)

                if code ~= 0 then
                    vim.notify(string.format(':Dispatch exited with code %d: %s', code, command), vim.log.levels.ERROR)
                end
            end, 80)
        end,
    })

    vim.cmd.startinsert()
end
---@param options modules.plugins.native_dispatch.Options
function _P.dispatch_with_options(options)
    if options.mode == "show-last-log" then
        M.show_last_log()

        return
    end

    if options.command == "" then
        local fallback = vim.b.dispatch

        if type(fallback) == "string" then
            options.command = fallback
        else
            vim.notify(":Dispatch requires a command.", vim.log.levels.ERROR)

            return
        end
    end

    local run = function()
        if options.show_on_error then
            _P.run_silent(options.command, options)
        else
            _P.run_terminal(options.command, options)
        end
    end

    if options.compiler then
        _P.with_compiler(options.compiler, function(errorformat)
            options.errorformat = errorformat
            run()
        end)
    else
        run()
    end
end

---@param opts vim.api.keyset.create_user_command.command_args
function M.dispatch(opts)
    _P.dispatch_with_options(_P.parse_args(opts.args))
end

return M
