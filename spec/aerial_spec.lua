local aerial = require("modules.plugins.aerial")
local core_helpers = require("modules.utilities.core_helpers")
local fonts = require("modules.utilities.fonts")

--- Create a listed scratch source buffer.
---
---@param lines string[] Initial buffer lines.
---@return integer # The created source buffer.
local function make_source_buffer(lines)
    local buffer = vim.api.nvim_create_buf(true, false)
    local window = vim.api.nvim_get_current_win()
    local winfixbuf = vim.wo[window].winfixbuf

    if winfixbuf then
        vim.wo[window].winfixbuf = false
    end

    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)

    if winfixbuf then
        vim.wo[window].winfixbuf = true
    end

    return buffer
end

--- Get the visible lines from `buffer`.
---
---@param buffer integer The buffer to inspect.
---@return string[] # All lines in the buffer.
local function get_lines(buffer)
    return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

--- Wait until `buffer` shows exactly `lines`.
---
---@param buffer integer The buffer to inspect.
---@param lines string[] The expected lines.
local function wait_for_lines(buffer, lines)
    assert.True(vim.wait(1000, function()
        return vim.deep_equal(lines, get_lines(buffer))
    end, 20))
end

--- Get extmark highlight groups visible at a buffer position.
---
---@param buffer integer The buffer to inspect.
---@param line integer The 0-or-more line.
---@param column integer The 0-or-more column.
---@return string[] # Highlight groups at the position.
local function get_inspected_extmark_groups(buffer, line, column)
    ---@type string[]
    local groups = {}
    local inspected = vim.inspect_pos(buffer, line, column)

    for _, extmark in ipairs(inspected.extmarks or {}) do
        local group = extmark.opts and extmark.opts.hl_group

        if type(group) == "string" then
            table.insert(groups, group)
        end
    end

    return groups
end

--- Close any open aerial windows.
local function close_aerial_windows()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)

        if vim.bo[buffer].filetype == "aerial" then
            vim.api.nvim_win_close(window, true)
        end
    end
end

--- Find the first visible aerial window.
---
---@return integer? # The aerial window, if visible.
local function find_aerial_window()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)

        if vim.bo[buffer].filetype == "aerial" then
            return window
        end
    end

    return nil
end

describe("modules.plugins.aerial", function()
    local original_columns
    local original_nerdfont_allowed

    before_each(function()
        original_columns = vim.o.columns
        original_nerdfont_allowed = core_helpers.IS_NERDFONT_ALLOWED
        vim.o.columns = 120
        core_helpers.IS_NERDFONT_ALLOWED = false
    end)

    after_each(function()
        close_aerial_windows()
        vim.o.columns = original_columns
        core_helpers.IS_NERDFONT_ALLOWED = original_nerdfont_allowed
        vim.wo.winfixbuf = false
        vim.cmd.enew({ bang = true })
    end)

    it("maps literal space SS with a description", function()
        local mapping = vim.fn.maparg("<Space>SS", "n", false, true)

        assert.equal("Toggle the current buffer outline sidebar.", mapping.desc)
    end)

    it("builds indentation fallback symbols from first lines of indentation blocks", function()
        local buffer = make_source_buffer({
            "class Widget1:",
            "    def __init__(self):",
            "        body",
            "    more body",
            "",
            "class SomeClass:",
            "    def do_some_method(self):",
            "        def inner_function():",
            "            pass",
        })
        local symbols = aerial.get_indentation_symbols(buffer)

        assert.equal("class Widget1:", symbols[1].name)
        assert.equal("def __init__(self):", symbols[1].children[1].name)
        assert.equal("body", symbols[1].children[1].children[1].name)
        assert.equal("class SomeClass:", symbols[2].name)
        assert.equal("def do_some_method(self):", symbols[2].children[1].name)
        assert.equal("def inner_function():", symbols[2].children[1].children[1].name)
    end)

    it("ignores comment lines when building indentation fallback symbols", function()
        local buffer = make_source_buffer({
            "   -- Some comment",
            "   function foo()",
            "   end",
        })

        vim.bo[buffer].commentstring = "-- %s"

        local symbols = aerial.get_indentation_symbols(buffer)

        assert.equal("function foo()", symbols[1].name)
        assert.equal(1, #symbols)
    end)

    it("builds useful Python fallback symbols from definitions instead of decorators or continuations", function()
        local buffer = make_source_buffer({
            "# Some comments",
            "@another.line(",
            "    args = 10",
            ")",
            "def function(",
            "    some: str,",
            "    text: str",
            ") -> blah:",
            '    """Something."""',
        })

        vim.bo[buffer].filetype = "python"
        vim.bo[buffer].commentstring = "# %s"

        local symbols = aerial.get_indentation_symbols(buffer)

        assert.equal(1, #symbols)
        assert.equal("function", symbols[1].kind)
        assert.equal("def function", symbols[1].name)
        assert.equal(5, symbols[1].line)
    end)

    it("uses Python fallback symbols for py files even when filetype is empty", function()
        local buffer = make_source_buffer({
            "@decorator(",
            "    value",
            ")",
            "def from_extension():",
            "    pass",
        })

        vim.api.nvim_buf_set_name(buffer, vim.fn.tempname() .. ".py")
        vim.bo[buffer].filetype = ""
        vim.bo[buffer].commentstring = "# %s"

        local symbols = aerial.get_indentation_symbols(buffer)

        assert.equal(1, #symbols)
        assert.equal("def from_extension", symbols[1].name)
        assert.equal(4, symbols[1].line)
    end)

    it("prefers obvious function definitions in unknown files before raw indentation", function()
        local buffer = make_source_buffer({
            "# Some comments",
            "@another.line(",
            "    args = 10",
            ")",
            "def get_something(",
            "    some: str,",
            "    text: str",
            ") -> blah:",
            '    """Something."""',
        })

        vim.api.nvim_buf_set_name(buffer, "/tmp/foo")
        vim.bo[buffer].filetype = ""
        vim.bo[buffer].commentstring = "# %s"

        local symbols = aerial.get_indentation_symbols(buffer)

        assert.equal("def get_something", symbols[1].name)
        assert.equal(5, symbols[1].line)
    end)

    it("builds useful Lua fallback symbols from function definitions", function()
        local buffer = make_source_buffer({
            "local value = call(",
            "    thing",
            ")",
            "local function alpha()",
            "end",
            "function M.beta(value)",
            "end",
        })

        vim.bo[buffer].filetype = "lua"
        vim.bo[buffer].commentstring = "-- %s"

        local symbols = aerial.get_indentation_symbols(buffer)

        assert.equal(2, #symbols)
        assert.equal("function", symbols[1].kind)
        assert.equal("local function alpha", symbols[1].name)
        assert.equal(4, symbols[1].line)
        assert.equal("function M.beta", symbols[2].name)
    end)

    it("builds useful C++ fallback symbols from class and function definitions", function()
        local buffer = make_source_buffer({
            "if (ready) {",
            "    call();",
            "}",
            "class Widget final {",
            "public:",
            "    void draw(",
            "        int width",
            "    );",
            "};",
            "std::string make_name(const Widget& widget) {",
            "    return widget.name();",
            "}",
        })

        vim.bo[buffer].filetype = "cpp"
        vim.bo[buffer].commentstring = "// %s"

        local symbols = aerial.get_indentation_symbols(buffer)

        assert.equal(2, #symbols)
        assert.equal("class", symbols[1].kind)
        assert.equal("class Widget", symbols[1].name)
        assert.equal("function", symbols[2].kind)
        assert.equal("make_name", symbols[2].name)
    end)

    it("renders class and function rows with CC and FF prefixes", function()
        local symbols = aerial.nest_symbols({
            {
                children = {},
                column = 0,
                end_line = 5,
                highlights = {},
                key = "class\t1\tWidget",
                kind = "class",
                level = 0,
                line = 1,
                name = "Widget",
            },
            {
                children = {},
                column = 4,
                end_line = 4,
                highlights = {},
                key = "function\t2\t__init__",
                kind = "function",
                level = 0,
                line = 2,
                name = "__init__",
            },
        })
        local rows = aerial.get_rows(symbols, {})

        assert.equal("  CC Widget", rows[1].text)
        assert.equal("    FF __init__", rows[2].text)
    end)

    it("uses Nerd Font aerial icons when they are allowed", function()
        core_helpers.IS_NERDFONT_ALLOWED = true

        assert.is_false(fonts.get_icon(fonts.Icon.aerial_class) == "CC")
        assert.is_false(fonts.get_icon(fonts.Icon.aerial_function) == "FF")
    end)

    it("opens a right sidebar and focuses the aerial buffer", function()
        local shortmess = vim.o.shortmess

        make_source_buffer({
            "class Widget1:",
            "    def __init__(self):",
        })

        aerial.toggle()

        local aerial_window = vim.api.nvim_get_current_win()
        local aerial_buffer = vim.api.nvim_get_current_buf()

        assert.equal(shortmess, vim.o.shortmess)
        assert.equal("aerial", vim.bo[aerial_buffer].filetype)
        assert.equal("nofile", vim.bo[aerial_buffer].buftype)
        assert.is_true(vim.wo[aerial_window].winfixbuf)
        assert.equal(30, vim.api.nvim_win_get_width(aerial_window))
        assert.are.same({ "  -- class Widget1:", "    -- def __init__(self):" }, get_lines(aerial_buffer))
    end)

    it("restores an aerial sidebar for a visible session source window", function()
        local source_path = vim.fn.tempname() .. ".lua"

        vim.fn.writefile({
            "local function alpha()",
            "end",
        }, source_path)
        vim.cmd("silent edit " .. vim.fn.fnameescape(source_path))

        local source_window = vim.api.nvim_get_current_win()

        vim.cmd.vsplit()
        local stale_buffer = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_name(stale_buffer, "aerial://" .. source_path)
        vim.api.nvim_win_set_buf(0, stale_buffer)
        assert.equal("", vim.bo[stale_buffer].filetype)
        vim.api.nvim_set_current_win(source_window)

        aerial.restore_session({ { source_name = source_path } })

        local aerial_window = assert(find_aerial_window())

        vim.api.nvim_set_current_win(aerial_window)
        assert.equal(source_window, aerial.get_current_source_window())
        assert.equal("aerial", vim.bo[vim.api.nvim_win_get_buf(aerial_window)].filetype)
        assert.are.same({ "  -- local function alpha()" }, get_lines(vim.api.nvim_win_get_buf(aerial_window)))

        os.remove(source_path)
    end)

    it("restores from stale aerial buffers created by mksession", function()
        local source_path = vim.fn.tempname() .. ".lua"

        vim.fn.writefile({
            "local function alpha()",
            "end",
        }, source_path)
        vim.cmd("silent edit " .. vim.fn.fnameescape(source_path))

        local source_window = vim.api.nvim_get_current_win()

        vim.cmd.vsplit()
        local stale_buffer = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_name(stale_buffer, "aerial://" .. source_path)
        vim.api.nvim_win_set_buf(0, stale_buffer)
        vim.api.nvim_set_current_win(source_window)

        local entries = aerial.get_stale_session_entries()

        assert.are.same({ { source_name = source_path } }, entries)

        aerial.restore_stale_session_windows()

        local aerial_window = assert(find_aerial_window())

        vim.api.nvim_set_current_win(aerial_window)
        assert.equal(source_window, aerial.get_current_source_window())
        assert.equal("aerial", vim.bo[vim.api.nvim_win_get_buf(aerial_window)].filetype)
        assert.are.same({ "  -- local function alpha()" }, get_lines(vim.api.nvim_win_get_buf(aerial_window)))

        os.remove(source_path)
    end)

    it("serializes aerial restore code for session sidecars", function()
        local source_path = vim.fn.tempname() .. ".lua"

        vim.fn.writefile({
            "local function alpha()",
            "end",
        }, source_path)
        vim.cmd("silent edit " .. vim.fn.fnameescape(source_path))

        aerial.toggle()

        local code = aerial.serialize_session_restore()

        assert.is_truthy(code:find('require("modules.plugins.aerial").restore_session', 1, true))
        assert.is_truthy(code:find(source_path, 1, true))

        os.remove(source_path)
    end)

    it("copies source text highlight groups into fallback aerial rows", function()
        local buffer = make_source_buffer({
            "class Widget1:",
        })
        local namespace = vim.api.nvim_create_namespace("aerial.spec.source_highlight")

        vim.api.nvim_buf_set_extmark(buffer, namespace, 0, 6, {
            end_col = 13,
            hl_group = "ErrorMsg",
        })

        aerial.toggle()

        local aerial_buffer = vim.api.nvim_get_current_buf()

        assert.is_true(vim.tbl_contains(get_inspected_extmark_groups(aerial_buffer, 0, 11), "ErrorMsg"))
    end)

    it("skips expensive source highlight copying for large fallback outlines", function()
        ---@type string[]
        local lines = {}

        for index = 1, 520 do
            table.insert(lines, string.format("line %s", index))
        end

        local buffer = make_source_buffer(lines)
        local namespace = vim.api.nvim_create_namespace("aerial.spec.large_source_highlight")

        vim.api.nvim_buf_set_extmark(buffer, namespace, 0, 0, {
            end_col = 4,
            hl_group = "ErrorMsg",
        })

        aerial.toggle()

        local aerial_buffer = vim.api.nvim_get_current_buf()

        assert.is_false(vim.tbl_contains(get_inspected_extmark_groups(aerial_buffer, 0, 5), "ErrorMsg"))
    end)

    it("jumps to a row and returns focus to the source window on enter", function()
        local source_buffer = make_source_buffer({
            "class Widget1:",
            "    def __init__(self):",
        })
        local source_window = vim.api.nvim_get_current_win()

        aerial.toggle()
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        aerial.jump_to_selected(false)

        assert.equal(source_window, vim.api.nvim_get_current_win())
        assert.equal(source_buffer, vim.api.nvim_get_current_buf())
        assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(source_window))
    end)

    it("previews a row while keeping focus in aerial", function()
        make_source_buffer({
            "class Widget1:",
            "    def __init__(self):",
        })
        local source_window = vim.api.nvim_get_current_win()

        aerial.toggle()
        local aerial_window = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_cursor(aerial_window, { 2, 0 })
        aerial.jump_to_selected(true)

        assert.equal(aerial_window, vim.api.nvim_get_current_win())
        assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(source_window))
    end)

    it("uses a buffer-local control-l fallback for previewing from aerial", function()
        make_source_buffer({
            "class Widget1:",
            "    def __init__(self):",
        })

        aerial.toggle()

        local mapping = vim.fn.maparg("<C-l>", "n", false, true)

        assert.equal("Preview the selected outline item.", mapping.desc)
        assert.equal(1, mapping.buffer)
    end)

    it("does not map control-enter variants in aerial buffers", function()
        make_source_buffer({
            "class Widget1:",
            "    def __init__(self):",
        })

        aerial.toggle()

        assert.equal("", vim.fn.maparg("<C-CR>", "n"))
        assert.equal("", vim.fn.maparg("<C-Enter>", "n"))
    end)

    it("collapses and recursively expands selected rows", function()
        make_source_buffer({
            "class Widget1:",
            "    def __init__(self):",
            "        body",
        })

        aerial.toggle()
        local aerial_buffer = vim.api.nvim_get_current_buf()

        aerial.collapse_selected()

        assert.are.same({ "> -- class Widget1:" }, get_lines(aerial_buffer))

        aerial.expand_selected()

        assert.are.same({
            "  -- class Widget1:",
            "    -- def __init__(self):",
            "      -- body",
        }, get_lines(aerial_buffer))
    end)

    it("keeps the aerial cursor in place when collapsing or expanding", function()
        make_source_buffer({
            "class Widget1:",
            "    def __init__(self):",
            "        body",
            "class SomeClass:",
        })

        aerial.toggle()
        local aerial_window = vim.api.nvim_get_current_win()

        vim.api.nvim_win_set_cursor(aerial_window, { 1, 0 })
        aerial.collapse_selected()

        assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(aerial_window))

        aerial.expand_selected()

        assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(aerial_window))
    end)

    it("updates the aerial buffer after source text edits", function()
        local source_buffer = make_source_buffer({
            "class Widget1:",
            "    def __init__(self):",
        })
        local source_window = vim.api.nvim_get_current_win()

        aerial.toggle()
        local aerial_buffer = vim.api.nvim_get_current_buf()
        vim.api.nvim_set_current_win(source_window)
        vim.api.nvim_buf_set_lines(source_buffer, 2, 2, false, { "", "class SomeClass:" })
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = source_buffer })

        wait_for_lines(aerial_buffer, {
            "  -- class Widget1:",
            "    -- def __init__(self):",
            "  -- class SomeClass:",
        })
    end)

    it("debounces updates from unsaved source text edits", function()
        local source_buffer = make_source_buffer({
            "class Widget1:",
        })
        local source_window = vim.api.nvim_get_current_win()

        aerial.toggle()
        local aerial_buffer = vim.api.nvim_get_current_buf()
        vim.api.nvim_set_current_win(source_window)
        vim.api.nvim_buf_set_lines(source_buffer, 1, 1, false, { "    def unsaved_method(self):" })
        vim.api.nvim_exec_autocmds("TextChangedI", { buffer = source_buffer })

        assert.True(vim.bo[source_buffer].modified)
        wait_for_lines(aerial_buffer, {
            "  -- class Widget1:",
            "    -- def unsaved_method(self):",
        })
    end)

    it("follows the original source window when it switches buffers", function()
        make_source_buffer({
            "class Widget1:",
            "    def __init__(self):",
        })
        local source_window = vim.api.nvim_get_current_win()
        local second_buffer = vim.api.nvim_create_buf(true, false)

        vim.api.nvim_buf_set_lines(second_buffer, 0, -1, false, {
            "class Second:",
            "    def method(self):",
        })

        aerial.toggle()
        local aerial_buffer = vim.api.nvim_get_current_buf()
        vim.api.nvim_set_current_win(source_window)
        vim.api.nvim_win_set_buf(source_window, second_buffer)
        vim.api.nvim_exec_autocmds("BufEnter", { buffer = second_buffer })

        assert.are.same({
            "  -- class Second:",
            "    -- def method(self):",
        }, get_lines(aerial_buffer))
    end)

    it("refreshes edits from the buffer followed after a source-window buffer switch", function()
        make_source_buffer({
            "class Widget1:",
        })
        local source_window = vim.api.nvim_get_current_win()
        local second_buffer = vim.api.nvim_create_buf(true, false)

        vim.api.nvim_buf_set_lines(second_buffer, 0, -1, false, {
            "class Second:",
        })

        aerial.toggle()
        local aerial_buffer = vim.api.nvim_get_current_buf()
        vim.api.nvim_set_current_win(source_window)
        vim.api.nvim_win_set_buf(source_window, second_buffer)
        vim.api.nvim_exec_autocmds("BufEnter", { buffer = second_buffer })
        vim.api.nvim_buf_set_lines(second_buffer, 1, 1, false, { "    def method(self):" })
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = second_buffer })

        wait_for_lines(aerial_buffer, {
            "  -- class Second:",
            "    -- def method(self):",
        })
    end)

    it("does not treat floating selector windows as aerial source windows", function()
        local source_buffer = make_source_buffer({
            "class Widget1:",
            "    def __init__(self):",
        })
        local source_window = vim.api.nvim_get_current_win()

        aerial.toggle()
        local aerial_window = vim.api.nvim_get_current_win()
        local floating_window = vim.api.nvim_open_win(source_buffer, true, {
            col = 1,
            height = 2,
            relative = "editor",
            row = 1,
            style = "minimal",
            width = 20,
        })

        vim.api.nvim_exec_autocmds("WinEnter", {})
        vim.api.nvim_set_current_win(aerial_window)

        assert.equal(source_window, aerial.get_current_source_window())

        vim.api.nvim_win_close(floating_window, true)
    end)

    it("opens SpaceE from aerial against the original source window", function()
        local core_editor_setup = require("modules.features.core_editor_setup")
        local original_select_from_options = core_editor_setup.select_from_options
        local original_exists_command = core_helpers.exists_command
        local original_get_deferred_results = core_helpers.get_deferred_shell_command_results
        local original_get_project_root = core_helpers.get_nearest_project_root
        local root = vim.fn.tempname()
        local captured_window
        local captured_root_buffer

        vim.fn.mkdir(root, "p")
        local source_buffer = make_source_buffer({
            "class Widget1:",
            "    def __init__(self):",
        })
        local source_window = vim.api.nvim_get_current_win()
        aerial.toggle()
        local aerial_buffer = vim.api.nvim_get_current_buf()

        ---@diagnostic disable-next-line: duplicate-set-field
        core_helpers.get_nearest_project_root = function(buffer)
            captured_root_buffer = buffer

            return root
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

            return { root .. "/alpha.txt", root .. "/beta.txt" }
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        core_editor_setup.select_from_options = function()
            captured_window = vim.api.nvim_get_current_win()

            return function() end
        end

        core_editor_setup.select_file_from_project_root()

        core_editor_setup.select_from_options = original_select_from_options
        core_helpers.exists_command = original_exists_command
        core_helpers.get_deferred_shell_command_results = original_get_deferred_results
        core_helpers.get_nearest_project_root = original_get_project_root

        assert.equal(source_buffer, captured_root_buffer)
        assert.equal(source_window, captured_window)
        assert.equal(source_window, vim.api.nvim_get_current_win())
        assert.equal("aerial", vim.bo[aerial_buffer].filetype)
        assert.are.same({
            "  -- class Widget1:",
            "    -- def __init__(self):",
        }, get_lines(aerial_buffer))
    end)

    it("updates the highlighted aerial row as the source cursor moves", function()
        make_source_buffer({
            "class Widget1:",
            "    def __init__(self):",
            "",
            "class SomeClass:",
        })
        local source_window = vim.api.nvim_get_current_win()

        aerial.toggle()
        local aerial_window = vim.api.nvim_get_current_win()
        vim.api.nvim_set_current_win(source_window)
        vim.api.nvim_win_set_cursor(source_window, { 4, 0 })
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf() })

        assert.are.same({ 3, 0 }, vim.api.nvim_win_get_cursor(aerial_window))
    end)
end)
