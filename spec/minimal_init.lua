--- Add required paths so that tests see all of the Neovim modules.

local _CURRENT_FILE = debug.getinfo(1, "S").source:sub(2)
local _CURRENT_RELATIVE_DIRECTORY = _CURRENT_FILE:match("(.+[/\\])")
local _CURRENT_ABSOLUTE_DIRECTORY = vim.fn.fnamemodify(_CURRENT_RELATIVE_DIRECTORY, ":p:h")
local _PROJECT_ROOT_DIRECTORY = vim.fs.dirname(_CURRENT_ABSOLUTE_DIRECTORY)

-- NOTE: Force unbuffered stdout so CI logs show test output (and any
-- failure) as it happens, instead of it all arriving in one block right
-- before the process exits, which can drop the trailing output entirely.
io.stdout:setvbuf("no")

-- Busted invokes Neovim differently across platforms, so `_G.arg[0]` is not
-- a reliable way for the configuration to recognize the test harness.
vim.g.my_is_running_busted = true

-- NOTE: `toggle_terminal` specs open a real terminal job. Without this, they
-- fall back to the user's interactive shell (e.g. a bare, banner-printing
-- `cmd.exe` on Windows CI runners), which sits waiting for input and can
-- swallow stray typeahead queued by earlier specs. Use a non-interactive
-- command instead: it still keeps the terminal buffer alive long enough for
-- the specs to inspect it, but it never reads a command line from stdin.
if not os.getenv("NEOVIM_SHELL_COMMAND") then
    if vim.fn.has("win32") == 1 then
        vim.env.NEOVIM_SHELL_COMMAND = (os.getenv("ComSpec") or "cmd.exe") .. ' /d /c "ping -n 6 127.0.0.1 >nul"'
    else
        vim.env.NEOVIM_SHELL_COMMAND = (os.getenv("SHELL") or "sh") .. " -c 'sleep 5'"
    end
end

package.path = package.path
    .. ";"
    .. _PROJECT_ROOT_DIRECTORY
    .. "/lua/?.lua"
    .. ";"
    .. _PROJECT_ROOT_DIRECTORY
    .. "/lua/?/init.lua"

vim.cmd.source(vim.fs.joinpath(_PROJECT_ROOT_DIRECTORY, "init.lua"))
