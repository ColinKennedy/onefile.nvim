--- Register a small native Dispatch command.

vim.api.nvim_create_user_command("Dispatch", function(opts)
    require("modules.plugins.native_dispatch.core").dispatch(opts)
end, {
    bang = true,
    complete = "shellcmd",
    desc = "Run a command asynchronously and load parsed output into quickfix.",
    nargs = "*",
})