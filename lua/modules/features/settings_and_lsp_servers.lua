--- Configure editor options and collect built-in LSP server definitions.

local M = {}

---------- Saver [Start] ----------
-- NOTE: Create the :AsyncWrite command (for writing without blocking Neovim)
vim.api.nvim_create_user_command("AsyncWrite", function()
    local work = vim.loop.new_work(
        require("modules.features.core_editor_setup").write_async,
        require("modules.utilities.core_helpers").check_async_write
    )
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    work:queue(vim.api.nvim_buf_get_name(0), table.concat(lines, "\n"))
end, { desc = "Write all buffer lines to-disk in a separate thread." })
---------- Saver [End] ----------

---------- Settings [Start] ----------
vim.opt.scrolloff = 999 -- Center the cursor vertically on the screen

vim.opt.guicursor = "" -- Keeps the "fat cursor" in INSERT Mode

-- Allow a large undo history. Don't use swap files. Those are so 80's
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = true
local temporary_directory = os.getenv("HOME") or os.getenv("APPDATA")
vim.opt.undodir = temporary_directory .. "/.vim/undodir"
vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = "*",
    callback = function(event)
        local name = vim.api.nvim_buf_get_name(event.buf)

        if name == "" or vim.bo[event.buf].buftype ~= "" then
            return
        end

        vim.cmd("wundo " .. vim.fn.fnameescape(vim.fn.undofile(name)))
    end,
})

vim.opt.cmdheight = 2

-- Enables 24-bit RGB color
vim.opt.termguicolors = true

-- TODO: Set this differently depending on if in Python or not
vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("my.colors", { clear = true }),
    pattern = { "lua", "python" },
    callback = function()
        vim.opt_local.colorcolumn = "88"
    end,
})

vim.g.python_host_prog = "/bin/python"
-- Reference: https://www.inmotionhosting.com/support/server/linux/install-python-3-9-centos-7/
-- vim.g.python3_host_prog = "/usr/local/bin/python3.7"
vim.g.python3_host_prog = "/bin/python3.10"

-- Force Neovim to have one statusline for all buffers (rather than one-per-buffer)
--
-- Reference: https://github.com/neovim/neovim/pull/17266
--
vim.opt.laststatus = 3

-- Don't allow editor config files that I don't use for accidentally causing issues.
--
-- Reference: https://youtu.be/3TRouzuWOuQ?t=107
--
vim.g.editorconfig = false

-- Keep Neovim's cursor always centered
-- TODO: remove this pcall once Neovim 0.11 is dropped
pcall(function()
    vim.o.scrolloffpad = 1
end)

-- Allow local project .nvim.lua files to run on-Neovim-startup.
vim.o.exrc = true

---------- Settings [End] ----------

-- NOTE: If you need to override the shell, use $NEOVIM_SHELL_COMMAND
vim.opt.shell = os.getenv("NEOVIM_SHELL_COMMAND") or vim.opt.shell

---@type _my.lsp.ServerDefinition[]
M.servers = {
    {
        name = "ty",
        config = {
            cmd = { "ty", "server" },
            filetypes = { "python" },
        },
    },
    {
        name = "lua_ls",
        config = function()
            local paths = vim.tbl_deep_extend("force", {}, require("modules.utilities.core_helpers")._LUA_ROOT_PATHS)
            table.insert(paths, ".git")

            return {
                cmd = { "lua-language-server" },
                filetypes = { "lua" },
                root_markers = paths,
            }
        end,
    },
}

--- Configure and enable all built-in LSP servers.
---
---@param config_lsp? fun(name: string, config: vim.lsp.Config): nil Test seam for `vim.lsp.config`.
---@param enable_lsp? fun(name: string): nil Test seam for `vim.lsp.enable`.
function M.configure_lsp_servers(config_lsp, enable_lsp)
    config_lsp = config_lsp or function(name, config)
        vim.lsp.config(name, config)
    end
    enable_lsp = enable_lsp or function(name)
        vim.lsp.enable(name)
    end

    for _, server in ipairs(M.servers) do
        ---@type vim.lsp.Config
        local config

        if type(server.config) == "function" then
            config = (server.config --[[@as fun(): vim.lsp.Config]])()
        else
            config = server.config --[[@as vim.lsp.Config]]
        end

        config_lsp(server.name, config)
        enable_lsp(server.name)
    end
end

--- Check if Neovim is running the Busted test harness.
---
---@return boolean # If this process is running Busted, return `true`.
function M.is_running_busted()
    local arguments = _G.arg or {}

    return tostring(arguments[0] or ""):match("busted") ~= nil
end

---@type boolean
M.auto_configured_lsp_servers = false

if not M.is_running_busted() then
    M.auto_configured_lsp_servers = true
    M.configure_lsp_servers()
end

return M
