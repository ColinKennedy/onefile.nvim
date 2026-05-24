--- Register native bookmark management inspired by grapple.nvim.
---
--- Reference:
---     https://www.reddit.com/r/neovim/comments/1js5bg8/comment/mloidmn/

for index = 1, 9 do
    vim.keymap.set("n", "<leader>" .. index, function()
        local core = require("modules.plugins.native_grapple.core")

        core.mark_current_buffer_as_bookmark(core.get_mark_from_index(index))
    end, { desc = "Toggle bookmark " .. tostring(index) })

    vim.keymap.set("n", "<leader>bd" .. index, function()
        require("modules.plugins.native_grapple.core").delete_bookmark(index)
    end, { desc = "[b]ookmark [d]elete " .. tostring(index) })
end

vim.keymap.set("n", "<M-S-j>", function()
    require("modules.plugins.native_grapple.core").go_to_relative_bookmark(1)
end, { desc = "Cycle to the next bookmark." })

vim.keymap.set("n", "<M-S-k>", function()
    require("modules.plugins.native_grapple.core").go_to_relative_bookmark(-1)
end, { desc = "Cycle to the previous bookmark." })

vim.keymap.set("n", "<M-S-l>", function()
    require("modules.plugins.native_grapple.core").show_bookmarks()
end, { desc = "List all bookmarks." })

vim.keymap.set("n", "<M-S-h>", function()
    require("modules.plugins.native_grapple.core").toggle_current_buffer()
end, { desc = "Delete bookmark." })

vim.api.nvim_create_autocmd({ "DirChanged", "FocusGained", "ShellCmdPost", "TermClose" }, {
    group = vim.api.nvim_create_augroup("my.native_grapple.branch_sync", { clear = true }),
    callback = function(args)
        local reference_path

        if args.event == "DirChanged" then
            reference_path = vim.v.event.cwd
        end

        require("modules.plugins.native_grapple.core").sync_branch(
            reference_path,
            { force = args.event ~= "DirChanged" }
        )
        vim.cmd.redrawstatus()
    end,
    desc = "Reload native grapple marks when the cwd or Git branch may have changed.",
})

vim.schedule(function()
    require("modules.plugins.native_grapple.core").sync_branch()
end)

vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("my.native_grapple.shutdown", { clear = true }),
    callback = function()
        local core = require("modules.plugins.native_grapple.core")

        core.write_current_branch_marks()
        core.teardown()
    end,
    desc = "Save native grapple marks and close branch watchers.",
})

require("modules.features.core_editor_setup")._SESSION_MANAGER:register_session_write_pre_callback(
    ".nvim.marks.lua",
    function()
        local core = require("modules.plugins.native_grapple.core")

        core.sync_branch()

        return table.concat(core.serialize_mark_code(core.get_current_root()), "\n")
    end
)
