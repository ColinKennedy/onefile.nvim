local core_editor_setup = require("modules.features.core_editor_setup")

--- Get the floating list window created by the selector UI.
---
---@return integer # The list window.
local function get_selector_list_window()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local configuration = vim.api.nvim_win_get_config(window)
        local buffer = vim.api.nvim_win_get_buf(window)

        if configuration.relative == "editor" and vim.api.nvim_buf_line_count(buffer) > 1 then
            return window
        end
    end

    error("No selector list window was found.", 0)
end

--- Get the floating prompt window created by the selector UI.
---
---@return integer # The prompt window.
local function get_selector_prompt_window()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local configuration = vim.api.nvim_win_get_config(window)
        local buffer = vim.api.nvim_win_get_buf(window)

        if configuration.relative == "editor" and vim.api.nvim_buf_line_count(buffer) == 1 then
            return window
        end
    end

    error("No selector prompt window was found.", 0)
end

--- Get the selector preview window by filetype.
---
---@param filetype string The expected preview filetype.
---@return integer # The preview window.
local function get_selector_preview_window(filetype)
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local configuration = vim.api.nvim_win_get_config(window)
        local buffer = vim.api.nvim_win_get_buf(window)

        if configuration.relative == "editor" and vim.bo[buffer].filetype == filetype then
            return window
        end
    end

    error("No selector preview window was found.", 0)
end

--- Close all floating windows.
local function close_floating_windows()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(window).relative ~= "" then
            vim.api.nvim_win_close(window, true)
        end
    end
end

--- Press keys in the selector prompt.
---
---@param keys string The keys to press.
local function press(keys)
    local mapping = vim.fn.maparg(keys, "i", false, true)

    assert.is_function(mapping.callback)
    mapping.callback()
end

--- Press normal-mode keys in the selector prompt.
---
---@param keys string The keys to press.
local function press_normal(keys)
    local mapping = vim.fn.maparg(keys, "n", false, true)

    assert.is_function(mapping.callback)
    mapping.callback()
end

describe("selector UI", function()
    local original_lines
    local original_columns
    local original_scrolloff

    before_each(function()
        original_lines = vim.o.lines
        original_columns = vim.o.columns
        original_scrolloff = vim.o.scrolloff
        vim.o.lines = 24
        vim.o.columns = 80
        vim.o.scrolloff = 999
    end)

    after_each(function()
        vim.cmd.stopinsert()
        close_floating_windows()
        vim.o.lines = original_lines
        vim.o.columns = original_columns
        vim.o.scrolloff = original_scrolloff
    end)

    it("keeps the selected row centered after it reaches the middle of the view", function()
        ---@type string[]
        local values = {}

        for index = 1, 40 do
            table.insert(values, string.format("item-%02d", index))
        end

        local refresh = core_editor_setup.select_from_options(values, {
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
        })

        refresh()

        for _ = 1, 20 do
            press("<C-n>")
        end

        local list_window = get_selector_list_window()
        local list_buffer = vim.api.nvim_win_get_buf(list_window)
        local lines = vim.api.nvim_buf_get_lines(list_buffer, 0, -1, false)
        local selected_row = nil

        for index, line in ipairs(lines) do
            if line:sub(1, 2) == "> " then
                selected_row = index

                break
            end
        end

        assert.is_not_nil(selected_row)
        assert.is_true(selected_row > 1)
        assert.is_true(selected_row < #lines)

        local window_info = vim.fn.getwininfo(list_window)[1]
        local cursor_line = vim.api.nvim_win_get_cursor(list_window)[1]
        local anchor_row = math.floor((vim.api.nvim_win_get_height(list_window) + 1) / 2)

        assert.are.same(anchor_row, cursor_line - window_info.topline + 1)
        assert.is_true(window_info.topline > 1)
    end)

    it("pads the bottom so the selected row can stay centered at the end", function()
        ---@type string[]
        local values = {}

        for index = 1, 12 do
            table.insert(values, string.format("item-%02d", index))
        end

        local refresh = core_editor_setup.select_from_options(values, {
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
        })

        refresh()

        for _ = 1, 30 do
            press("<C-n>")
        end

        local list_window = get_selector_list_window()
        local list_buffer = vim.api.nvim_win_get_buf(list_window)
        local window_info = vim.fn.getwininfo(list_window)[1]
        local cursor_line = vim.api.nvim_win_get_cursor(list_window)[1]
        local anchor_row = math.floor((vim.api.nvim_win_get_height(list_window) + 1) / 2)

        assert.are.same(anchor_row, cursor_line - window_info.topline + 1)
        assert.is_true(vim.api.nvim_buf_line_count(list_buffer) > (#values + 1))
    end)

    it("renders unselectable header chunks as a pinned list winbar", function()
        local refresh = core_editor_setup.select_from_options({ "alpha", "beta" }, {
            header = {
                { text = "/tmp/project", highlight = "Directory" },
            },
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
        })

        refresh()

        local list_window = get_selector_list_window()
        local list_buffer = vim.api.nvim_win_get_buf(list_window)
        local lines = vim.api.nvim_buf_get_lines(list_buffer, 0, 2, false)

        assert.are.same("%#Directory#/tmp/project%*", vim.wo[list_window].winbar)
        assert.are.same("> alpha", lines[1])
        assert.are.same("  beta", lines[2])
    end)

    it("keeps the pinned header visible while the list scrolls", function()
        ---@type string[]
        local values = {}

        for index = 1, 40 do
            table.insert(values, string.format("item-%02d", index))
        end

        local refresh = core_editor_setup.select_from_options(values, {
            header = {
                { text = "/tmp/project", highlight = "Directory" },
            },
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
        })

        refresh()

        for _ = 1, 20 do
            press("<C-n>")
        end

        local list_window = get_selector_list_window()
        local window_info = vim.fn.getwininfo(list_window)[1]

        assert.are.same("%#Directory#/tmp/project%*", vim.wo[list_window].winbar)
        assert.is_true(window_info.topline > 1)
    end)

    it("escapes percent signs in pinned selector headers", function()
        local refresh = core_editor_setup.select_from_options({ "alpha", "beta" }, {
            header = {
                { text = "/tmp/100%/project", highlight = "Directory" },
            },
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
        })

        refresh()

        local list_window = get_selector_list_window()

        assert.are.same("%#Directory#/tmp/100%%/project%*", vim.wo[list_window].winbar)
    end)
    it("renders a top preview window with the requested filetype", function()
        local refresh = core_editor_setup.select_from_options({ "alpha" }, {
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
            preview = {
                location = "top",
                min_height = 4,
                height_ratio = 0.5,
                render = function(entry)
                    return {
                        buftype = "nofile",
                        filetype = "lua",
                        lines = { "local value = " .. entry.value },
                    }
                end,
            },
        })

        refresh()

        local preview_window = get_selector_preview_window("lua")
        local preview_buffer = vim.api.nvim_win_get_buf(preview_window)

        assert.equal("nofile", vim.bo[preview_buffer].buftype)
        assert.are.same({ "local value = alpha" }, vim.api.nvim_buf_get_lines(preview_buffer, 0, -1, false))
        local preview_row = vim.api.nvim_win_get_config(preview_window).row
        local prompt_row = vim.api.nvim_win_get_config(get_selector_prompt_window()).row

        assert.is_true(preview_row < prompt_row)
    end)

    it("scrolls a top preview window from the prompt", function()
        local refresh = core_editor_setup.select_from_options({ "alpha" }, {
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
            preview = {
                location = "top",
                min_height = 4,
                height_ratio = 0.5,
                render = function()
                    ---@type string[]
                    local lines = {}

                    for index = 1, 40 do
                        table.insert(lines, "line " .. index)
                    end

                    return {
                        buftype = "nofile",
                        filetype = "markdown",
                        lines = lines,
                    }
                end,
            },
        })

        refresh()

        local preview_window = get_selector_preview_window("markdown")
        local before = vim.fn.getwininfo(preview_window)[1].topline
        press("<C-d>")
        local after = vim.fn.getwininfo(preview_window)[1].topline

        assert.is_true(after > before)
    end)

    it("keeps a top preview scrolled after the selector refreshes", function()
        local refresh = core_editor_setup.select_from_options({ "alpha" }, {
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
            preview = {
                location = "top",
                min_height = 4,
                height_ratio = 0.5,
                render = function()
                    ---@type string[]
                    local lines = {}

                    for index = 1, 40 do
                        table.insert(lines, "line " .. index)
                    end

                    return {
                        buftype = "nofile",
                        filetype = "markdown",
                        lines = lines,
                    }
                end,
            },
        })

        refresh()

        local preview_window = get_selector_preview_window("markdown")
        press("<C-d>")
        local scrolled = vim.fn.getwininfo(preview_window)[1].topline
        refresh()
        local refreshed = vim.fn.getwininfo(preview_window)[1].topline

        assert.is_true(scrolled > 1)
        assert.equal(scrolled, refreshed)
    end)

    it("scrolls a top preview after moving to another selected item", function()
        local refresh = core_editor_setup.select_from_options({ "alpha", "beta" }, {
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
            preview = {
                location = "top",
                min_height = 4,
                height_ratio = 0.5,
                render = function(entry)
                    ---@type string[]
                    local lines = {}

                    for index = 1, 40 do
                        table.insert(lines, entry.value .. " line " .. index)
                    end

                    return {
                        buftype = "nofile",
                        filetype = "markdown",
                        lines = lines,
                    }
                end,
            },
        })

        refresh()
        press("<C-n>")

        local preview_window = get_selector_preview_window("markdown")
        local before = vim.fn.getwininfo(preview_window)[1].topline
        press("<C-d>")
        local after = vim.fn.getwininfo(preview_window)[1].topline

        assert.is_true(after > before)
    end)

    it("debounces preview rendering after moving selection", function()
        local render_count = 0
        local refresh = core_editor_setup.select_from_options({ "alpha", "beta" }, {
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
            preview = {
                location = "top",
                min_height = 4,
                height_ratio = 0.5,
                render = function(entry)
                    render_count = render_count + 1

                    return {
                        buftype = "nofile",
                        filetype = "markdown",
                        lines = { "preview " .. entry.value },
                    }
                end,
            },
        })

        refresh()
        assert.equal(1, render_count)

        press("<C-n>")
        assert.equal(1, render_count)

        vim.wait(1000, function()
            return render_count == 2
        end)

        local preview_window = get_selector_preview_window("markdown")
        local preview_buffer = vim.api.nvim_win_get_buf(preview_window)

        assert.equal(2, render_count)
        assert.are.same({ "preview beta" }, vim.api.nvim_buf_get_lines(preview_buffer, 0, -1, false))
    end)

    it("renders a right preview window and scrolls it from the prompt", function()
        local refresh = core_editor_setup.select_from_options({ "alpha" }, {
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
            preview = {
                location = "right",
                min_height = 4,
                width_ratio = 0.5,
                render = function()
                    ---@type string[]
                    local lines = {}

                    for index = 1, 40 do
                        table.insert(lines, "line " .. index)
                    end

                    return {
                        buftype = "nofile",
                        filetype = "diff",
                        lines = lines,
                    }
                end,
            },
        })

        refresh()

        local preview_window = get_selector_preview_window("diff")
        local prompt_window = get_selector_prompt_window()
        local before = vim.fn.getwininfo(preview_window)[1].topline
        press("<C-d>")
        local after = vim.fn.getwininfo(preview_window)[1].topline

        assert.is_true(vim.api.nvim_win_get_config(preview_window).col > vim.api.nvim_win_get_config(prompt_window).col)
        assert.is_true(after > before)
    end)

    it("preserves filtered source order unless sorting is explicitly enabled", function()
        local refresh = core_editor_setup.select_from_options({
            "lua/modules/plugins/todo_comment_highlighting.lua",
            "lua/modules/features/autocommands.lua",
        }, {
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
        })

        local prompt_window = get_selector_prompt_window()
        local prompt_buffer = vim.api.nvim_win_get_buf(prompt_window)
        vim.api.nvim_buf_set_lines(prompt_buffer, 0, -1, false, { "autcom" })
        refresh()

        local list_window = get_selector_list_window()
        local list_buffer = vim.api.nvim_win_get_buf(list_window)
        local lines = vim.api.nvim_buf_get_lines(list_buffer, 0, 2, false)

        assert.are.same({
            "> lua/modules/plugins/todo_comment_highlighting.lua",
            "  lua/modules/features/autocommands.lua",
        }, lines)
    end)

    it("can opt into file-path sorting after filtering", function()
        local refresh = core_editor_setup.select_from_options({
            "lua/modules/plugins/todo_comment_highlighting.lua",
            "lua/modules/features/autocommands.lua",
        }, {
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
            sort_maximum = 200,
            sort_score = core_editor_setup.get_file_selector_sort_score,
        })

        local prompt_window = get_selector_prompt_window()
        local prompt_buffer = vim.api.nvim_win_get_buf(prompt_window)
        vim.api.nvim_buf_set_lines(prompt_buffer, 0, -1, false, { "autcom" })
        refresh()

        local list_window = get_selector_list_window()
        local list_buffer = vim.api.nvim_win_get_buf(list_window)
        local lines = vim.api.nvim_buf_get_lines(list_buffer, 0, 2, false)

        assert.are.same({
            "> lua/modules/features/autocommands.lua",
            "  lua/modules/plugins/todo_comment_highlighting.lua",
        }, lines)
    end)

    it("skips opt-in sorting when filtered results exceed the configured maximum", function()
        local values = {}

        for index = 1, 201 do
            table.insert(values, string.format("path/to/file_%03d.lua", index))
        end

        local refresh = core_editor_setup.select_from_options(values, {
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
            sort_maximum = 200,
            sort_score = function(entry)
                return entry.display == "path/to/file_201.lua" and 1000 or 0
            end,
        })

        local prompt_window = get_selector_prompt_window()
        local prompt_buffer = vim.api.nvim_win_get_buf(prompt_window)
        vim.api.nvim_buf_set_lines(prompt_buffer, 0, -1, false, { "file" })
        refresh()

        local list_window = get_selector_list_window()
        local list_buffer = vim.api.nvim_win_get_buf(list_window)
        local lines = vim.api.nvim_buf_get_lines(list_buffer, 0, 1, false)

        assert.are.same({ "> path/to/file_001.lua" }, lines)
    end)

    it("highlights the selected row like a visual selection with brighter selected text", function()
        local refresh = core_editor_setup.select_from_options({ "alpha", "beta" }, {
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
        })

        refresh()

        local list_window = get_selector_list_window()
        local list_buffer = vim.api.nvim_win_get_buf(list_window)
        local marks = vim.api.nvim_buf_get_extmarks(list_buffer, -1, 0, -1, { details = true })
        local found_visual = false
        local found_prefix = false
        local found_current_line = false

        for _, mark in ipairs(marks) do
            local details = mark[4]

            if details and details.line_hl_group == "Visual" then
                found_visual = true

                break
            end
        end

        for _, mark in ipairs(marks) do
            local details = mark[4]

            if details and details.hl_group == "SelectorCurrentPrefix" then
                found_prefix = true

                break
            end
        end

        for _, mark in ipairs(marks) do
            local details = mark[4]

            if details and details.hl_group == "SelectorCurrentLine" then
                found_current_line = true

                break
            end
        end

        assert.is_true(found_visual)
        assert.is_true(found_prefix)
        assert.is_true(found_current_line)

        local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
        local selected = vim.api.nvim_get_hl(0, { name = "SelectorCurrentLine", link = false })

        assert.is_not.same(normal.fg, selected.fg)
        assert.is_true(selected.bold)
    end)

    it("shows filtered and total match counts in the prompt", function()
        local refresh = core_editor_setup.select_from_options({ "alpha", "beta", "gamma" }, {
            confirm = function() end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
        })

        local prompt_window = get_selector_prompt_window()
        local prompt_buffer = vim.api.nvim_win_get_buf(prompt_window)

        vim.api.nvim_buf_set_lines(prompt_buffer, 0, 1, false, { "al" })
        refresh()

        local marks = vim.api.nvim_buf_get_extmarks(prompt_buffer, -1, 0, -1, { details = true })
        local count_text = nil

        for _, mark in ipairs(marks) do
            local details = mark[4]

            if details and details.virt_text then
                count_text = details.virt_text[1][1]
                assert.are.same("Comment", details.virt_text[1][2])

                break
            end
        end

        assert.are.same("1/3", count_text)
    end)

    it("toggles multi-selected rows and confirms selected entries even when filtered out", function()
        local confirmed = nil
        local refresh = core_editor_setup.select_from_options({ "alpha", "beta", "gamma" }, {
            multiple_selection = true,
            confirm = function(entries)
                confirmed = entries
            end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
        })

        refresh()
        press("<Tab>")
        press("<C-n>")
        press("<Tab>")

        local list_window = get_selector_list_window()
        local list_buffer = vim.api.nvim_win_get_buf(list_window)
        local lines = vim.api.nvim_buf_get_lines(list_buffer, 0, 3, false)

        assert.are.same(" > alpha", lines[1])
        assert.are.same(">> beta", lines[2])

        local found_selected_marker = false
        local selection_marks = vim.api.nvim_buf_get_extmarks(list_buffer, -1, 0, -1, { details = true })

        for _, mark in ipairs(selection_marks) do
            local details = mark[4]

            if details and details.hl_group == "SelectorSelectedMarker" then
                found_selected_marker = true

                break
            end
        end

        assert.is_true(found_selected_marker)

        local prompt_window = get_selector_prompt_window()
        local prompt_buffer = vim.api.nvim_win_get_buf(prompt_window)
        vim.api.nvim_buf_set_lines(prompt_buffer, 0, 1, false, { "gamma" })
        refresh()

        local marks = vim.api.nvim_buf_get_extmarks(prompt_buffer, -1, 0, -1, { details = true })
        local count_text = nil

        for _, mark in ipairs(marks) do
            local details = mark[4]

            if details and details.virt_text then
                count_text = details.virt_text[1][1]

                break
            end
        end

        assert.are.same("1/3 (2)", count_text)

        vim.cmd.stopinsert()
        press_normal("<CR>")
        vim.wait(100, function()
            return confirmed ~= nil
        end)
        assert.is_not_nil(confirmed)
        ---@cast confirmed _my.selector_gui.entry.Selection[]

        assert.are.same("alpha", confirmed[1].value)
        assert.are.same("beta", confirmed[2].value)
    end)

    it("confirms the hovered entry as a one-item list when multi-select has no explicit selections", function()
        local confirmed = nil
        local refresh = core_editor_setup.select_from_options({ "alpha", "beta" }, {
            multiple_selection = true,
            confirm = function(entries)
                confirmed = entries
            end,
            deserialize = function(value)
                return { display = value, value = value }
            end,
        })

        refresh()
        vim.cmd.stopinsert()
        press_normal("<CR>")
        vim.wait(100, function()
            return confirmed ~= nil
        end)
        assert.is_not_nil(confirmed)
        ---@cast confirmed _my.selector_gui.entry.Selection[]

        assert.are.same(1, #confirmed)
        assert.are.same("alpha", confirmed[1].value)
    end)

    it("shortens selector directory headers with home and parent abbreviations", function()
        local header = core_editor_setup.shorten_selector_directory_path(
            "/home/selecaoone/repositories/personal/.config/noplugins",
            "/home/selecaoone"
        )

        assert.are.same("~/r/p/.c/noplugins", header)
    end)

    it("shortens Windows selector directory headers with home and parent abbreviations", function()
        local header = core_editor_setup.shorten_selector_directory_path(
            [[C:\Users\selecaoone\repositories\personal\.config\noplugins]],
            [[c:\users\selecaoone]]
        )

        assert.are.same("~/r/p/.c/noplugins", header)
    end)

    it("shortens Windows drive paths when they are outside home", function()
        local header = core_editor_setup.shorten_selector_directory_path(
            [[D:\work\repositories\personal\noplugins]],
            [[C:\Users\selecaoone]]
        )

        assert.are.same("D:/w/r/p/noplugins", header)
    end)

    it("keeps single-segment selector directory headers readable", function()
        local header = core_editor_setup.shorten_selector_directory_path("/tmp", "/home/selecaoone")

        assert.are.same("/tmp", header)
    end)

    it("<Space>E uses multi-select file selection", function()
        local core_helpers = require("modules.utilities.core_helpers")
        local original_select_from_options = core_editor_setup.select_from_options
        local original_get_project_root = core_helpers.get_nearest_project_root
        local original_exists_command = core_helpers.exists_command
        local original_get_deferred_results = core_helpers.get_deferred_shell_command_results
        ---@type _my.selection_gui.GuiOptions?
        local captured_options = nil

        ---@diagnostic disable-next-line: duplicate-set-field
        core_helpers.get_nearest_project_root = function()
            return vim.fn.getcwd()
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        core_helpers.exists_command = function()
            return true
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        core_helpers.get_deferred_shell_command_results = function(_, _, on_complete)
            if on_complete then
                on_complete()
            end

            return { "file-one", "file-two" }
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        core_editor_setup.select_from_options = function(_, options)
            captured_options = options

            return function() end
        end

        local mapping = vim.fn.maparg("<Space>E", "n", false, true)
        assert.is_function(mapping.callback)
        mapping.callback()

        core_editor_setup.select_from_options = original_select_from_options
        core_helpers.get_nearest_project_root = original_get_project_root
        core_helpers.exists_command = original_exists_command
        core_helpers.get_deferred_shell_command_results = original_get_deferred_results

        assert.is_not_nil(captured_options)
        ---@cast captured_options _my.selection_gui.GuiOptions
        assert.is_true(captured_options.multiple_selection)
        assert.is_not_nil(captured_options.preview)
        assert.equal("top", captured_options.preview.location)
        assert.equal(200, captured_options.sort_maximum)
        assert.equal(core_editor_setup.get_file_selector_sort_score, captured_options.sort_score)
    end)

    it("<Space>E ignores ripgrep permission errors when partial results exist", function()
        local core_helpers = require("modules.utilities.core_helpers")
        local original_select_from_options = core_editor_setup.select_from_options
        local original_get_project_root = core_helpers.get_nearest_project_root
        local original_exists_command = core_helpers.exists_command
        local original_get_deferred_results = core_helpers.get_deferred_shell_command_results
        local original_notify = vim.notify
        local notifications = {}

        ---@diagnostic disable-next-line: duplicate-set-field
        core_helpers.get_nearest_project_root = function()
            return vim.fn.getcwd()
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        core_helpers.exists_command = function()
            return true
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        core_helpers.get_deferred_shell_command_results = function(_, on_fail, on_complete)
            on_fail({ code = 2, stdout = "file-one\n", stderr = "permission denied" })

            if on_complete then
                on_complete()
            end

            return { "file-one" }
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        core_editor_setup.select_from_options = function()
            return function() end
        end
        rawset(vim, "notify", function(message, level)
            table.insert(notifications, { message = message, level = level })
        end)

        local mapping = vim.fn.maparg("<Space>E", "n", false, true)
        assert.is_function(mapping.callback)
        mapping.callback()

        core_editor_setup.select_from_options = original_select_from_options
        core_helpers.get_nearest_project_root = original_get_project_root
        core_helpers.exists_command = original_exists_command
        core_helpers.get_deferred_shell_command_results = original_get_deferred_results
        rawset(vim, "notify", original_notify)

        assert.same({}, notifications)
    end)

    it("top file preview content can be scrolled", function()
        local root = vim.fn.tempname()
        local path = vim.fs.joinpath(root, "preview.lua")
        ---@type string[]
        local lines = {}

        for index = 1, 80 do
            table.insert(lines, "local value_" .. index .. " = " .. index)
        end

        vim.fn.mkdir(root, "p")
        vim.fn.writefile(lines, path)

        local refresh = core_editor_setup.select_from_options({ path }, {
            confirm = function() end,
            deserialize = function(value)
                return { display = vim.fs.basename(value), value = value }
            end,
            preview = {
                location = "top",
                min_height = 4,
                height_ratio = 0.5,
                render = function(entry)
                    local filetype = vim.filetype.match({ filename = entry.value })

                    return {
                        buftype = "nofile",
                        filetype = filetype,
                        lines = vim.fn.readfile(entry.value, "", 200),
                    }
                end,
            },
        })

        refresh()

        local preview_window = get_selector_preview_window("lua")
        local before = vim.fn.getwininfo(preview_window)[1].topline
        press("<C-d>")
        local after = vim.fn.getwininfo(preview_window)[1].topline

        vim.fn.delete(root, "rf")

        assert.is_true(after > before)
    end)

    it("<leader>gsa refreshes when deferred stash results arrive", function()
        local core_helpers = require("modules.utilities.core_helpers")
        local original_exists_command = core_helpers.exists_command
        local original_get_deferred_results = core_helpers.get_deferred_shell_command_results
        local original_get_stash_changed_line_count_async = core_editor_setup.get_stash_changed_line_count_async
        local original_get_stash_preview_lines_async = core_editor_setup.get_stash_preview_lines_async
        local stashes = {}
        local on_update

        ---@diagnostic disable-next-line: duplicate-set-field
        core_helpers.exists_command = function()
            return true
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        core_helpers.get_deferred_shell_command_results = function(_, _, callback)
            on_update = callback

            return stashes
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        core_editor_setup.get_stash_changed_line_count_async = function(_, callback)
            callback(20)
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        core_editor_setup.get_stash_preview_lines_async = function(_, callback)
            callback({ "diff --git a/file b/file" })
        end

        require("modules.features.git_keymaps")
        local mapping = vim.fn.maparg("<leader>gsa", "n", false, true)
        assert.is_function(mapping.callback)
        mapping.callback()

        table.insert(stashes, "stash@{0}: On main: important stash")
        assert.is_function(on_update)
        on_update()

        vim.wait(1000, function()
            for _, window in ipairs(vim.api.nvim_list_wins()) do
                if vim.api.nvim_win_get_config(window).relative == "editor" then
                    local buffer = vim.api.nvim_win_get_buf(window)
                    local lines = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")

                    if lines:find("important stash %(20 lines%)", 1, false) then
                        return true
                    end
                end
            end

            return false
        end)

        local found_stash_text = false

        for _, window in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_config(window).relative == "editor" then
                local buffer = vim.api.nvim_win_get_buf(window)
                local lines = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")

                if lines:find("important stash %(20 lines%)", 1, false) then
                    found_stash_text = true

                    break
                end
            end
        end

        core_helpers.exists_command = original_exists_command
        core_helpers.get_deferred_shell_command_results = original_get_deferred_results
        core_editor_setup.get_stash_changed_line_count_async = original_get_stash_changed_line_count_async
        core_editor_setup.get_stash_preview_lines_async = original_get_stash_preview_lines_async

        assert.is_true(found_stash_text)
    end)

    it("<leader>gsa does not synchronously compute stash counts or previews on open", function()
        local core_helpers = require("modules.utilities.core_helpers")
        local original_exists_command = core_helpers.exists_command
        local original_get_deferred_results = core_helpers.get_deferred_shell_command_results
        local original_get_stash_changed_line_count = core_editor_setup.get_stash_changed_line_count
        local original_get_stash_preview_lines = core_editor_setup.get_stash_preview_lines

        ---@diagnostic disable-next-line: duplicate-set-field
        core_helpers.exists_command = function()
            return true
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        core_helpers.get_deferred_shell_command_results = function()
            return { "stash@{0}: On main: important stash" }
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        core_editor_setup.get_stash_changed_line_count = function()
            error("stash line counts must not be computed synchronously", 0)
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        core_editor_setup.get_stash_preview_lines = function()
            error("stash previews must not be computed synchronously", 0)
        end

        require("modules.features.git_keymaps")
        local mapping = vim.fn.maparg("<leader>gsa", "n", false, true)
        assert.is_function(mapping.callback)
        mapping.callback()

        core_helpers.exists_command = original_exists_command
        core_helpers.get_deferred_shell_command_results = original_get_deferred_results
        core_editor_setup.get_stash_changed_line_count = original_get_stash_changed_line_count
        core_editor_setup.get_stash_preview_lines = original_get_stash_preview_lines
    end)

    it("<Space>B uses multi-select buffer selection", function()
        local core_helpers = require("modules.utilities.core_helpers")
        local original_select_from_options = core_editor_setup.select_from_options
        ---@type _my.selection_gui.GuiOptions?
        local captured_options = nil

        ---@diagnostic disable-next-line: duplicate-set-field
        core_editor_setup.select_from_options = function(_, options)
            captured_options = options

            return function() end
        end

        local mapping = vim.fn.maparg("<Space>B", "n", false, true)
        assert.is_function(mapping.callback)
        mapping.callback()

        core_editor_setup.select_from_options = original_select_from_options

        assert.is_not_nil(captured_options)
        ---@cast captured_options _my.selection_gui.GuiOptions
        assert.is_true(captured_options.multiple_selection)
        assert.equal(200, captured_options.sort_maximum)
        assert.equal(core_editor_setup.get_file_selector_sort_score, captured_options.sort_score)
        assert.is_table(core_helpers)
    end)
end)
