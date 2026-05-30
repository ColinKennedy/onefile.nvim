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
            if callback then
                vim.schedule(function()
                    callback({ code = 0, stdout = "alpha\nbeta\n", stderr = "" })
                end)
            end

            ---@diagnostic disable-next-line: return-type-mismatch
            return {
                wait = function()
                    return { code = 0, stdout = "", stderr = "" }
                end,
            }
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

    it("keeps partial stdout from a failed command before calling the failure callback", function()
        local core_helpers = require("modules.utilities.core_helpers")
        local did_update = false
        local failed = false

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.system = function(_, _, callback)
            if callback then
                vim.schedule(function()
                    callback({ code = 2, stdout = "alpha\nbeta\n", stderr = "permission denied" })
                end)
            end

            ---@diagnostic disable-next-line: return-type-mismatch
            return {
                wait = function()
                    return { code = 0, stdout = "", stderr = "" }
                end,
            }
        end

        local results = core_helpers.get_deferred_shell_command_results({ "fake" }, function()
            failed = true
        end, function()
            did_update = true
        end)

        vim.wait(1000, function()
            return did_update and failed
        end)

        assert.same("alpha", results[1])
        assert.same("beta", results[2])
        assert.is_true(failed)
    end)
end)
