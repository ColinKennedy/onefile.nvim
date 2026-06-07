--- Add required paths so that tests see all of the Neovim modules.

local _CURRENT_FILE = debug.getinfo(1, "S").source:sub(2)
local _CURRENT_RELATIVE_DIRECTORY = _CURRENT_FILE:match("(.+[/\\])")
local _CURRENT_ABSOLUTE_DIRECTORY = vim.fn.fnamemodify(_CURRENT_RELATIVE_DIRECTORY, ":p:h")
local _PROJECT_ROOT_DIRECTORY = vim.fs.dirname(_CURRENT_ABSOLUTE_DIRECTORY)

package.path = package.path
    .. ";"
    .. _PROJECT_ROOT_DIRECTORY
    .. "/lua/?.lua"
    .. ";"
    .. _PROJECT_ROOT_DIRECTORY
    .. "/lua/?/init.lua"

vim.cmd.source(vim.fs.joinpath(_PROJECT_ROOT_DIRECTORY, "init.lua"))
