--- A small vim-dispatch-like command runner.

local M = {}
local _P = {}

---@alias _my.dispatch.DisplayMode "always" | "on_error" | "never"

local _MAXIMUM_TMUX_DISPLAY_HEIGHT = 15

---@class _my.dispatch.Options
---@field command string[] The argv-style command to run.
---@field raw_command string The command text shown to the user.
---@field compiler string? The compiler to use while parsing output.
---@field display _my.dispatch.DisplayMode Whether to show command output while it runs.
---@field jump_first boolean? Whether to jump to the first parsed quickfix item.

---@class _my.dispatch.Display
---@field write fun(lines: string[]): nil
---@field close fun(): nil

---@type table<string, fun(): nil>
_P.extra_compilers = {
    vimgrep = function()
        vim.opt.errorformat = { "%f:%l:%c:%m", "%f:%l:%m" }
    end,
}

--- Parse a command string into argv without asking a shell to evaluate it.
---
---@param text string The raw command text.
---@return string[] # Parsed command arguments.
function _P.parse_argv(text)
    ---@type string[]
    local arguments = {}
    ---@type string[]
    local current = {}
    ---@type string?
    local quote = nil
    local escaping = false

    for index = 1, #text do
        local character = text:sub(index, index)

        if escaping then
            table.insert(current, character)
            escaping = false
        elseif character == "\\" then
            escaping = true
        elseif quote ~= nil then
            if character == quote then
                quote = nil
            else
                table.insert(current, character)
            end
        elseif character == '"' or character == "'" then
            quote = character
        elseif character:match("%s") then
            if #current > 0 then
                table.insert(arguments, table.concat(current))
                current = {}
            end
        else
            table.insert(current, character)
        end
    end

    if escaping then
        table.insert(current, "\\")
    end

    if #current > 0 then
        table.insert(arguments, table.concat(current))
    end

    return arguments
end

--- Parse :Dispatch flags and command text.
---
---@param arguments string The user-command argument string.
---@return _my.dispatch.Options? options Parsed options.
---@return string? error_message A human-readable parse error.
function _P.parse_arguments(arguments)
    local argv = _P.parse_argv(arguments)
    ---@type string?
    local compiler = nil
    ---@type _my.dispatch.DisplayMode
    local display = "always"
    local command_start = 1
    local jump_first = false

    for index, argument in ipairs(argv) do
        if argument:sub(1, 2) ~= "--" then
            command_start = index
            break
        end

        if argument == "--jump-first" then
            jump_first = true
        elseif argument:sub(1, 11) == "--compiler=" then
            compiler = argument:sub(12)
        elseif argument:sub(1, 10) == "--display=" then
            local value = argument:sub(11)

            if value ~= "always" and value ~= "on_error" and value ~= "never" then
                return nil, string.format('Invalid Dispatch display mode "%s".', value)
            end

            display = value
        else
            return nil, string.format('Invalid Dispatch flag "%s".', argument)
        end

        command_start = index + 1
    end

    ---@type string[]
    local command = {}

    for index = command_start, #argv do
        table.insert(command, argv[index])
    end

    if #command == 0 then
        return nil, "Dispatch requires a command to run."
    end

    return {
        command = command,
        raw_command = table.concat(command, " "),
        compiler = compiler,
        display = display,
        jump_first = jump_first,
    },
        nil
end

--- Snapshot compiler-related options so they can be restored.
---
---@return table<string, any> # The saved compiler state.
function _P.get_compiler_state()
    return {
        current_compiler = vim.b.current_compiler,
        errorformat = vim.o.errorformat,
        makeprg = vim.o.makeprg,
    }
end

--- Restore a compiler state snapshot.
---
---@param state table<string, any> The state from `_P.get_compiler_state()`.
function _P.restore_compiler_state(state)
    if state.current_compiler == nil then
        vim.b.current_compiler = nil
    else
        vim.b.current_compiler = state.current_compiler
    end

    vim.o.errorformat = state.errorformat
    vim.o.makeprg = state.makeprg
end

--- Temporarily apply a compiler while `callback` runs.
---
---@param compiler string? The compiler to apply.
---@param callback fun(): nil The work to run with the compiler active.
function _P.with_compiler(compiler, callback)
    local state = _P.get_compiler_state()

    if compiler and compiler ~= "" then
        local extra_compiler = _P.extra_compilers[compiler]

        if extra_compiler then
            extra_compiler()
            vim.b.current_compiler = compiler
        else
            vim.cmd.compiler(compiler)
        end
    end

    local ok, message = pcall(callback)
    _P.restore_compiler_state(state)

    if not ok then
        error(message, 0)
    end
end

--- Convert raw output lines to quickfix entries using the active errorformat.
---
---@param lines string[] The raw command output.
---@return vim.quickfix.entry[] # Parsed and unparsed quickfix entries.
function _P.lines_to_quickfix(lines)
    local result = vim.fn.getqflist({
        lines = lines,
        efm = vim.o.errorformat,
    })

    return result.items or {}
end

--- Open a Neovim scratch output split.
---
---@return _my.dispatch.Display # The display sink.
function _P.open_vim_display()
    vim.cmd.botright("new")
    local window = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_get_current_buf()
    vim.bo[buffer].buftype = "nofile"
    vim.bo[buffer].bufhidden = "wipe"
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].filetype = "dispatch"

    return {
        write = function(lines)
            if not vim.api.nvim_buf_is_valid(buffer) then
                return
            end

            vim.bo[buffer].modifiable = true
            vim.api.nvim_buf_set_lines(buffer, -1, -1, false, lines)
            vim.bo[buffer].modifiable = false
        end,
        close = function()
            if vim.api.nvim_win_is_valid(window) then
                vim.api.nvim_win_close(window, true)
            end
        end,
    }
end

--- Clamp an oversized tmux display pane after tmux picks its natural split size.
---
---@param pane string The tmux pane id.
function _P.clamp_tmux_display_height(pane)
    local height_text = vim.fn.systemlist({ "tmux", "display-message", "-p", "-t", pane, "#{pane_height}" })[1]
    local height = tonumber(height_text)

    if height and height > _MAXIMUM_TMUX_DISPLAY_HEIGHT then
        vim.fn.system({ "tmux", "resize-pane", "-t", pane, "-y", tostring(_MAXIMUM_TMUX_DISPLAY_HEIGHT) })
    end
end

--- Open a tmux pane for mirrored command output.
---
---@return _my.dispatch.Display? # The display sink.
function _P.open_tmux_display()
    local core_helpers = require("modules.utilities.core_helpers")

    if not core_helpers.in_tmux() or not core_helpers.exists_command("tmux") then
        return nil
    end

    local pane = vim.fn.systemlist({ "tmux", "split-window", "-P", "-F", "#{pane_id}", "cat" })[1]

    if vim.v.shell_error ~= 0 or not pane or pane == "" then
        return nil
    end

    _P.clamp_tmux_display_height(pane)

    return {
        write = function(lines)
            for _, line in ipairs(lines) do
                vim.fn.system({ "tmux", "send-keys", "-t", pane, "-l", line })
                vim.fn.system({ "tmux", "send-keys", "-t", pane, "Enter" })
            end
        end,
        close = function()
            vim.fn.system({ "tmux", "kill-pane", "-t", pane })
        end,
    }
end

--- Open the preferred display sink.
---
---@return _my.dispatch.Display # The display sink.
function _P.open_display()
    return _P.open_tmux_display() or _P.open_vim_display()
end

--- Complete :Dispatch arguments.
---
---@param _ string The current argument lead.
---@param line string The whole command line.
---@return string[] # Completion candidates.
function _P.complete(_, line)
    local last = line:match("%S+$") or ""

    if last:match("^%-%-display=") then
        return { "--display=always", "--display=on_error", "--display=never" }
    end

    if last:match("^%-%-compiler=") then
        local prefix = last:gsub("^%-%-compiler=", "")
        ---@type string[]
        local names = vim.tbl_keys(_P.extra_compilers)
        local runtime_compilers = vim.api.nvim_get_runtime_file("compiler/*.vim", true)

        for _, path in ipairs(runtime_compilers) do
            local name = vim.fs.basename(tostring(path)):gsub("%.vim$", "")

            table.insert(names, name)
        end

        table.sort(names)

        ---@type string[]
        local output = {}

        for _, name in ipairs(names) do
            if name:sub(1, #prefix) == prefix then
                table.insert(output, "--compiler=" .. name)
            end
        end

        return output
    end

    if last:sub(1, 2) == "--" then
        return { "--compiler=", "--display=always", "--display=on_error", "--display=never", "--jump-first" }
    end

    return vim.fn.getcompletion(last, "shellcmd")
end

--- Finish a dispatch run by loading quickfix and opening it.
---
---@param options _my.dispatch.Options The dispatch options.
---@param lines string[] The raw output lines.
function _P.finish(options, lines)
    local first_valid_index = nil

    _P.with_compiler(options.compiler, function()
        local items = _P.lines_to_quickfix(lines)

        for index, item in ipairs(items) do
            if item.valid == 1 then
                first_valid_index = index
                break
            end
        end

        vim.fn.setqflist({}, "r", {
            title = "Dispatch: " .. options.raw_command,
            items = items,
        })
    end)

    vim.cmd("silent copen")

    if options.jump_first and first_valid_index then
        require("modules.utilities.core_helpers").with_file_messages_suppressed(function()
            vim.cmd.cc(first_valid_index)
        end)
    end
end

--- Run a parsed dispatch command.
---
---@param options _my.dispatch.Options The parsed options.
function M.run(options)
    ---@type string[]
    local output = {}
    ---@type _my.dispatch.Display?
    local display = nil

    if options.display == "always" then
        display = _P.open_display()
    end

    local pending_stdout = ""
    local pending_stderr = ""

    ---@param lines string[] The complete lines to append.
    local function append_complete_lines(lines)
        if #lines == 0 then
            return
        end

        vim.list_extend(output, lines)

        if display then
            display.write(lines)
        end
    end

    ---@param data string[]|nil The raw job callback data.
    ---@param stream "stdout"|"stderr" The stream being updated.
    local function append_job_data(data, stream)
        if not data or #data == 0 then
            return
        end

        local pending = stream == "stdout" and pending_stdout or pending_stderr
        data[1] = pending .. data[1]

        if stream == "stdout" then
            pending_stdout = data[#data]
        else
            pending_stderr = data[#data]
        end

        ---@type string[]
        local complete_lines = {}

        for index = 1, #data - 1 do
            if data[index] ~= "" then
                table.insert(complete_lines, data[index])
            end
        end

        append_complete_lines(complete_lines)
    end

    local function flush_pending_lines()
        ---@type string[]
        local lines = {}

        if pending_stdout ~= "" then
            table.insert(lines, pending_stdout)
            pending_stdout = ""
        end

        if pending_stderr ~= "" then
            table.insert(lines, pending_stderr)
            pending_stderr = ""
        end

        append_complete_lines(lines)
    end

    local job = vim.fn.jobstart(options.command, {
        cwd = vim.fn.getcwd(0, 0),
        stdin = "null",
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = function(_, data)
            append_job_data(data, "stdout")
        end,
        on_stderr = function(_, data)
            append_job_data(data, "stderr")
        end,
        on_exit = function(_, code)
            vim.schedule(function()
                flush_pending_lines()

                if display and options.display == "always" then
                    display.close()
                end

                if options.display == "on_error" and code ~= 0 then
                    display = _P.open_display()

                    if display then
                        display.write(output)
                    end
                end

                _P.finish(options, output)
            end)
        end,
    })

    if job <= 0 then
        vim.notify("Dispatch failed to start: " .. options.raw_command, vim.log.levels.ERROR)
    end
end

--- Run :Dispatch from command-line options.
---
---@param command_options vim.api.keyset.create_user_command.command_args The command arguments.
function M.dispatch(command_options)
    local options, error_message = _P.parse_arguments(command_options.args)

    if not options then
        vim.notify(error_message, vim.log.levels.ERROR)

        return
    end

    M.run(options)
end

vim.api.nvim_create_user_command("Dispatch", M.dispatch, {
    desc = "Run a command and load its output into quickfix.",
    nargs = "+",
    complete = _P.complete,
})

M._P = _P

return M
