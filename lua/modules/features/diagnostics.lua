local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
    --- Diagnostic symbols and colors
    -- The ctermfg colors are determined by your terminal (``echo $TERM``). Mine is
    -- ``screen-256color`` at the time of writing. Their chart is located here:
    --
    -- References:
    --     https://www.ditig.com/256-colors-cheat-sheet
    --     https://vim.fandom.com/wiki/Xterm256_color_names_for_console_Vim
    --
    vim.cmd("highlight DiagnosticVirtualTextError ctermfg=DarkRed guifg=DarkRed")
    vim.cmd("highlight DiagnosticVirtualTextWarn ctermfg=94 guifg=#875f00") -- Mustard-y
    vim.cmd("highlight DiagnosticVirtualTextInfo ctermfg=25 guifg=DeepSkyBlue4") -- Dark, desaturated blue
    vim.cmd("highlight link DiagnosticVirtualTextHint Comment") -- Dark gray

    vim.cmd("highlight DiagnosticError ctermfg=Red guifg=Red")
    vim.cmd("highlight DiagnosticWarn ctermfg=94 guifg=Orange")
    vim.cmd("highlight DiagnosticInfo ctermfg=26 guifg=DeepSkyBlue2") -- Lighter-ish blue
    vim.cmd("highlight DiagnosticSignHint ctermfg=7 guifg=#c0c0c0") -- Silver (gray)

    -- Reference: https://www.reddit.com/r/neovim/comments/l00zzb/improve_style_of_builtin_lsp_diagnostic_messages
    -- Errors in Red
    vim.cmd("highlight LspDiagnosticsVirtualTextError guifg=Red ctermfg=Red")
    -- Warnings in Yellow
    vim.cmd("highlight LspDiagnosticsVirtualTextWarning guifg=Yellow ctermfg=Yellow")
    -- Info and Hints in White
    vim.cmd("highlight LspDiagnosticsVirtualTextInformation guifg=White ctermfg=White")
    vim.cmd("highlight LspDiagnosticsVirtualTextHint guifg=White ctermfg=White")

    -- Underline the offending code
    vim.cmd("highlight LspDiagnosticsUnderlineError guifg=NONE ctermfg=NONE cterm=underline gui=underline")
    vim.cmd("highlight LspDiagnosticsUnderlineWarning guifg=NONE ctermfg=NONE cterm=underline gui=underline")
    vim.cmd("highlight LspDiagnosticsUnderlineInformation guifg=NONE ctermfg=NONE cterm=underline gui=underline")
    vim.cmd("highlight LspDiagnosticsUnderlineHint guifg=NONE ctermfg=NONE cterm=underline gui=underline")

    -- Add icons for the left-hand sign gutter
    if vim.fn.has("nvim-0.10") then
        vim.diagnostic.config({
            -- Reference: https://github.com/neovim/neovim/commit/ad191be65e2b1641c181506166b1037b548d14a8
            -- Reference: https://www.reddit.com/r/neovim/comments/10jh2jm/comment/j5koxew/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
            --
            severity_sort = true,
            signs = {
                numhl = {
                    [vim.diagnostic.severity.ERROR] = "DiagnosticSignError",
                    [vim.diagnostic.severity.HINT] = "DiagnosticSignHint",
                    [vim.diagnostic.severity.INFO] = "DiagnosticSignInfo",
                    [vim.diagnostic.severity.WARN] = "DiagnosticSignWarn",
                },
                text = {
                    -- Reference: www.nerdfonts.com/cheat-sheet
                    [vim.diagnostic.severity.ERROR] = "",
                    [vim.diagnostic.severity.HINT] = "",
                    [vim.diagnostic.severity.INFO] = "",
                    [vim.diagnostic.severity.WARN] = "⚠",
                },
                texthl = {
                    [vim.diagnostic.severity.ERROR] = "DiagnosticSignError",
                    [vim.diagnostic.severity.HINT] = "DiagnosticSignHint",
                    [vim.diagnostic.severity.INFO] = "DiagnosticSignInfo",
                    [vim.diagnostic.severity.WARN] = "DiagnosticSignWarn",
                },
            },
        })
    else
        -- NOTE: Remove this once we've dropped Neovim 0.9 support
        vim.fn.sign_define("DiagnosticSignError", {
            text = "", -- Reference: www.nerdfonts.com/cheat-sheet
            numhl = "DiagnosticSignError",
            texthl = "DiagnosticSignError",
        })
        vim.fn.sign_define("DiagnosticSignWarn", {
            text = "⚠", -- Reference: www.nerdfonts.com/cheat-sheet
            numhl = "DiagnosticSignWarn",
            texthl = "DiagnosticSignWarn",
        })
        vim.fn.sign_define("DiagnosticSignInfo", {
            text = "", -- Reference: www.nerdfonts.com/cheat-sheet
            numhl = "DiagnosticSignInfo",
            texthl = "DiagnosticSignInfo",
        })
        vim.fn.sign_define("DiagnosticSignHint", {
            text = "", -- Reference: www.nerdfonts.com/cheat-sheet
            numhl = "DiagnosticSignHint",
            texthl = "DiagnosticSignHint",
        })
    end

    -- Add a bordered frame around the diagnostics window
    -- TODO: I think this is no longer needed now that Neovim has default border styles.
    vim.lsp.handlers["textDocument/signatureHelp"] = function()
        vim.lsp.buf.signature_help({ border = "rounded", close_events = { "BufHidden", "InsertLeave" } })
    end

    -- TODO: I think this is no longer needed now that Neovim has default border styles.
    vim.lsp.handlers["textDocument/hover"] = function()
        vim.lsp.buf.hover({ border = "rounded" })
    end

    vim.diagnostic.config({ float = { border = "rounded" } })
end)
