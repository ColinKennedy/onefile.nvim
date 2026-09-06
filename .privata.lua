--- Configuration for `make privata`.
return {
    -- Feature modules are internal parts of the same configuration and may
    -- deliberately share underscore-prefixed helpers.
    package_private = { "modules" },

    interfaces = {
        {
            expose = { "split_pair_on_enter" },
            from = { "modules\\.features\\.auto_pairs" },
        },
        {
            expose = { "get_window_line_progress" },
            from = { "modules\\.features\\.core_editor_setup" },
        },
        {
            expose = { "compute_marks", "is_enabled", "toggle" },
            from = { "modules\\.features\\.git_diff_view" },
        },
        {
            -- Test-visible state used to verify the modal UI is cleaned up.
            expose = { "is_active" },
            from = { "modules\\.features\\.git_add_submode" },
        },
        {
            expose = { "apply_closest_hunk", "apply_current_file" },
            from = { "modules\\.features\\.git_hunks" },
        },
        {
            expose = { "temporary_operator_paste" },
            from = { "modules\\.features\\.put_text_objects" },
        },
        {
            expose = { "get_quickfix_winbar_title" },
            from = { "modules\\.features\\.quickfix_winbar" },
        },
    },
}
