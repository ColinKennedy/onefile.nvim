local lsp_commands = require("modules.features.lsp_commands")

---@class _spec.lsp.Client
---@field name string
---@field server_capabilities table<string, any>|fun(): table<string, any>

--- Make a minimal LSP client for command tests.
---
---@param name string The client name.
---@param capabilities table<string, any>? Server capabilities.
---@return _spec.lsp.Client # A fake LSP client.
local function make_client(name, capabilities)
    local server_capabilities = capabilities or {}

    return {
        name = name,
        server_capabilities = setmetatable(server_capabilities, {
            __call = function()
                return server_capabilities
            end,
        }),
    }
end

describe("LSP commands", function()
    local original_get_clients
    local original_notify
    local original_setreg

    before_each(function()
        original_get_clients = vim.lsp.get_clients
        original_notify = vim.notify
        original_setreg = vim.fn.setreg
    end)

    after_each(function()
        vim.lsp.get_clients = original_get_clients
        vim.notify = original_notify
        vim.fn.setreg = original_setreg
    end)

    it("reports inactive LSP clients when none are attached", function()
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.lsp.get_clients = function()
            return {}
        end

        assert.equal("LSP Inactive", lsp_commands.get_attached_clients())
    end)

    it("lists attached LSP clients while ignoring null-ls and copilot", function()
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.lsp.get_clients = function()
            return {
                make_client("ty"),
                make_client("null-ls"),
                make_client("pylint"),
                make_client("copilot"),
                make_client("mypy"),
            }
        end

        assert.equal("[mypy, pylint, ty]", lsp_commands.get_attached_clients())
    end)

    it("notifies the attached client list with :LspClients", function()
        local message

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.lsp.get_clients = function()
            return { make_client("ty") }
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.notify = function(text)
            message = text
        end

        vim.cmd("LspClients")

        assert.equal("[ty]", message)
    end)

    it("builds sorted capability messages for reportable LSP clients", function()
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.lsp.get_clients = function()
            return {
                make_client("lua-language-server", {
                    completionProvider = {},
                    definitionProvider = true,
                    hoverProvider = false,
                    renameProvider = true,
                }),
                make_client("null-ls", {
                    formattingProvider = true,
                }),
            }
        end

        assert.are.same({
            "# lua-language-server\n- completion\n- definition\n- rename",
        }, lsp_commands.get_capabilities_messages())
    end)

    it("notifies capabilities and raw capability details", function()
        ---@type string[]
        local messages = {}

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.lsp.get_clients = function()
            return {
                make_client("lua-language-server", {
                    definitionProvider = true,
                }),
            }
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.notify = function(text)
            table.insert(messages, text)
        end

        vim.cmd("LspCapabilities")

        assert.equal("# lua-language-server\n- definition", messages[1])
        assert.is_true(messages[2]:find("lua-language-server Capabilities:", 1, true) ~= nil)
        assert.is_true(messages[2]:find("definitionProvider", 1, true) ~= nil)
    end)

    it("has descriptions for both LSP commands", function()
        local commands = vim.api.nvim_get_commands({ builtin = false })

        assert.equal("Show LSP clients attached to the current buffer.", commands.LspClients.definition)
        assert.equal(
            "Show capabilities for LSP clients attached to the current buffer.",
            commands.LspCapabilities.definition
        )
    end)
end)
