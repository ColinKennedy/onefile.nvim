local settings_and_lsp_servers = require("modules.features.settings_and_lsp_servers")

describe("settings and LSP servers", function()
    it("configures and enables declarative LSP configs instead of starting on FileType", function()
        local configured = {}
        local enabled = {}

        settings_and_lsp_servers.configure_lsp_servers(function(name, config)
            configured[name] = config
        end, function(name)
            table.insert(enabled, name)
        end)

        assert.are.same({ "ty", "server" }, configured.ty.cmd)
        assert.are.same({ "python" }, configured.ty.filetypes)
        assert.is_nil(configured.ty.callback)
        assert.is_nil(configured.ty.executable)
        assert.is_table(configured.lua_ls.root_markers)
        assert.are.same({ "ty", "lua_ls" }, enabled)
    end)
end)
