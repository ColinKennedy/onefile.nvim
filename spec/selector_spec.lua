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
        assert.is_table(core_helpers)
    end)
end)
