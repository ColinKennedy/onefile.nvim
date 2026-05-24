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
    command = "execute 'wundo ' . escape(undofile(expand('%')),'% ')",
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

---------- Settings [End] ----------

-- NOTE: If you need to override the shell, use $NEOVIM_SHELL_COMMAND
vim.opt.shell = os.getenv("NEOVIM_SHELL_COMMAND") or vim.opt.shell

---@type _my.lsp.ServerDefinition[]
M.servers = {
    -- {
    --     name = "basedpyright",
    --     filetypes = "python",
    --     callback = function(event)
    --         local command = "basedpyright-langserver"
    --
    --         if vim.fn.executable(command) ~= 1 then
    --             vim.notify(
    --                 string.format('Cannot load LSP. There is no "%s" executable.', command),
    --                 vim.log.levels.ERROR
    --             )
    --
    --             return
    --         end
    --
    --         vim.lsp.start({
    --             name = "basedpyright",
    --             cmd = { command, "--stdio" },
    --             settings = {
    --                 basedpyright = {
    --                     disableOrganizeImports = true,
    --                     analysis = {
    --                         typeCheckingMode = "basic",
    --                     },
    --                 },
    --             },
    --         }, { bufnr = event.buf })
    --     end,
    -- },
    {
        name = "ty",
        filetypes = "python",
        callback = function(event)
            local command = "ty"

            if vim.fn.executable(command) ~= 1 then
                vim.notify(
                    string.format('Cannot load LSP. There is no "%s" executable.', command),
                    vim.log.levels.ERROR
                )

                return
            end

            vim.lsp.start({
                name = "ty",
                cmd = { command, "server" },
            }, { bufnr = event.buf })
        end,
    },
    {
        name = "lua_ls",
        filetypes = { "lua" },
        callback = function(event)
            local paths = vim.tbl_deep_extend("force", {}, require("modules.utilities.core_helpers")._LUA_ROOT_PATHS)
            table.insert(paths, ".git")

            local command = "lua-language-server"

            if vim.fn.executable(command) ~= 1 then
                vim.schedule(function()
                    vim.notify(
                        string.format('Cannot load LSP. There is no "%s" executable.', command),
                        vim.log.levels.ERROR
                    )
                end)

                return
            end

            vim.lsp.start({
                cmd = { command },
                name = "lua-language-server",
                root_dir = vim.fs.root(0, paths),
            }, { bufnr = event.buf })
        end,
    },
}

return M
