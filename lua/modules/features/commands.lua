--- Register project-aware commands for ripgrep search and project-root detection.

---@type string[]
local _REPOSITORY_ROOT = { ".git" }
local _REPOSITORY_OR_PROJECT_ROOT = vim.deepcopy(_REPOSITORY_ROOT)
table.insert(_REPOSITORY_OR_PROJECT_ROOT, "pyproject.toml")

--- Notify that `command` cannot be run for the current buffer.
---
---@param command string The command name that failed.
---@param message string The reason that the command failed.
local function _notify_buffer_command_error(command, message)
    vim.notify(string.format(":%s %s", command, message), vim.log.levels.ERROR)
end

--- Get the current listed buffer's file path.
---
---@param command string The command name to mention in errors.
---@return integer? # The current buffer, if it is usable.
---@return string? # The current buffer file path, if any.
local function _get_current_file_buffer(command)
    local buffer = vim.api.nvim_get_current_buf()
    local path = vim.api.nvim_buf_get_name(buffer)

    if not vim.bo[buffer].buflisted then
        _notify_buffer_command_error(command, "requires a listed buffer.")

        return nil, nil
    end

    if path == "" or vim.fn.filereadable(path) ~= 1 then
        _notify_buffer_command_error(command, "requires a buffer pointing to a file on-disk.")

        return nil, nil
    end

    return buffer, path
end

--- Delete the current buffer's file and then delete the buffer.
local function _delete_current_file()
    local buffer, path = _get_current_file_buffer("Delete")

    if not buffer or not path then
        return
    end

    local result = vim.fn.delete(path)

    if result ~= 0 then
        _notify_buffer_command_error("Delete", string.format('could not delete "%s".', path))

        return
    end

    vim.api.nvim_buf_delete(buffer, { force = true })
end

--- Resolve `target` relative to the directory containing `source`.
---
---@param source string The source file path.
---@param target string The user-provided target path.
---@return string # The resolved absolute target path.
local function _resolve_move_target(source, target)
    if vim.fn.fnamemodify(target, ":p") == target then
        return vim.fs.normalize(target)
    end

    return vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(source), target))
end

--- Move the current buffer's file to `target`.
---
---@param options vim.api.keyset.create_user_command.command_args The command options.
local function _move_current_file(options)
    local buffer, source = _get_current_file_buffer("Move")

    if not buffer or not source then
        return
    end

    local target = _resolve_move_target(source, options.args)

    if source == target then
        return
    end

    if vim.fn.filereadable(target) == 1 then
        if not options.bang then
            _notify_buffer_command_error("Move", string.format('cannot be saved because "%s" already exists.', target))

            return
        end
    elseif vim.fn.isdirectory(target) == 1 then
        _notify_buffer_command_error("Move", string.format('cannot be saved because "%s" is a directory.', target))

        return
    end

    local parent = vim.fs.dirname(target)

    if vim.fn.isdirectory(parent) ~= 1 then
        _notify_buffer_command_error("Move", string.format('cannot be saved because "%s" does not exist.', parent))

        return
    end

    local ok, error_message = pcall(function()
        vim.api.nvim_buf_call(buffer, function()
            vim.cmd("silent keepalt saveas! " .. vim.fn.fnameescape(target))
        end)
    end)

    if not ok then
        _notify_buffer_command_error("Move", string.format('could not save "%s": %s', target, error_message))

        return
    end

    if vim.fn.delete(source) ~= 0 then
        _notify_buffer_command_error("Move", string.format('could not delete "%s".', source))
    end
end

--- Send command-line text to an adjacent tmux pane.
---
---@param options vim.api.keyset.create_user_command.command_args The command options.
local function _send_tmux_text(options)
    require("modules.features.tmux_navigation").send_text_from_command(options.args)
end

--- Complete the direction argument for `:SendTmux`.
---
---@param argument_lead string The current argument fragment.
---@param command_line string The whole command line.
---@return string[] # Matching tmux pane directions.
local function _complete_send_tmux_text(argument_lead, command_line)
    return require("modules.features.tmux_navigation").complete_send_text(argument_lead, command_line)
end

vim.api.nvim_create_user_command("Rg", function(opts)
    ---@cast opts _neovim.commandline.Options
    require("modules.utilities.core_helpers").run_ripgrep_command(opts)
end, { nargs = 1, desc = "Search using ripgrep." })

--- Find the nearest directory that matches `pattern`.
---
---@param pattern string[] a file name. e.g. `"tox.ini"`.
---@return string? # The found directory, if any.
---
local function _get_directory(pattern)
    local directory = vim.fs.root(0, pattern) or vim.fs.root(vim.fn.getcwd(), pattern)

    if directory then
        return directory
    end

    vim.notify(
        string.format('No "%s" root could be found from this buffer or from "%s" directory.', vim.fn.getcwd()),
        vim.log.levels.ERROR
    )

    return nil
end

--- Run ripgrep from `directory` with `options`.
---
---@param directory string The path on-disk to start searching from within.
---@param options {fargs: string[]} User-provided arguments to add to the `rg` command.
---
local function _run_rg(directory, options)
    ---@type string[]
    local command = { "Rg" }
    vim.list_extend(command, options.fargs)
    table.insert(command, directory)
    vim.cmd(vim.fn.join(command, " "))
end

vim.api.nvim_create_user_command("Crg", function(options)
    local path = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    local directory

    if path == "" then
        directory = vim.fn.getcwd()
    else
        directory = vim.fs.dirname(path)
    end

    _run_rg(directory, options)
end, {
    desc = "From the [C]urrent file, search with [r]ip[g]rep.",
    nargs = "*",
})

vim.api.nvim_create_user_command("Rrg", function(options)
    local directory = _get_directory(_REPOSITORY_ROOT)

    if not directory then
        return
    end

    _run_rg(directory, options)
end, {
    desc = "From the [R]repository, search with [r]ip[g]rep.",
    nargs = "*",
})

vim.api.nvim_create_user_command("Prg", function(options)
    local directory = _get_directory(_REPOSITORY_OR_PROJECT_ROOT)

    if not directory then
        return
    end

    _run_rg(directory, options)
end, {
    desc = "From the [P]roject directory, search with [r]ip[g]rep.",
    nargs = "*",
})

vim.api.nvim_create_user_command("Pcd", function()
    require("modules.utilities.core_helpers").cd_to_parent_project_root()
end, { nargs = 0, desc = "From the [P]roject, [c]hange [d]irectory." })
vim.api.nvim_create_user_command("Delete", _delete_current_file, {
    nargs = 0,
    desc = "Delete the current file and its buffer.",
})
vim.api.nvim_create_user_command("Move", _move_current_file, {
    bang = true,
    complete = "file",
    nargs = 1,
    desc = "Move the current file and rename its buffer.",
})
vim.api.nvim_create_user_command("SendTmux", _send_tmux_text, {
    complete = _complete_send_tmux_text,
    desc = "Send text to an adjacent tmux pane.",
    nargs = "+",
})
vim.api.nvim_create_user_command("Cedit", function(opts)
    require("modules.utilities.core_helpers").open_relative(opts.args)
end, {
    complete = function(text)
        return require("modules.utilities.core_helpers").complete_relative(text)
    end,
    nargs = 1,
    desc = "Open a file using a relative file path.",
})
