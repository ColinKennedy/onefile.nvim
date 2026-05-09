--- Commands
local _REPOSITORY_ROOT = { ".git" }
local _REPOSITORY_OR_PROJECT_ROOT = vim.deepcopy(_REPOSITORY_ROOT)
table.insert(_REPOSITORY_OR_PROJECT_ROOT, "pyproject.toml")

vim.api.nvim_create_user_command("Rg", function(opts)
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

vim.api.nvim_create_user_command(
    "Pcd",
    function()
        require("modules.utilities.core_helpers").cd_to_parent_project_root()
    end,
    { nargs = 0, desc = "From the [P]roject, [c]hange [d]irectory." }
)
vim.api.nvim_create_user_command("Cedit", function(opts)
    require("modules.utilities.core_helpers").open_relative(opts.args)
end, {
    complete = function(text)
        return require("modules.utilities.core_helpers").complete_relative(text)
    end,
    nargs = 1,
    desc = "Open a file using a relative file path.",
})
