local core_helpers = require("modules.utilities.core_helpers")

--- A really basic git command wrapper.
vim.api.nvim_create_user_command("Git", function(opts)
    local arguments = table.concat(opts.fargs, " ")
    local command = string.format("%s %s", core_helpers._GIT_EXECUTABLE, arguments)

    vim.cmd.split()
    vim.cmd.enew()
    local buffer = vim.api.nvim_get_current_buf()

    vim.fn.jobstart(command, {
        term = true,
        on_exit = function(_, exit_code, _)
            if exit_code ~= 0 then
                -- NOTE: We leave the buffer open so that we can display the error.
                return
            end

            -- NOTE: We auto-close the terminal buffer when git process exits.
            if vim.api.nvim_buf_is_valid(buffer) then
                vim.api.nvim_buf_delete(buffer, { force = true })
            end
        end,
    })

    -- NOTE: Switch to terminal mode so we can immediately begin typing.
    vim.cmd.startinsert()
end, {
    desc = "A basic git wrapper.",
    nargs = "+",
    complete = function(_, _line)
        return { "add", "commit", "diff", "log", "pull", "push", "status" }
    end,
})
