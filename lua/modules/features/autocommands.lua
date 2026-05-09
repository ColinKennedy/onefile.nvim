local core_helpers = require("modules.utilities.core_helpers")
local settings_and_lsp_servers = require("modules.features.settings_and_lsp_servers")

--- Autocommands
for _, data in ipairs(settings_and_lsp_servers.servers) do
    vim.api.nvim_create_autocmd("FileType", {
        group = core_helpers._LSP_GROUP,
        pattern = data.filetypes,
        callback = data.callback,
    })
end

-- Add tree-sitter highlighting if a parser is found
vim.api.nvim_create_autocmd("FileType", {
    callback = function()
        local treesitter = require("vim.treesitter")

        local buffer = vim.api.nvim_get_current_buf()
        local filetype = vim.bo[buffer].filetype
        local treesitter_language = core_helpers._FILETYPE_TO_TREESITTER[filetype] or filetype

        local success, result = pcall(function()
            treesitter.query.get(treesitter_language, "highlights")
        end)

        if not success then
            return
        end

        -- NOTE: If there are tree-sitter highlights, use it. If not, use Vim regex.
        if not result then
            vim.bo[buffer].syntax = "on"
        else
            pcall(function()
                vim.treesitter.start(buffer, treesitter_language)
            end)
        end
    end,
})

vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(event)
        require("modules.features.core_editor_setup").setup_lsp_details(event)
    end,
    group = core_helpers._LSP_GROUP,
})

-- NOTE: Make sure long lines do not wrap to the next line
vim.api.nvim_create_autocmd("FileType", {
    pattern = "qf",
    callback = function()
        vim.opt_local.wrap = false
        vim.opt_local.relativenumber = false
        vim.opt_local.number = false
        vim.opt_local.signcolumn = "no"
    end,
})
