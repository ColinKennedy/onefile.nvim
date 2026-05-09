---- Make [q + ]q / [l + ]l mappings auto-wrap. Seriously why are these not the default?

vim.keymap.set("n", "[q", function()
    local success = pcall(vim.cmd.cprevious)

    if not success then
        vim.cmd.clast()
    end
end, { desc = "Go to the previous Quickfix entry or wrap around to the end.", silent = true })

vim.keymap.set("n", "]q", function()
    local success = pcall(vim.cmd.cnext)

    if not success then
        vim.cmd.cfirst()
    end
end, { desc = "Go to the next Quickfix entry or wrap around to the start.", silent = true })

vim.keymap.set("n", "[l", function()
    local success = pcall(vim.cmd.lprevious)

    if not success then
        vim.cmd.llast()
    end
end, { desc = "Go to the previous Location List entry or wrap around to the end.", silent = true })

vim.keymap.set("n", "]l", function()
    local success = pcall(vim.cmd.lnext)

    if not success then
        vim.cmd.lfirst()
    end
end, { desc = "Go to the next Location List entry or wrap around to the start.", silent = true })
