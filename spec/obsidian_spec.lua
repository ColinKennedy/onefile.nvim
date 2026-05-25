local obsidian = require("modules.plugins.obsidian")

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
        local close = {
            display = "The environment was disclosing",
            score = 1,
            value = "close.md",
        }
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

    it("opens the first deterministic matching note", function()
        local root = vim.fn.tempname()
        local current = vim.fs.joinpath(root, "foo", "current.md")
        local first = vim.fs.joinpath(root, "foo", "a-first.md")
        local second = vim.fs.joinpath(root, "foo", "z-second.md")

        write_note(current, {}, { "[[foo bar]]" })
        write_note(second, { "foo bar" })
        write_note(first, { "Foo Bar" })
        obsidian.set_vaults_root_for_tests(root)

        vim.cmd("silent edit " .. vim.fn.fnameescape(current))
        vim.api.nvim_win_set_cursor(0, { 6, 3 })
        obsidian.go_to_definition()

        assert.equal(first, vim.api.nvim_buf_get_name(0))
        vim.fn.delete(root, "rf")
    end)
end)
