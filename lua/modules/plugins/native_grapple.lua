local core_editor_setup = require("modules.features.core_editor_setup")
local core_helpers = require("modules.utilities.core_helpers")

--- A grapple.nvim replacement using only native Neovim
--
-- Reference:
--     https://www.reddit.com/r/neovim/comments/1js5bg8/comment/mloidmn/
--

for index = core_helpers._BOOKMARK_MINIMUM, core_helpers._BOOKMARK_MAXIMUM do
    local mark = core_helpers.get_vim_mark_from_bookmark_index(index)

    vim.keymap.set("n", "<leader>" .. index, function()
        core_helpers.mark_current_buffer_as_bookmark(mark)
    end, { desc = "Toggle bookmark " .. tostring(index) })
    vim.keymap.set("n", "<leader>bd" .. index, function()
        core_helpers.delete_bookmark(index)
    end, { desc = "[b]ookmark [d]elete " .. tostring(index) })
end

vim.keymap.set("n", "<M-S-j>", function()
    core_helpers.go_to_relative_bookmark(1)
end, { desc = "Cycle to the next bookmark." })
vim.keymap.set("n", "<M-S-k>", function()
    core_helpers.go_to_relative_bookmark(-1)
end, { desc = "Cycle to the previous bookmark." })
vim.keymap.set("n", "<M-S-l>", core_editor_setup.show_bookmarks, { desc = "List all bookmarks." })
vim.keymap.set("n", "<M-S-h>", core_editor_setup.toggle_bookmark_in_current_buffer, { desc = "Delete bookmark." })
core_editor_setup._SESSION_MANAGER:register_session_write_pre_callback(".nvim.marks.lua", function()
    local directory = vim.fn.getcwd()
    local root = core_helpers.get_nearest_project_root(directory)
    local data = core_editor_setup.serialize_mark_code(root)

    return table.concat(data, "\n")
end)
