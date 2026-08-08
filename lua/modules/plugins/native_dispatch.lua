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
---@field allow_duplicates boolean? Whether to keep back-to-back repeats of one location.

---@class _my.dispatch.Defaults
---@field display _my.dispatch.DisplayMode Whether to show command output while it runs.
---@field jump_first boolean Whether to jump to the first parsed quickfix item.

-- The flags that `:Dispatch` implies. They are what we want 90%+ of the time.
---@type _my.dispatch.Defaults
local _QUIET_DEFAULTS = { display = "on_error", jump_first = true }

-- The flags that `:DispatchOutput` implies. Mirror output while the command runs.
---@type _my.dispatch.Defaults
local _OUTPUT_DEFAULTS = { display = "always", jump_first = false }

---@class _my.dispatch.Display
---@field write fun(lines: string[]): nil
---@field close fun(): nil

---@type table<string, fun(): nil>
_P.extra_compilers = {
    vimgrep = function()
        vim.opt.errorformat = { "%f:%l:%c:%m", "%f:%l:%m" }
    end,
}

--- Run a command and return its output lines.
---
---@param command string[] The argv-style command to run.
---@return string[] # The command output lines.
function _P.systemlist(command)
    return vim.fn.systemlist(command)
end

--- Run a command and return its output text.
---
---@param command string[] The argv-style command to run.
---@return string # The command output.
function _P.system(command)
    return vim.fn.system(command)
end

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
---@param defaults _my.dispatch.Defaults? The flags to assume when the user omits them.
---@return _my.dispatch.Options? options Parsed options.
---@return string? error_message A human-readable parse error.
function _P.parse_arguments(arguments, defaults)
    defaults = defaults or _OUTPUT_DEFAULTS
    local argv = _P.parse_argv(arguments)
    ---@type string?
    local compiler = nil
    ---@type _my.dispatch.DisplayMode
    local display = defaults.display
    local command_start = 1
    local jump_first = defaults.jump_first
    local allow_duplicates = false

    for index, argument in ipairs(argv) do
        if argument:sub(1, 2) ~= "--" then
            command_start = index
            break
        end

        if argument == "--jump-first" then
            jump_first = true
        elseif argument == "--no-jump-first" then
            jump_first = false
        elseif argument == "--allow-duplicates" then
            allow_duplicates = true
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
        allow_duplicates = allow_duplicates,
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

--- Get the location that `item` points at, if it points at one at all.
---
--- Only entries that name a real file and line have a location. Unparsed output
--- lines all share an empty location, so they report `nil` and are never treated
--- as repeats of each other.
---
---@param item vim.quickfix.entry The quickfix entry to inspect.
---@return string? # The `buffer:line:column` location, if `item` has one.
function _P.get_entry_location(item)
    local buffer = item.bufnr or 0
    local line = item.lnum or 0

    if item.valid ~= 1 or buffer == 0 or line == 0 then
        return nil
    end

    return string.format("%d:%d:%d", buffer, line, item.col or 0)
end

--- Drop entries that repeat the location of the entry right before them.
---
--- Some tools report the same file, line, and column many times in a row. Only
--- the first of each run is worth showing. The same location later in the output
--- is kept because something else came between the two.
---
--- The entry text is deliberately ignored. Two reports of one location are
--- repeats even when their messages differ.
---
---@param items vim.quickfix.entry[] The parsed quickfix entries.
---@return vim.quickfix.entry[] # The entries, minus back-to-back repeats.
function _P.remove_consecutive_duplicates(items)
    ---@type vim.quickfix.entry[]
    local output = {}
    ---@type string?
    local previous = nil

    for _, item in ipairs(items) do
        local location = _P.get_entry_location(item)

        if location == nil or location ~= previous then
            table.insert(output, item)
        end

        previous = location
    end

    return output
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
    local height_text = _P.systemlist({ "tmux", "display-message", "-p", "-t", pane, "#{pane_height}" })[1]
    local height = tonumber(height_text)

    if height and height > _MAXIMUM_TMUX_DISPLAY_HEIGHT then
        _P.system({ "tmux", "resize-pane", "-t", pane, "-y", tostring(_MAXIMUM_TMUX_DISPLAY_HEIGHT) })
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

    local pane = _P.systemlist({ "tmux", "split-window", "-P", "-F", "#{pane_id}", "cat" })[1]

    if vim.v.shell_error ~= 0 or not pane or pane == "" then
        return nil
    end

    _P.clamp_tmux_display_height(pane)

    return {
        write = function(lines)
            for _, line in ipairs(lines) do
                _P.system({ "tmux", "send-keys", "-t", pane, "-l", line })
                _P.system({ "tmux", "send-keys", "-t", pane, "Enter" })
            end
        end,
        close = function()
            _P.system({ "tmux", "kill-pane", "-t", pane })
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
        return {
            "--allow-duplicates",
            "--compiler=",
            "--display=always",
            "--display=never",
            "--display=on_error",
            "--jump-first",
            "--no-jump-first",
        }
    end

    return vim.fn.getcompletion(last, "shellcmd")
end

--- Get the quickfix title that a dispatch run claims as its own.
---
---@param options _my.dispatch.Options The dispatch options.
---@return string # The title to write onto the quickfix list.
function _P.get_quickfix_title(options)
    return "Dispatch: " .. options.raw_command
end

--- Drop a passing run's stale results, but only if they are that run's own.
---
--- A passing command has nothing to show. Whatever is in quickfix belongs to
--- somebody else (a `:Ripgrep` search, a diff, an earlier command) unless this
--- exact command put it there, so leave it alone rather than clobbering it.
---
---@param options _my.dispatch.Options The dispatch options.
function _P.clear_previous_results(options)
    if vim.fn.getqflist({ title = true }).title ~= _P.get_quickfix_title(options) then
        return
    end

    vim.fn.setqflist({}, "r", { title = _P.get_quickfix_title(options), items = {} })
    vim.cmd("silent! cclose")
end

--- Finish a dispatch run by loading quickfix and opening it.
---
---@param options _my.dispatch.Options The dispatch options.
---@param lines string[] The raw output lines.
---@param code integer? The command exit code.
function _P.finish(options, lines, code)
    local first_valid_index = nil
    ---@type vim.quickfix.entry[]
    local items = {}

    _P.with_compiler(options.compiler, function()
        items = _P.lines_to_quickfix(lines)

        if not options.allow_duplicates then
            items = _P.remove_consecutive_duplicates(items)
        end

        for index, item in ipairs(items) do
            if item.valid == 1 then
                first_valid_index = index
                break
            end
        end
    end)

    if code == 0 and not first_valid_index then
        _P.clear_previous_results(options)
        vim.notify(string.format("Dispatch passed: %s", options.raw_command), vim.log.levels.INFO)

        return
    end

    vim.fn.setqflist({}, "r", {
        title = _P.get_quickfix_title(options),
        items = items,
    })

    require("modules.utilities.core_helpers").with_file_messages_suppressed(function()
        vim.cmd("silent copen")
    end)

    if options.jump_first and first_valid_index then
        require("modules.utilities.core_helpers").with_file_messages_suppressed(function()
            vim.cmd.cc(first_valid_index)
        end)
    end
end

--- Restore a saved window layout once Neovim settles at its original height.
---
--- A tmux display pane resizes Neovim asynchronously: opening it shrinks the
--- host pane and closing it grows the host pane back a moment later, each firing
--- a delayed `VimResized`. Re-applying the layout immediately would fight the
--- pending resize and leave the windows worse than before, so when Neovim is
--- still shrunk we wait for the resize back to `total_lines` before restoring.
---
---@param layout string A `vim.fn.winrestcmd()` snapshot.
---@param total_lines integer `vim.o.lines` captured before the display opened.
function _P.restore_window_layout(layout, total_lines)
    if not layout or layout == "" then
        return
    end

    -- Already back at the original height (the in-editor split fallback, or the
    -- tmux resize has already settled): restore now, no need to watch for more.
    if vim.o.lines >= total_lines then
        pcall(function()
            vim.cmd(layout)
        end)

        return
    end

    ---@type integer?
    local autocmd_id
    autocmd_id = vim.api.nvim_create_autocmd("VimResized", {
        desc = "Restore window sizes after a Dispatch display pane closes.",
        callback = function()
            -- Ignore the shrink events; only restore once Neovim has grown back.
            if vim.o.lines < total_lines then
                return
            end

            pcall(function()
                vim.cmd(layout)
            end)

            if autocmd_id then
                pcall(vim.api.nvim_del_autocmd, autocmd_id)
            end
        end,
    })
end

--- Run a parsed dispatch command.
---
---@param options _my.dispatch.Options The parsed options.
function M.run(options)
    ---@type string[]
    local output = {}
    ---@type _my.dispatch.Display?
    local display = nil
    ---@type string?
    local window_layout = nil
    local window_total_lines = vim.o.lines

    if options.display == "always" then
        -- Opening a tmux display pane shrinks Neovim's host pane, which makes
        -- Neovim re-flow every window. Snapshot the current window sizes so the
        -- user's splits (for example a bottom terminal) are restored to their
        -- original heights once the display pane closes.
        window_layout = vim.fn.winrestcmd()
        window_total_lines = vim.o.lines
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

                if window_layout then
                    _P.restore_window_layout(window_layout, window_total_lines)
                end

                _P.finish(options, output, code)
            end)
        end,
    })

    if job <= 0 then
        vim.notify("Dispatch failed to start: " .. options.raw_command, vim.log.levels.ERROR)
    end
end

--- Run a dispatch command from command-line options.
---
---@param command_options vim.api.keyset.create_user_command.command_args The command arguments.
---@param defaults _my.dispatch.Defaults The flags to assume when the user omits them.
function _P.dispatch(command_options, defaults)
    local options, error_message = _P.parse_arguments(command_options.args, defaults)

    if not options then
        vim.notify(error_message, vim.log.levels.ERROR)

        return
    end

    M.run(options)
end

--- Run :Dispatch from command-line options.
---
---@param command_options vim.api.keyset.create_user_command.command_args The command arguments.
function M.dispatch(command_options)
    _P.dispatch(command_options, _QUIET_DEFAULTS)
end

--- Run :DispatchOutput from command-line options.
---
---@param command_options vim.api.keyset.create_user_command.command_args The command arguments.
function M.dispatch_output(command_options)
    _P.dispatch(command_options, _OUTPUT_DEFAULTS)
end

vim.api.nvim_create_user_command("Dispatch", M.dispatch, {
    desc = "Run a command quietly and load its output into quickfix.",
    nargs = "+",
    complete = _P.complete,
})

vim.api.nvim_create_user_command("DispatchOutput", M.dispatch_output, {
    desc = "Run a command, mirror its output live, and load it into quickfix.",
    nargs = "+",
    complete = _P.complete,
})

M._P = _P

return M
