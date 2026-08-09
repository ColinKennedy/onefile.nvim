--- The symbols that Lua code cannot be seen calling, but Vim still calls.
---
--- Everything declared here has a real caller. The caller just lives inside
--- a Vim expression string - a 'statusline' / 'winbar' template, an
--- 'operatorfunc' name, a `<Cmd>lua ...` mapping - which no static scan of the
--- Lua source can follow. Deleting any of these breaks the editor at runtime.
---
return {
    interfaces = {
        {
            -- Called by `<Cmd>lua require('modules.features.auto_pairs').split_pair_on_enter()<CR>`.
            expose = { "split_pair_on_enter" },
            from = { "lua\\.modules\\.features\\.auto_pairs" },
        },
        {
            -- Called by the 'statusline' template in `modules.features.statusline`,
            -- as `%{v:lua.get_window_line_progress()}`.
            expose = { "get_window_line_progress" },
            from = { "lua\\.modules\\.features\\.core_editor_setup" },
        },
        {
            -- Called by Vim as 'operatorfunc', set to
            -- `v:lua.require'modules.features.put_text_objects'.temporary_operator_paste`.
            expose = { "temporary_operator_paste" },
            from = { "lua\\.modules\\.features\\.put_text_objects" },
        },
        {
            -- Called by the quickfix 'winbar' template, `M.WINBAR_EXPRESSION`.
            expose = { "get_quickfix_winbar_title" },
            from = { "lua\\.modules\\.features\\.quickfix_winbar" },
        },
    },
}
