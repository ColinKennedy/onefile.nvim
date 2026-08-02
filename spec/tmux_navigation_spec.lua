local tmux_navigation = require("modules.features.tmux_navigation")

describe("tmux navigation", function()
    describe("SendTmux", function()
        it("builds a tmux send-keys command for adjacent panes", function()
            assert.are.same(
                { "tmux", "send-keys", "-t", "{left-of}", "tttt" },
                tmux_navigation.get_send_text_arguments("left", "tttt")
            )
            assert.are.same(
                { "tmux", "send-keys", "-t", "{right-of}", "tttt" },
                tmux_navigation.get_send_text_arguments("right", "tttt")
            )
        end)

        it("converts literal CR markers into enter keys", function()
            assert.are.same(
                { "tmux", "send-keys", "-t", "{left-of}", "tttt", "Enter" },
                tmux_navigation.get_send_text_arguments("left", "tttt<CR>")
            )
            assert.are.same(
                { "tmux", "send-keys", "-t", "{left-of}", "foo", "Enter", "bar" },
                tmux_navigation.get_send_text_arguments("left", "foo<CR>bar")
            )
        end)

        it("completes only the direction argument", function()
            assert.are.same({ "left" }, tmux_navigation.complete_send_text("le", "SendTmux le"))
            assert.are.same({}, tmux_navigation.complete_send_text("tttt", "SendTmux left tttt"))
        end)
    end)

    describe("resize", function()
        local core_helpers = require("modules.utilities.core_helpers")
        local original_in_tmux
        local original_system
        local tmux_commands

        --- Build three full-width splits stacked on top of each other.
        ---
        ---@return integer[] # The window IDs ordered from top to bottom.
        local function stacked_windows()
            vim.cmd("split")
            vim.cmd("split")

            local windows = vim.api.nvim_tabpage_list_wins(0)

            table.sort(windows, function(left, right)
                return vim.api.nvim_win_get_position(left)[1] < vim.api.nvim_win_get_position(right)[1]
            end)

            return windows
        end

        before_each(function()
            original_in_tmux = core_helpers.in_tmux
            original_system = vim.fn.system
            tmux_commands = {}

            -- NOTE: Pretend we are always inside tmux so the tmux fallback path
            -- is exercised even when the tests do not run under tmux.
            core_helpers.in_tmux = function()
                return true
            end

            -- NOTE: Capture (and swallow) tmux CLI calls so tests never shell out.
            vim.fn.system = function(arguments)
                table.insert(tmux_commands, table.concat(arguments, " "))

                return ""
            end

            vim.cmd("silent! only")
        end)

        after_each(function()
            core_helpers.in_tmux = original_in_tmux
            vim.fn.system = original_system
            vim.cmd("silent! only")
        end)

        it("resizes the bottom split against the split above it instead of tmux", function()
            -- NOTE: A bottom-most split touches the screen's bottom edge but can
            -- still be resized by borrowing from the split above it. It must not
            -- short-circuit to a tmux pane resize.
            local windows = stacked_windows()
            local bottom = windows[3]
            vim.api.nvim_set_current_win(bottom)

            local starting_height = vim.api.nvim_win_get_height(bottom)

            tmux_navigation.resize("j")
            local after_shrink = vim.api.nvim_win_get_height(bottom)

            tmux_navigation.resize("k")
            local after_grow = vim.api.nvim_win_get_height(bottom)

            assert.is_true(after_shrink < starting_height)
            assert.is_true(after_grow > after_shrink)
            assert.are.same({}, tmux_commands)
        end)

        it("falls back to a tmux pane resize when no split can change", function()
            -- NOTE: With a single window there is nothing to resize against in
            -- Neovim, so we defer to the surrounding tmux pane.
            tmux_navigation.resize("j")
            tmux_navigation.resize("k")

            assert.are.same({
                "tmux resize-pane -D 3",
                "tmux resize-pane -U 3",
            }, tmux_commands)
        end)
    end)
end)
