local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
--- A grapple.nvim replacement using only native Neovim
--
-- Reference:
--     https://www.reddit.com/r/neovim/comments/1js5bg8/comment/mloidmn/?utm_source=share&utm_medium=web3x&utm_name=web3xcss
--

for index = _BOOKMARK_MINIMUM, _BOOKMARK_MAXIMUM do
    local mark = _P.get_vim_mark_from_bookmark_index(index)

    vim.keymap.set("n", "<leader>" .. index, function()
        _P.mark_current_buffer_as_bookmark(mark)
    end, { desc = "Toggle bookmark " .. tostring(index) })
    vim.keymap.set("n", "<leader>bd" .. index, function()
        _P.delete_bookmark(index)
    end, { desc = "[b]ookmark [d]elete " .. tostring(index) })
end

vim.keymap.set("n", "<M-S-j>", function()
    _P.go_to_relative_bookmark(1)
end, { desc = "Cycle to the next bookmark." })
vim.keymap.set("n", "<M-S-k>", function()
    _P.go_to_relative_bookmark(-1)
end, { desc = "Cycle to the previous bookmark." })
vim.keymap.set("n", "<M-S-l>", _P.show_bookmarks, { desc = "List all bookmarks." })
vim.keymap.set("n", "<M-S-h>", _P.toggle_bookmark_in_current_buffer, { desc = "Delete bookmark." })

_SESSION_MANAGER:register_session_write_pre_callback(".nvim.marks.lua", function()
    local directory = vim.fn.getcwd()
    local root = _P.get_nearest_project_root(directory)
    local data = _P.serialize_mark_code(root)

    return table.concat(data, "\n")
end)
end)
