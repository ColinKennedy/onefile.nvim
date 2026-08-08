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

        ---@type string[] The nine cell labels, row-major (A..I).
        local LABELS = { "A", "B", "C", "D", "E", "F", "G", "H", "I" }

        --- Build a row-major 3x3 grid: col(row(A,B,C), row(D,E,F), row(G,H,I)).
        ---
        ---@return table<string, integer> # Window id keyed by cell label.
        local function build_grid()
            vim.cmd("silent! only")
            vim.cmd("split")
            vim.cmd("split")

            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                vim.api.nvim_set_current_win(win)
                vim.cmd("vsplit")
                vim.cmd("vsplit")
            end

            local cells = {}

            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                local position = vim.api.nvim_win_get_position(win)
                cells[#cells + 1] = { win = win, row = position[1], col = position[2] }
            end

            table.sort(cells, function(left, right)
                if left.row ~= right.row then
                    return left.row < right.row
                end

                return left.col < right.col
            end)

            local by_label = {}

            for index, cell in ipairs(cells) do
                by_label[LABELS[index]] = cell.win
            end

            return by_label
        end

        describe("grid geometry (no tmux)", function()
            local original_in_tmux

            before_each(function()
                original_in_tmux = core_helpers.in_tmux

                -- NOTE: Force "not in tmux" so neighbour detection stays purely
                -- inside Neovim and never shells out, regardless of the host.
                rawset(core_helpers, "in_tmux", function()
                    return false
                end)
            end)

            after_each(function()
                rawset(core_helpers, "in_tmux", original_in_tmux)
                vim.cmd("silent! only")
            end)

            -- Whether each key grows (true) or shrinks (false) the *current* cell.
            -- Covers all rows and columns, matching resize_ux_plan.md.
            local CASES = {
                { cell = "A", key = "j", grows = true },
                { cell = "A", key = "k", grows = false },
                { cell = "A", key = "h", grows = false },
                { cell = "A", key = "l", grows = true },
                { cell = "C", key = "j", grows = true },
                { cell = "C", key = "k", grows = false },
                { cell = "C", key = "h", grows = true },
                { cell = "C", key = "l", grows = false },
                { cell = "E", key = "j", grows = true },
                { cell = "E", key = "k", grows = false },
                { cell = "E", key = "h", grows = false },
                { cell = "E", key = "l", grows = true },
                { cell = "G", key = "j", grows = false },
                { cell = "G", key = "k", grows = true },
                { cell = "G", key = "h", grows = false },
                { cell = "G", key = "l", grows = true },
                { cell = "I", key = "j", grows = false },
                { cell = "I", key = "k", grows = true },
                { cell = "I", key = "h", grows = true },
                { cell = "I", key = "l", grows = false },
            }

            for _, case in ipairs(CASES) do
                local vertical = case.key == "j" or case.key == "k"
                local measure = vertical and vim.api.nvim_win_get_height or vim.api.nvim_win_get_width

                it(
                    string.format("cell %s: alt-%s %s it", case.cell, case.key, case.grows and "grows" or "shrinks"),
                    function()
                        local grid = build_grid()
                        local win = grid[case.cell]
                        vim.api.nvim_set_current_win(win)

                        local before = measure(win)
                        tmux_navigation.resize(case.key)
                        local after = measure(win)

                        -- NOTE: luassert accepts a failure message as the second
                        -- argument but the LuaCATS/luassert meta declares only
                        -- one parameter, so the message trips `redundant-parameter`.
                        if case.grows then
                            ---@diagnostic disable-next-line: redundant-parameter
                            assert.is_true(after > before, string.format("expected %s to grow", case.cell))
                        else
                            ---@diagnostic disable-next-line: redundant-parameter
                            assert.is_true(after < before, string.format("expected %s to shrink", case.cell))
                        end
                    end
                )
            end

            it("alt-j grows the whole row (vertical resizes are row-wide)", function()
                local grid = build_grid()
                vim.api.nvim_set_current_win(grid.A)

                local b_before = vim.api.nvim_win_get_height(grid.B)
                local c_before = vim.api.nvim_win_get_height(grid.C)

                tmux_navigation.resize("j")

                -- A's row-mates grow with it.
                assert.is_true(vim.api.nvim_win_get_height(grid.B) > b_before)
                assert.is_true(vim.api.nvim_win_get_height(grid.C) > c_before)
            end)

            it("alt-l is local to the row (horizontal resizes do not touch other rows)", function()
                local grid = build_grid()
                vim.api.nvim_set_current_win(grid.A)

                local d_before = vim.api.nvim_win_get_width(grid.D)
                local g_before = vim.api.nvim_win_get_width(grid.G)

                tmux_navigation.resize("l")

                -- The cells below A (same column, other rows) are untouched.
                assert.are.equal(d_before, vim.api.nvim_win_get_width(grid.D))
                assert.are.equal(g_before, vim.api.nvim_win_get_width(grid.G))
            end)
        end)

        describe("tmux panes", function()
            local original_in_tmux
            local original_system
            local tmux_commands
            -- Whether the mocked tmux reports a pane adjacent to Neovim.
            local adjacent_pane

            --- Build two full-width splits stacked top over bottom.
            ---
            ---@return integer, integer # top and bottom window ids.
            local function stacked_pair()
                vim.cmd("silent! only")
                vim.cmd("split")

                local windows = vim.api.nvim_tabpage_list_wins(0)
                table.sort(windows, function(left, right)
                    return vim.api.nvim_win_get_position(left)[1] < vim.api.nvim_win_get_position(right)[1]
                end)

                return windows[1], windows[2]
            end

            --- Build two full-height splits side by side.
            ---
            ---@return integer, integer # left and right window ids.
            local function side_by_side()
                vim.cmd("silent! only")
                vim.cmd("vsplit")

                local windows = vim.api.nvim_tabpage_list_wins(0)
                table.sort(windows, function(left, right)
                    return vim.api.nvim_win_get_position(left)[2] < vim.api.nvim_win_get_position(right)[2]
                end)

                return windows[1], windows[2]
            end

            before_each(function()
                original_in_tmux = core_helpers.in_tmux
                original_system = vim.fn.system
                tmux_commands = {}
                adjacent_pane = false

                rawset(core_helpers, "in_tmux", function()
                    return true
                end)

                -- NOTE: Answer `display-message` pane-edge queries with tmux's own
                -- convention ("0" = a neighbouring pane exists, "1" = flush against
                -- the edge). Those queries are not recorded, so assertions only see
                -- the resize commands under test.
                rawset(vim.fn, "system", function(arguments)
                    local joined = table.concat(arguments, " ")

                    if joined:find("display-message", 1, true) then
                        return adjacent_pane and "0\n" or "1\n"
                    end

                    table.insert(tmux_commands, joined)

                    return ""
                end)
            end)

            after_each(function()
                rawset(core_helpers, "in_tmux", original_in_tmux)
                rawset(vim.fn, "system", original_system)
                vim.cmd("silent! only")
            end)

            it("resizes a tmux pane below the bottom split instead of the split above", function()
                -- A pane below wins over the split above: alt-j resizes the pane.
                adjacent_pane = true
                local _, bottom = stacked_pair()
                vim.api.nvim_set_current_win(bottom)

                local starting_height = vim.api.nvim_win_get_height(bottom)

                tmux_navigation.resize("j")

                assert.are.same({ "tmux resize-pane -D 3" }, tmux_commands)
                assert.are.equal(starting_height, vim.api.nvim_win_get_height(bottom))
            end)

            it("resizes the bottom split against the split above when no tmux pane is below", function()
                -- No pane below: alt-j resizes Neovim, shrinking the bottom split.
                adjacent_pane = false
                local _, bottom = stacked_pair()
                vim.api.nvim_set_current_win(bottom)

                local starting_height = vim.api.nvim_win_get_height(bottom)

                tmux_navigation.resize("j")

                assert.are.same({}, tmux_commands)
                assert.is_true(vim.api.nvim_win_get_height(bottom) < starting_height)
            end)

            it("treats a tmux pane on the right as a neighbour of the right-most split", function()
                -- Seamless flip: the right-most split behaves like a middle cell,
                -- so both alt-l and alt-h act on the pane to its right.
                adjacent_pane = true
                local _, right = side_by_side()
                vim.api.nvim_set_current_win(right)

                local starting_width = vim.api.nvim_win_get_width(right)

                tmux_navigation.resize("l")
                assert.are.same({ "tmux resize-pane -R 3" }, tmux_commands)

                tmux_navigation.resize("h")
                assert.are.same({ "tmux resize-pane -R 3", "tmux resize-pane -L 3" }, tmux_commands)

                assert.are.equal(starting_width, vim.api.nvim_win_get_width(right))
            end)

            it("resizes the surrounding tmux pane for a lone window", function()
                adjacent_pane = true

                tmux_navigation.resize("j")
                tmux_navigation.resize("k")

                assert.are.same({ "tmux resize-pane -D 3", "tmux resize-pane -U 3" }, tmux_commands)
            end)

            it("does nothing for a lone window with no adjacent pane", function()
                adjacent_pane = false

                local starting_height = vim.api.nvim_win_get_height(0)
                tmux_navigation.resize("j")

                assert.are.same({}, tmux_commands)
                assert.are.equal(starting_height, vim.api.nvim_win_get_height(0))
            end)
        end)
    end)
end)
