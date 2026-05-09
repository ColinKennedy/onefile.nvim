--- Register commands for inspecting LSP clients and capabilities.

local M = {}

local _IGNORED_CLIENTS = {
    ["copilot"] = true,
    ["null-ls"] = true,
}

--- Check if `client` should be shown in user-facing LSP reports.
---
---@param client vim.lsp.Client The LSP client to inspect.
---@return boolean # If `client` should be listed, return `true`.
local function _is_reportable_client(client)
    return not _IGNORED_CLIENTS[client.name]
end

--- Get reportable LSP clients attached to `buffer`.
---
---@param buffer integer The buffer to inspect.
---@return vim.lsp.Client[] # Attached LSP clients, excluding hidden/meta clients.
function M.get_reportable_clients(buffer)
    local clients = vim.lsp.get_clients({ bufnr = buffer })
    ---@type vim.lsp.Client[]
    local output = {}

    for _, client in ipairs(clients) do
        if _is_reportable_client(client) then
            table.insert(output, client)
        end
    end

    return output
end

--- Get a summary of LSP clients attached to the current buffer.
---
---@return string # A display summary of attached LSP client names.
function M.get_attached_clients()
    local clients = M.get_reportable_clients(0)

    if #clients == 0 then
        return "LSP Inactive"
    end

    ---@type string[]
    local names = {}

    for _, client in ipairs(clients) do
        table.insert(names, client.name)
    end

    table.sort(names)

    return "[" .. table.concat(names, ", ") .. "]"
end

--- Notify the user of the current buffer's LSP clients.
function M.show_attached_clients()
    vim.notify(M.get_attached_clients(), vim.log.levels.INFO)
end

--- Get a sorted list of capability names supported by `client`.
---
---@param client vim.lsp.Client The LSP client to inspect.
---@return string[] # Capability names without the trailing "Provider" suffix.
function M.get_client_capabilities(client)
    ---@type string[]
    local capabilities = {}

    for key, value in pairs(client.server_capabilities or {}) do
        if value and key:find("Provider") then
            local capability = key:gsub("Provider$", "")

            table.insert(capabilities, capability)
        end
    end

    table.sort(capabilities)

    return capabilities
end

--- Build Markdown messages describing all current-buffer LSP capabilities.
---
---@return string[] # One Markdown message per reportable client.
function M.get_capabilities_messages()
    local clients = M.get_reportable_clients(vim.api.nvim_get_current_buf())
    ---@type string[]
    local messages = {}

    for _, client in ipairs(clients) do
        local capabilities = M.get_client_capabilities(client)
        ---@type string[]
        local lines = { "# " .. client.name }

        for _, capability in ipairs(capabilities) do
            table.insert(lines, "- " .. capability)
        end

        table.insert(messages, table.concat(lines, "\n"))
    end

    return messages
end

--- Notify the user of the current buffer's LSP server capabilities.
function M.show_capabilities()
    local clients = M.get_reportable_clients(vim.api.nvim_get_current_buf())

    if #clients == 0 then
        vim.notify("LSP Inactive", vim.log.levels.INFO)

        return
    end

    for _, client in ipairs(clients) do
        local capabilities = M.get_client_capabilities(client)
        ---@type string[]
        local lines = { "# " .. client.name }

        for _, capability in ipairs(capabilities) do
            table.insert(lines, "- " .. capability)
        end

        vim.notify(table.concat(lines, "\n"), vim.log.levels.TRACE, {
            on_open = function(window)
                local buffer = vim.api.nvim_win_get_buf(window)

                vim.bo[buffer].filetype = "markdown"
            end,
            timeout = 14000,
        })

        vim.notify(
            string.format("%s Capabilities:\n%s", client.name, vim.inspect(client.server_capabilities())),
            vim.log.levels.INFO
        )
    end
end

vim.api.nvim_create_user_command("LspClients", M.show_attached_clients, {
    desc = "Show LSP clients attached to the current buffer.",
})

vim.api.nvim_create_user_command("LspCapabilities", M.show_capabilities, {
    desc = "Show capabilities for LSP clients attached to the current buffer.",
})

return M
