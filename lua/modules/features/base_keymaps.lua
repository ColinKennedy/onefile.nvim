local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
    --- Base keymaps

    ---------- Keymaps [Start] ----------
    options = { expr = true, noremap = true, silent = true }
    move_description = function(direction)
        return vim.tbl_deep_extend("force", options, { desc = string.format('Move to the "%s" window.', direction) })
    end
    vim.keymap.set("n", "<C-h>", "<C-w>h", move_description("left"))
    vim.keymap.set("n", "<C-j>", "<C-w>j", move_description("bottom"))
    vim.keymap.set("n", "<C-k>", "<C-w>k", move_description("top"))
    vim.keymap.set("n", "<C-l>", "<C-w>l", move_description("right"))

    resize_description = function(direction)
        return vim.tbl_deep_extend("force", options, { desc = string.format('Resize the "%s" window.', direction) })
    end
    vim.keymap.set("n", "<M-h>", function()
        _P.resize_window("left", 5)
    end, resize_description("left"))
    vim.keymap.set("n", "<M-j>", function()
        _P.resize_window("down", 2)
    end, resize_description("down"))
    vim.keymap.set("n", "<M-k>", function()
        _P.resize_window("up", 2)
    end, resize_description("up"))
    vim.keymap.set("n", "<M-l>", function()
        _P.resize_window("right", 5)
    end, resize_description("right"))

    -- Add numbered j/k movements to Vim's jumplist
    -- Reference: https://www.reddit.com/r/neovim/comments/1k3lhac/tiny_quality_of_life_rebind_make_j_and_k/
    vim.keymap.set("n", "j", function()
        if vim.v.count > 0 then
            return 'm"' .. vim.v.count .. "j"
        end

        return "j"
    end, { desc = "Add numbered j movements (e.g. 20j) to VIm's jumplist.", expr = true })

    vim.keymap.set("n", "k", function()
        if vim.v.count > 0 then
            return 'm"' .. vim.v.count .. "k"
        end

        return "k"
    end, { desc = "Add numbered k movements (e.g. 20k) to VIm's jumplist.", expr = true })

    -- Select the most recent text change you've made
    vim.keymap.set("n", "gp", "`[v`]", { desc = "Select the most recent text [p]ut you've done." })

    vim.keymap.set("v", ".", "<cmd>norm.<CR>", {
        desc = "Make `.` work with visually selected lines.",
    })

    vim.keymap.set("i", "jk", "<Esc>", { desc = "Escape to NORMAL mode." })
    vim.keymap.set("t", "jk", "<C-\\><C-n>", { desc = "Escape to NORMAL mode." })

    vim.keymap.set("n", "<leader>ss", ":%s/\\<<C-r><C-w>\\>/<C-r><C-w>/<Right>", {
        desc = "[s]ubstitute [s]election (in-file search/replace) for the word under your cursor.",
    })

    -- When typing in INSERT mode, pass through : if the cursor is to the left of it.
    vim.cmd("inoremap <expr> : search('\\%#:', 'n') ? '<Right>' : ':'")

    vim.keymap.set(
        "n",
        "<leader>j",
        "j:s/^\\s*//<CR>kgJ",
        { desc = "[j]oin this line with the line below, without whitespace." }
    )

    -- Basic mappings that can be used to make Vim "magic" by default
    -- Reference: https://stackoverflow.com/q/3760444
    -- Reference: http://vim.wikia.com/wiki/Simplifying_regular_expressions_using_magic_and_no-magic
    --
    description = { desc = 'Make Vim\'s search more "magic", by default.' }
    vim.keymap.set("n", "/", "/\\v", description)
    vim.keymap.set("v", "/", "/\\v", description)
    vim.keymap.set("c", "%s/", "%smagic/", description)
    vim.keymap.set("c", ">s/", ">smagic/", description)

    -- Copies the current file to the clipboard
    vim.cmd('command! CopyCurrentFile :let @+=expand("%:p")<bar>echo "Copied " . expand("%:p") . " to the clipboard"')
    vim.keymap.set("n", "<leader>cc", "<cmd>CopyCurrentFile<CR>", {
        desc = "[c]opy the [c]urrent file in the current window to the system clipboard. Assuming +clipboard.",
        silent = true,
    })

    -- Delete the current line, without the ending newline character, but
    -- still delete the line. This is useful for when you want to delete a
    -- line and insert it somewhere else without introducing extra newlines.
    -- e.g. `<leader>dilpi(` will delete the current line and then paste it
    -- within the next pair of parentheses.
    --
    vim.keymap.set(
        "n",
        "<leader>dil",
        '^v$hd"_dd',
        { desc = "[d]elete [i]nside the current [l]ine, without the ending newline character." }
    )

    -- A mapping that quickly expands to the current file's folder. Much
    -- easier than cd'ing to the current folder just to edit a single file.
    --
    vim.keymap.set("n", "<leader>e", ":Cedit ", { desc = "[e]xpand to the current file's folder." })

    vim.keymap.set(
        "n",
        "<leader>cd",
        "<cmd>lcd %:p:h<cr>:pwd<CR>",
        { desc = "[c]hange the [d]irectory (`:pwd`) to the directory of the current open window." }
    )

    vim.keymap.set("n", "<space>C", "<cmd>close<CR>", { desc = "[C]lose the current window." })

    vim.keymap.set("n", "J", "mzJ`z", {
        desc = "Keep the cursor in the same position while pressing ``J``.",
    })

    vim.keymap.set("n", "QQ", "<cmd>qall!<CR>", { desc = "Exit Vim without saving." })

    -- Reference: https://www.reddit.com/r/neovim/comments/16ztjvl/comment/k3hd4i1/?utm_source=share&utm_medium=web2x&context=3
    vim.keymap.set("x", "/", "<Esc>/\\%V", { desc = "Search for text some within a visual selection" })

    -- Change Vim to add numbered j/k  movement to the jumplist. It makes <C-o> and
    -- <C-i> remember more cursor positions.
    --
    vim.keymap.set("n", "k", function()
        if vim.v.count <= 1 then
            return "k"
        end

        return "m'" .. vim.v.count .. "k"
    end, { desc = "Include numbered-up-movements in Vim's jumplist", expr = true })

    vim.keymap.set("n", "j", function()
        if vim.v.count <= 1 then
            return "j"
        end

        return "m'" .. vim.v.count .. "j"
    end, { desc = "Include numbered-down-movements in Vim's jumplist", expr = true })

    -- Reference: https://github.com/neovim/neovim/issues/21422#issue-1497443707
    vim.keymap.set(
        "x",
        "Q",
        "<cmd>normal @<C-r>=reg_recorded()<CR><CR>",
        { desc = "Repeat the last recorded register on all selected lines." }
    )

    -- Reference: https://www.joshmedeski.com/posts/underrated-square-bracket
    vim.keymap.set("n", "]e", _P.go_to_diagnostic(true, "ERROR"), { desc = "Next diagnostic [e]rror." })
    vim.keymap.set("n", "[e", _P.go_to_diagnostic(false, "ERROR"), { desc = "Previous diagnostic [e]rror." })
    vim.keymap.set("n", "]w", _P.go_to_diagnostic(true, "WARN"), { desc = "Next diagnostic [w]arning." })
    vim.keymap.set("n", "[w", _P.go_to_diagnostic(false, "WARN"), { desc = "Previous diagnostic [w]arning." })

    vim.keymap.set("n", "[d", _P.go_to_diagnostic(false, nil), { desc = "Previous diagnostic issue." })
    vim.keymap.set("n", "]d", _P.go_to_diagnostic(true, nil), { desc = "Previous diagnostic issue." })

    vim.keymap.set("n", "=d", function()
        vim.diagnostic.open_float({ source = true })
    end, { desc = "Open the [d]iagnostics window for the current cursor." })

    vim.diagnostic.config({ virtual_text = false })

    -- Auto-Replace :cd to :tcd, which is better, all around
    --
    -- Reference: https://vim.fandom.com/wiki/Replace_a_builtin_command_using_cabbrev
    --
    vim.cmd("cabbrev cd <c-r>=(getcmdtype()==':' && getcmdpos()==1 ? 'tcd' : 'cd')<CR>")

    vim.keymap.set("n", "QA", function()
        vim.cmd("wqall")
    end, { desc = "[w]rite and [q]uit [all] buffers." })

    vim.keymap.set("n", "<leader>rs", "<cmd>normal 1z=<CR>", {
        desc = "[r]eplace word with [s]uggestion.",
        silent = true,
    })
    ---------- Keymaps [End] ----------
end)
