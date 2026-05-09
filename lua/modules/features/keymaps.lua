local core_editor_setup = require("modules.features.core_editor_setup")
local core_helpers = require("modules.utilities.core_helpers")

--- Keymaps
vim.keymap.set(
    "n",
    "<space>E",
    core_editor_setup.select_file_from_project_root,
    { desc = "Search And [E]dit a file from the project root." }
)
vim.keymap.set(
    "n",
    "<space>e",
    core_editor_setup.select_file_in_directory,
    { desc = "Search and [e]dit from the current directory." }
)
vim.keymap.set("n", "<space>B", core_helpers.select_buffer, { desc = "Select a [B]uffer and swtich to it." })
vim.keymap.set("n", "<leader>tq", core_editor_setup.toggle_quickfix, { desc = "Open or close the [q]uickfix buffer." })
vim.keymap.set(
    "i",
    "<C-Space>",
    core_editor_setup.show_snippet_completion,
    { noremap = true, desc = "Trigger snippet completion." }
)

vim.keymap.set({ "i", "n", "s" }, "<C-j>", function()
    if vim.snippet.active({ direction = 1 }) then
        return "<Cmd>lua vim.snippet.jump(1)<CR>"
    else
        return "<C-w>j"
    end
end, { desc = "Jump to the next snippet tabstop, if active.", expr = true, silent = true })

vim.keymap.set({ "i", "n", "s" }, "<C-k>", function()
    if vim.snippet.active({ direction = -1 }) then
        return "<Cmd>lua vim.snippet.jump(-1)<CR>"
    else
        return "<C-w>k"
    end
end, { desc = "Jump to the previous snippet tabstop, if active.", expr = true, silent = true })

vim.keymap.set("n", "<leader>td", function()
    vim.diagnostic.config({ virtual_lines = not vim.diagnostic.config().virtual_lines })
end, { desc = "[t]oggle [d]iagnostic as virtual_lines." })
