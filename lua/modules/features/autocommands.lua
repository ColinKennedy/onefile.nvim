local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
    --- Autocommands
    for _, data in ipairs(servers) do
        vim.api.nvim_create_autocmd("FileType", {
            group = _LSP_GROUP,
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
            local treesitter_language = _FILETYPE_TO_TREESITTER[filetype] or filetype

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

    vim.api.nvim_create_autocmd("LspAttach", { callback = _P.setup_lsp_details, group = _LSP_GROUP })

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
end)
