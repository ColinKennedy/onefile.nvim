describe("deferred shell command results", function()
    ---@type fun(cmd: string[], opts: vim.SystemOpts, on_exit?: fun(out: vim.SystemCompleted): nil): vim.SystemObj
    local original_system

    before_each(function()
        original_system = vim.system
    end)

    after_each(function()
        vim.system = original_system
    end)

    it("calls the update callback after async output is available", function()
        local core_helpers = require("modules.utilities.core_helpers")
        local did_update = false

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.system = function(_, _, callback)
            vim.schedule(function()
                callback({ code = 0, stdout = "alpha\nbeta\n", stderr = "" })
            end)

            ---@diagnostic disable-next-line: return-type-mismatch
            return {}
        end

        local results = core_helpers.get_deferred_shell_command_results({ "fake" }, nil, function()
            did_update = true
        end)

        assert.is_nil(results[1])
        vim.wait(1000, function()
            return did_update
        end)

        assert.same("alpha", results[1])
        assert.same("beta", results[2])
    end)
end)
