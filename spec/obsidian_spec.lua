local obsidian = require("modules.plugins.obsidian")._P

--- Write exact lines to `path`.
---
---@param path string The file path to write.
---@param lines string[] The file lines.
local function write_lines(path, lines)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(lines, path)
end

--- Create an Obsidian-style markdown note.
---
---@param path string The markdown path to write.
---@param aliases string[]? Aliases to write, or nil to omit the aliases key.
---@param body string[]? Extra body lines after frontmatter.
local function write_note(path, aliases, body)
    ---@type string[]
    local lines = {
        "---",
        "id: test",
    }

    if aliases then
        if vim.tbl_isempty(aliases) then
            table.insert(lines, "aliases: []")
        else
            table.insert(lines, "aliases:")

            for _, alias in ipairs(aliases) do
                table.insert(lines, "  - " .. alias)
            end
        end
    end

    vim.list_extend(lines, {
        "tags: []",
        "---",
    })
    vim.list_extend(lines, body or {})

    write_lines(path, lines)
end

--- Create an Obsidian-style markdown note that declares tags.
---
---@param path string The markdown path to write.
---@param aliases string[] Aliases to write.
---@param tags string[] Frontmatter tags to write.
local function write_tagged_note(path, aliases, tags)
    ---@type string[]
    local lines = {
        "---",
        "id: test",
        "aliases:",
    }

    for _, alias in ipairs(aliases) do
        table.insert(lines, "  - " .. alias)
    end

    table.insert(lines, "tags:")

    for _, tag in ipairs(tags) do
        table.insert(lines, "  - " .. tag)
    end

    table.insert(lines, "---")

    write_lines(path, lines)
end

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

--- Get every visible, selectable row of the selector list window.
---
---@return string[] # Each rendered row, with trailing blank padding removed.
local function get_selector_rows()
    local buffer = vim.api.nvim_win_get_buf(get_selector_list_window())
    ---@type string[]
    local output = {}

    for _, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
        if line ~= "" then
            table.insert(output, line)
        end
    end

    return output
end

--- Press insert-mode keys in the selector prompt.
---
---@param keys string The keys to press.
local function press(keys)
    local mapping = vim.fn.maparg(keys, "i", false, true)

    assert.is_function(mapping.callback)
    mapping.callback()
end

--- Press normal-mode keys in the selector prompt and let scheduled work finish.
---
---@param keys string The keys to press.
local function press_normal(keys)
    local mapping = vim.fn.maparg(keys, "n", false, true)

    assert.is_function(mapping.callback)
    mapping.callback()
    vim.wait(10)
end

--- Close all floating windows.
local function close_floating_windows()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(window).relative ~= "" then
            vim.api.nvim_win_close(window, true)
        end
    end
end

--- Get a normal-mode buffer-local mapping, if one exists.
---
---@param buffer integer The buffer to inspect.
---@param lhs string The left-hand side to find.
---@return vim.api.keyset.get_keymap?
local function get_buffer_mapping(buffer, lhs)
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buffer, "n")) do
        if mapping.lhs == lhs then
            return mapping
        end
    end

    return nil
end

describe("modules.plugins.obsidian", function()
    ---@type string
    local original_root

    before_each(function()
        original_root = obsidian.get_vaults_root_path()
    end)

    after_each(function()
        obsidian.set_vaults_root_for_tests(original_root)
        vim.cmd("silent! bwipeout!")
    end)

    it("gets aliases from the shared frontmatter iterator", function()
        local root = vim.fn.tempname()
        local note = vim.fs.joinpath(root, "workspace", "note.md")

        write_note(note, { "foo bar", "Foo Bar" })

        assert.same({ "foo bar", "Foo Bar" }, obsidian.get_aliases(note))
        vim.fn.delete(root, "rf")
    end)

    it("stops alias parsing at the end of top frontmatter", function()
        local root = vim.fn.tempname()
        local note = vim.fs.joinpath(root, "workspace", "note.md")

        write_note(note, { "frontmatter alias" }, {
            "aliases:",
            "  - body alias",
        })

        assert.same({ "frontmatter alias" }, obsidian.get_aliases(note))
        vim.fn.delete(root, "rf")
    end)

    it("returns no aliases for empty or missing aliases", function()
        local root = vim.fn.tempname()
        local empty = vim.fs.joinpath(root, "workspace", "empty.md")
        local missing = vim.fs.joinpath(root, "workspace", "missing.md")

        write_note(empty, {})
        write_note(missing, nil)

        assert.same({}, obsidian.get_aliases(empty))
        assert.same({}, obsidian.get_aliases(missing))
        vim.fn.delete(root, "rf")
    end)

    it("matches aliases case-insensitively", function()
        assert.True(obsidian.is_alias_match("Foo Bar", "foo bar"))
    end)

    it("ranks alias selector matches by fuzzy closeness", function()
        ---@type _my.selector_gui.entry.Selection
        local close = {
            display = "The environment was disclosing",
            score = 1,
            value = "close.md",
        }
        ---@type _my.selector_gui.entry.Selection
        local weak = {
            display = "Every nation values clear local order",
            score = 1,
            value = "weak.md",
        }

        assert.True(
            obsidian.get_alias_selector_sort_score(close, "envclo")
                > obsidian.get_alias_selector_sort_score(weak, "envclo")
        )
    end)

    it("rewards shorthand chunks inside alias words", function()
        assert.True(
            obsidian.get_alias_chunk_match_bonus("envclo", "The environment was disclosing")
                > obsidian.get_alias_chunk_match_bonus("envclo", "Every nation values clear local order")
        )
    end)

    it("uses fuzzy sorting for the aliases selector", function()
        local root = vim.fn.tempname()
        local note = vim.fs.joinpath(root, "workspace", "note.md")
        local core_editor_setup = require("modules.features.core_editor_setup")
        local original_select_from_options = core_editor_setup.select_from_options
        ---@type _my.selection_gui.GuiOptions
        local captured_options

        write_note(note, { "The environment was disclosing" })
        obsidian.set_vaults_root_for_tests(root)

        ---@diagnostic disable-next-line: duplicate-set-field
        core_editor_setup.select_from_options = function(_, options)
            captured_options = options
        end

        local ok, error_message = pcall(obsidian.search_notes_by_aliases)
        core_editor_setup.select_from_options = original_select_from_options

        if not ok then
            error(error_message, 0)
        end

        assert.equal(obsidian.get_alias_selector_sort_score, captured_options.sort_score)
        assert.equal(1000, captured_options.sort_maximum)
        vim.fn.delete(root, "rf")
    end)

    it("finds aliases recursively within the current workspace only", function()
        local root = vim.fn.tempname()
        local first = vim.fs.joinpath(root, "foo", "nested", "a.md")
        local other_workspace = vim.fs.joinpath(root, "thing", "b.md")

        write_note(first, { "Foo Bar" })
        write_note(other_workspace, { "foo bar" })
        obsidian.set_vaults_root_for_tests(root)

        assert.equal(first, obsidian.find_note_by_alias(vim.fs.joinpath(root, "foo"), "foo bar"))
        vim.fn.delete(root, "rf")
    end)

    it("resolves the workspace from the first directory under the vault root", function()
        local root = vim.fn.tempname()
        local note = vim.fs.joinpath(root, "foo", "nested", "note.md")

        obsidian.set_vaults_root_for_tests(root)

        assert.equal(vim.fs.joinpath(root, "foo"), obsidian.get_workspace_root_for_path(note))
        vim.fn.delete(root, "rf")
    end)

    it("extracts the wikilink target under the cursor", function()
        local buffer = vim.api.nvim_create_buf(false, true)

        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "prefix [[Some more text - anything 123]] suffix" })

        assert.equal("Some more text - anything 123", obsidian.get_wikilink_target_at_cursor(buffer, 1, 15))
        vim.api.nvim_buf_delete(buffer, { force = true })
    end)

    it("adds gd only for markdown buffers inside a vault workspace", function()
        local root = vim.fn.tempname()
        local inside = vim.fs.joinpath(root, "foo", "inside.md")
        local outside = vim.fs.joinpath(root .. "-outside", "outside.md")

        write_note(inside, {})
        write_note(outside, {})
        root = vim.uv.fs_realpath(root) or root
        obsidian.set_vaults_root_for_tests(root)

        vim.cmd("silent edit " .. vim.fn.fnameescape(inside))
        vim.bo.filetype = "markdown"
        obsidian.setup_buffer_keymaps(0)
        assert.is_truthy(get_buffer_mapping(0, "gd"))

        vim.cmd("silent edit " .. vim.fn.fnameescape(outside))
        vim.bo.filetype = "markdown"
        obsidian.setup_buffer_keymaps(0)
        assert.is_nil(get_buffer_mapping(0, "gd"))

        vim.fn.delete(root, "rf")
        vim.fn.delete(root .. "-outside", "rf")
    end)

    it("reads tags from frontmatter and ignores empty tag lists", function()
        local root = vim.fn.tempname()
        local tagged = vim.fs.joinpath(root, "workspace", "tagged.md")
        local untagged = vim.fs.joinpath(root, "workspace", "untagged.md")

        write_tagged_note(tagged, { "Tagged" }, { "food/protein", '"#cuisine/french"' })
        write_note(untagged, { "Untagged" })

        assert.same({ "food/protein", "cuisine/french" }, obsidian.get_tags(tagged))
        assert.same({}, obsidian.get_tags(untagged))
        vim.fn.delete(root, "rf")
    end)

    it("expands a tag into itself and all of its parents", function()
        assert.same({ "a", "a/b", "a/b/c" }, obsidian.get_tag_ancestors("a/b/c"))
        assert.same({ "a" }, obsidian.get_tag_ancestors("a"))
    end)

    it("matches child tags but not tags that merely share a prefix", function()
        assert.True(obsidian.is_tag_match("foo/bar", "foo/bar"))
        assert.True(obsidian.is_tag_match("foo/bar/fizz", "foo/bar"))
        assert.False(obsidian.is_tag_match("foo/barbaz", "foo/bar"))
        assert.False(obsidian.is_tag_match("foo", "foo/bar"))
    end)

    it("counts each note once per tag, parent tags included", function()
        ---@type modules.plugins.obsidian.TaggedNote[]
        local notes = {
            { display = "First", path = "first.md", tags = { "foo/bar/fizz", "foo/bar" } },
            { display = "Second", path = "second.md", tags = { "foo/other" } },
            { display = "Third", path = "third.md", tags = { "unrelated" } },
        }

        assert.same({
            { count = 2, tag = "foo" },
            { count = 1, tag = "foo/bar" },
            { count = 1, tag = "foo/bar/fizz" },
            { count = 1, tag = "foo/other" },
            { count = 1, tag = "unrelated" },
        }, obsidian.get_tag_entries(notes))
    end)

    it("finds notes for any selected tag, including child tags", function()
        ---@type modules.plugins.obsidian.TaggedNote[]
        local notes = {
            { display = "First", path = "first.md", tags = { "foo/bar/fizz" } },
            { display = "Second", path = "second.md", tags = { "unrelated" } },
            { display = "Third", path = "third.md", tags = { "other" } },
        }

        local matches = obsidian.get_notes_matching_tags(notes, { "foo/bar", "other" })

        assert.same(
            { "first.md", "third.md" },
            vim.tbl_map(function(note)
                return note.path
            end, matches)
        )
    end)

    it("scans every vault for tagged notes and falls back to the file name", function()
        local root = vim.fn.tempname()
        local aliased = vim.fs.joinpath(root, "foo", "aliased.md")
        local anonymous = vim.fs.joinpath(root, "bar", "anonymous.md")
        local untagged = vim.fs.joinpath(root, "foo", "untagged.md")

        write_tagged_note(aliased, { "Some Alias" }, { "foo/bar" })
        write_tagged_note(anonymous, {}, { "foo" })
        write_note(untagged, { "Untagged" })
        obsidian.set_vaults_root_for_tests(root)

        assert.same({
            { display = "anonymous", path = anonymous, tags = { "foo" } },
            { display = "Some Alias", path = aliased, tags = { "foo/bar" } },
        }, obsidian.get_tagged_notes())
        vim.fn.delete(root, "rf")
    end)

    it("opens a note selector once tags are confirmed", function()
        local root = vim.fn.tempname()
        local note = vim.fs.joinpath(root, "workspace", "note.md")
        local core_editor_setup = require("modules.features.core_editor_setup")
        local original_select_from_options = core_editor_setup.select_from_options
        ---@type _my.selector_gui.entry.Deserialized[][]
        local captured_values = {}
        ---@type _my.selection_gui.GuiOptions[]
        local captured_options = {}

        write_tagged_note(note, { "Some Alias" }, { "foo/bar/fizz" })
        obsidian.set_vaults_root_for_tests(root)

        ---@diagnostic disable-next-line: duplicate-set-field
        core_editor_setup.select_from_options = function(values, options)
            table.insert(captured_values, values)
            table.insert(captured_options, options)

            return function() end
        end

        local ok, error_message = pcall(function()
            obsidian.search_notes_by_tags()
            captured_options[1].confirm({ { display = "foo/bar (1)", score = 1, value = "foo/bar" } })
        end)

        core_editor_setup.select_from_options = original_select_from_options

        if not ok then
            error(error_message, 0)
        end

        assert.True(captured_options[1].multiple_selection)
        assert.same({
            { display = "foo (1)", value = "foo" },
            { display = "foo/bar (1)", value = "foo/bar" },
            { display = "foo/bar/fizz (1)", value = "foo/bar/fizz" },
        }, captured_values[1])

        assert.True(captured_options[2].multiple_selection)
        assert.same({ { display = "Some Alias", value = note } }, captured_values[2])
        vim.fn.delete(root, "rf")
    end)

    it("opens every note that was selected from a tag search", function()
        local root = vim.fn.tempname()
        local first = vim.fs.joinpath(root, "workspace", "first.md")
        local second = vim.fs.joinpath(root, "workspace", "second.md")
        local core_editor_setup = require("modules.features.core_editor_setup")
        local original_select_from_options = core_editor_setup.select_from_options
        ---@type _my.selection_gui.GuiOptions
        local captured_options

        write_tagged_note(first, { "First" }, { "foo" })
        write_tagged_note(second, { "Second" }, { "foo/bar" })
        root = vim.uv.fs_realpath(root) or root
        second = vim.uv.fs_realpath(second) or second
        obsidian.set_vaults_root_for_tests(root)

        ---@diagnostic disable-next-line: duplicate-set-field
        core_editor_setup.select_from_options = function(_, options)
            captured_options = options

            return function() end
        end

        local ok, error_message = pcall(function()
            obsidian.select_notes_from_tags(obsidian.get_tagged_notes(), { "foo" }, vim.api.nvim_get_current_win())
        end)

        core_editor_setup.select_from_options = original_select_from_options

        if not ok then
            error(error_message, 0)
        end

        -- NOTE: `F` keeps `:edit` from printing note file information during the test.
        local original_shortmess = vim.o.shortmess
        vim.opt.shortmess:append("F")
        captured_options.confirm({ { display = "Second", score = 1, value = second } })
        vim.o.shortmess = original_shortmess

        assert.equal(second, vim.api.nvim_buf_get_name(0))
        vim.fn.delete(root, "rf")
    end)

    it("fuzzy-ranks tag rows but keeps an empty prompt in its original order", function()
        local ranker = obsidian.get_stable_alias_sort_score({ "big_food", "food", "food/protein" })
        ---@type _my.selector_gui.entry.Selection
        local first = { display = "big_food (1)", score = 1, value = "big_food" }
        ---@type _my.selector_gui.entry.Selection
        local second = { display = "food (2)", score = 1, value = "food" }

        assert.True(ranker(first, "") > ranker(second, ""))
        assert.equal(obsidian.get_alias_selector_sort_score(second, "food"), ranker(second, "food"))
        assert.True(ranker(second, "food") > ranker(first, "food"))
    end)

    it("walks the tag page and then the note page, end-to-end", function()
        local root = vim.fn.tempname()
        local child = vim.fs.joinpath(root, "workspace", "child.md")
        local parent = vim.fs.joinpath(root, "workspace", "parent.md")
        local unrelated = vim.fs.joinpath(root, "workspace", "unrelated.md")
        local original_lines = vim.o.lines
        local original_columns = vim.o.columns
        local original_showmode = vim.o.showmode
        -- NOTE: `F` keeps `:edit` from printing note file information during the test.
        local original_shortmess = vim.o.shortmess

        vim.o.lines = 24
        vim.o.columns = 80
        vim.o.showmode = false
        vim.opt.shortmess:append("F")

        write_tagged_note(child, { "Child Note" }, { "foo/bar/fizz" })
        write_tagged_note(parent, { "Parent Note" }, { "foo/bar" })
        write_tagged_note(unrelated, { "Unrelated Note" }, { "other" })
        root = vim.uv.fs_realpath(root) or root
        parent = vim.uv.fs_realpath(parent) or parent
        obsidian.set_vaults_root_for_tests(root)

        local ok, error_message = pcall(function()
            obsidian.search_notes_by_tags()

            assert.same({
                ">  foo (2)",
                "   foo/bar (2)",
                "   foo/bar/fizz (1)",
                "   other (1)",
            }, get_selector_rows())

            -- NOTE: Toggle `"foo/bar"`, which must also match the `"foo/bar/fizz"` note.
            press("<C-n>")
            press("<Tab>")
            press_normal("<CR>")

            assert.same({ ">  Child Note", "   Parent Note" }, get_selector_rows())

            press("<C-n>")
            press("<Tab>")
            press_normal("<CR>")
        end)

        pcall(vim.cmd.stopinsert)
        close_floating_windows()
        vim.o.lines = original_lines
        vim.o.columns = original_columns
        vim.o.showmode = original_showmode
        vim.o.shortmess = original_shortmess

        if not ok then
            error(error_message, 0)
        end

        assert.equal(parent, vim.api.nvim_buf_get_name(0))

        -- NOTE: Let asynchronous git-gutter work finish before the note buffer is wiped.
        vim.wait(200)
        vim.fn.delete(root, "rf")
    end)

    it("opens the first deterministic matching note", function()
        local root = vim.fn.tempname()
        local current = vim.fs.joinpath(root, "foo", "current.md")
        local first = vim.fs.joinpath(root, "foo", "a-first.md")
        local second = vim.fs.joinpath(root, "foo", "z-second.md")

        write_note(current, {}, { "[[foo bar]]" })
        write_note(second, { "foo bar" })
        write_note(first, { "Foo Bar" })
        root = vim.uv.fs_realpath(root) or root
        current = vim.uv.fs_realpath(current) or current
        first = vim.uv.fs_realpath(first) or first
        obsidian.set_vaults_root_for_tests(root)

        vim.cmd("silent edit " .. vim.fn.fnameescape(current))
        vim.api.nvim_win_set_cursor(0, { 6, 3 })
        obsidian.go_to_definition()

        assert.equal(first, vim.api.nvim_buf_get_name(0))
        vim.fn.delete(root, "rf")
    end)
end)
