--- Basic [obsidian](https://obsidian.md) support.
---
--- Instead of supporting
--- [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim), which is
--- a huge I just port the commands that I want to keep. And I only need a few commands.

---@class _my.obsidian
local M = {}

---@class _my.obsidian._P
local _P = {}

-- NOTE: obsidian.nvim separates the top-level note data from the rest of the
-- document using these characters.
--
local _METADATA_MARKER = "---"
-- NOTE: obsidian.nvim uses YAML and aliases is a string[] that starts with "aliases:"
local _ALIASES_KEY = "aliases"
-- NOTE: obsidian.nvim uses YAML and tags is a string[] that starts with "tags:"
local _TAGS_KEY = "tags"
-- NOTE: obsidian tags are hierarchical. e.g. `"food/protein"` is a child of `"food"`.
local _TAG_SEPARATOR = "/"
local _CURRENT_WORKSPACE = "politics"
local _ROOT = os.getenv("NEOVIM_VAULTS_DIRECTORY") or vim.fs.joinpath(vim.fn.expand("~"), "vaults")

---@class modules.plugins.obsidian.AliasEntry
---@field path string The markdown file path containing the alias.
---@field alias string The exact alias text from frontmatter.

---@class modules.plugins.obsidian.TaggedNote A note that declares one or more frontmatter tags.
---@field path string The absolute markdown file path.
---@field display string Human-friendly note text. Its first alias or, failing that, its file name.
---@field tags string[] Every tag that the note declares.

---@class modules.plugins.obsidian.TagEntry One selectable row in the tag selector.
---@field tag string The full tag text. e.g. `"food/protein"`.
---@field count integer How many notes match `tag`, including its child tags.

--- Find the YAML list item from `text`, if any.
---
---@param text string The line to query. e.g. ` - some_tag/here`.
---@return string? # The found match, if any.
---
function _P.get_list_item_text(text)
    return (string.match(text, "%s*-%s*(.*)"))
end

--- Check if a frontmatter line begins a top-level key.
---
---@param line string Some frontmatter line.
---@return boolean # If the line starts a new top-level key, return `true`.
function _P.is_metadata_key_line(line)
    local character = line:sub(1, 1)

    return character ~= "" and character ~= " "
end

--- Read YAML list values from a note's top frontmatter.
---
--- Only block-style lists are considered. e.g. a `"tags:"` line followed by
--- `"  - some_tag"` lines. An inline `"tags: []"` yields no values.
---
--- Raises:
---     If `path` cannot be read for data.
---
---@param path string An absolute path on-disk to some obsidian note to query from.
---@param keys string[] The frontmatter keys to read. e.g. `{"aliases", "tags"}`.
---@return table<string, string[]> # Each requested key and its found values.
---
function _P.get_frontmatter_lists(path, keys)
    local handler = io.open(path)

    if not handler then
        error(string.format('File "%s" could not be opened.', path), 0)
    end

    ---@type table<string, string[]>
    local output = {}
    ---@type table<string, boolean>
    local is_wanted = {}

    for _, key in ipairs(keys) do
        output[key] = {}
        is_wanted[key] = true
    end

    ---@type string?
    local current_key = nil
    local line_number = 0

    for line in handler:lines() do
        line_number = line_number + 1

        if line_number == 1 then
            if line ~= _METADATA_MARKER then
                break
            end
        elseif line == _METADATA_MARKER then
            break
        else
            local key = line:match("^([%w_%-]+):")

            if key then
                -- NOTE: An inline value such as `"tags: []"` has no list items to read.
                current_key = (is_wanted[key] and line == key .. ":") and key or nil
            elseif current_key then
                local value = _P.get_list_item_text(line)

                if value then
                    table.insert(output[current_key], value)
                elseif _P.is_metadata_key_line(line) then
                    current_key = nil
                end
            end
        end
    end

    handler:close()

    return output
end

--- Iterate aliases from a note's top YAML frontmatter.
---
--- Raises:
---     If `path` cannot be read for data.
---
---@param path string An absolute path on-disk to some obsidian note to query from.
---@return fun(): string? # A generator that yields one alias at a time.
function _P.iter_aliases(path)
    local aliases = _P.get_frontmatter_lists(path, { _ALIASES_KEY })[_ALIASES_KEY]
    local index = 0

    return function()
        index = index + 1

        return aliases[index]
    end
end

--- Find all file aliases from some obsidian.nvim note `path`.
---
--- Raises:
---     If `path` cannot be read for data.
---
---@param path string An absolute path on-disk to some obsidian note to query from.
---@return string[]  # All found aliases, if any.
---
function _P.get_aliases(path)
    ---@type string[]
    local output = {}

    for alias in _P.iter_aliases(path) do
        table.insert(output, alias)
    end

    return output
end

--- Clean raw frontmatter tag text so it can be compared and displayed.
---
---@param text string A raw tag value. e.g. `' "#food/protein" '`.
---@return string # The cleaned tag. e.g. `"food/protein"`.
---
function _P.normalize_tag(text)
    local tag = text:match("^%s*(.-)%s*$")
    tag = tag:match('^"(.*)"$') or tag:match("^'(.*)'$") or tag

    return (tag:gsub("^#", ""))
end

--- Find all tags from some obsidian.nvim note `path`.
---
--- Raises:
---     If `path` cannot be read for data.
---
---@param path string An absolute path on-disk to some obsidian note to query from.
---@return string[] # All found tags, if any.
---
function _P.get_tags(path)
    return _P.get_normalized_tags(_P.get_frontmatter_lists(path, { _TAGS_KEY })[_TAGS_KEY])
end

--- Clean every raw frontmatter tag value and drop the empty ones.
---
---@param values string[] Raw tag values, straight from a note's frontmatter.
---@return string[] # Every cleaned, non-empty tag.
---
function _P.get_normalized_tags(values)
    ---@type string[]
    local output = {}

    for _, text in ipairs(values) do
        local tag = _P.normalize_tag(text)

        if tag ~= "" then
            table.insert(output, tag)
        end
    end

    return output
end

--- Normalize a path for comparisons.
---
---@param path string Some file or directory path.
---@return string # The normalized path.
function _P.normalize_path(path)
    local absolute = vim.fn.fnamemodify(path, ":p")
    local resolved = vim.uv.fs_realpath(absolute) or absolute

    return (vim.fs.normalize(resolved):gsub("\\", "/"))
end

--- Normalize path case for comparison on Windows drive-letter paths.
---
---@param path string An already normalized path.
---@return string # A path suitable for identity and prefix comparisons.
local function _get_comparison_path(path)
    if path:match("^%a:") then
        return path:lower()
    end

    return path
end

--- Get the Obsidian workspace root for `path`, if any.
---
---@param path string A buffer path.
---@return string? # The workspace root, if `path` is inside a vault workspace.
function _P.get_workspace_root_for_path(path)
    local vault_root = _P.get_vaults_root_path()
    local normalized_root = _P.normalize_path(vault_root):gsub("/+$", "")
    local normalized_path = _P.normalize_path(path)
    local root_prefix = normalized_root .. "/"

    if _get_comparison_path(normalized_path):sub(1, #root_prefix) ~= _get_comparison_path(root_prefix) then
        return nil
    end

    local relative = normalized_path:sub(#root_prefix + 1)
    local workspace_name = relative:match("^([^/]+)/")

    if not workspace_name then
        return nil
    end

    return vim.fs.joinpath(vault_root, workspace_name)
end

--- Get the Obsidian wikilink target under the cursor.
---
---@param buffer integer The buffer to inspect.
---@param cursor_row integer The 1-based cursor row.
---@param cursor_column integer The 0-based cursor column.
---@return string? # The wikilink target under the cursor, if any.
function _P.get_wikilink_target_at_cursor(buffer, cursor_row, cursor_column)
    local line = vim.api.nvim_buf_get_lines(buffer, cursor_row - 1, cursor_row, false)[1] or ""
    local cursor = cursor_column + 1
    local start_index = 1

    while true do
        local match_start, match_end, target = line:find("%[%[([^%]]+)%]%]", start_index)

        if not match_start then
            return nil
        end

        if match_start <= cursor and cursor <= match_end then
            return target
        end

        start_index = match_end + 1
    end
end

--- Find all markdown files in `workspace_root` recursively.
---
---@param workspace_root string The workspace to scan.
---@return string[] # Sorted, normalized markdown file paths.
function _P.get_markdown_files(workspace_root)
    local paths = vim.fs.find(function(name)
        return name:lower():sub(-3) == ".md"
    end, { limit = math.huge, path = workspace_root, type = "file" })

    for index, path in ipairs(paths) do
        paths[index] = _P.normalize_path(path)
    end

    table.sort(paths)

    return paths
end

--- Compare two alias values case-insensitively.
---
---@param left string Some alias text.
---@param right string Some link target text.
---@return boolean # If both values match after lowercasing, return `true`.
function _P.is_alias_match(left, right)
    return left:lower() == right:lower()
end

--- Find the first markdown file in `workspace_root` whose frontmatter aliases match `target`.
---
---@param workspace_root string The workspace to scan.
---@param target string The wikilink target to match.
---@return string? # The matching note path, if any.
function _P.find_note_by_alias(workspace_root, target)
    for _, path in ipairs(_P.get_markdown_files(workspace_root)) do
        for alias in _P.iter_aliases(path) do
            if _P.is_alias_match(alias, target) then
                return path
            end
        end
    end

    return nil
end

--- Create a note in `workspace_root` using the standard Obsidian note template.
---
---@param workspace_root string The workspace where the note should be created.
---@param title string The note title / alias.
---@return string # The note path.
function _P.create_note_in_workspace(workspace_root, title)
    local identifier = _P.get_note_identifier(title)
    local path = vim.fs.joinpath(workspace_root, identifier .. ".md")

    if vim.fn.filereadable(path) == 1 then
        return path
    end

    local date = os.date("%Y-%m-%d")
    local time = os.date("%H:%M")

    ---@type string[]
    local lines = {
        "---",
        "id: " .. identifier,
        "date: " .. date,
        "time: " .. time,
        "aliases:",
        "  - " .. title,
        "tags: []",
        "---",
        "",
        "# " .. title,
        "",
    }

    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(lines, path)

    return path
end

--- Go to the Obsidian note whose alias matches the wikilink under the cursor.
function _P.go_to_definition()
    local buffer = vim.api.nvim_get_current_buf()
    local path = vim.api.nvim_buf_get_name(buffer)
    local workspace_root = _P.get_workspace_root_for_path(path)

    if not workspace_root then
        vim.notify("Current markdown file is not inside an Obsidian vault workspace.", vim.log.levels.WARN)

        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local target = _P.get_wikilink_target_at_cursor(buffer, cursor[1], cursor[2])

    if not target then
        vim.notify("No Obsidian wikilink found under cursor.", vim.log.levels.WARN)

        return
    end

    local note = _P.find_note_by_alias(workspace_root, target)

    if not note then
        local answer = vim.fn.confirm(string.format('Create Obsidian note "%s"?', target), "&Yes\n&No", 2)

        if answer ~= 1 then
            vim.notify("Cancelled Obsidian note creation.", vim.log.levels.INFO)

            return
        end

        note = _P.create_note_in_workspace(workspace_root, target)
    end

    vim.cmd("silent edit " .. vim.fn.fnameescape(note))
end

--- Add Obsidian-only mappings to a markdown buffer.
---
---@param buffer integer The markdown buffer to configure.
function _P.setup_buffer_keymaps(buffer)
    local path = vim.api.nvim_buf_get_name(buffer)

    if path == "" or not _P.get_workspace_root_for_path(path) then
        return
    end

    vim.keymap.set("n", "gd", _P.go_to_definition, {
        buffer = buffer,
        desc = "Go to Obsidian note by alias.",
    })
end

--- Use `title` to recommend a simplified ID for the Obsidian note.
---
---@param title string Some word or phrase to make into a note.
---@return string # The generated ID.
---
function _P.get_note_identifier(title)
    local suffix = ""

    if title ~= nil and title ~= "" then
        suffix = title
            :gsub("%s+", "-") -- spaces → hyphens
            :gsub("[^A-Za-z0-9-]", "") -- strip invalid chars
            :lower()
    else
        for _ = 1, 4 do
            suffix = suffix .. string.char(math.random(65, 90))
        end
    end

    return tostring(os.time()) .. "-" .. suffix
end

---@return string # The absolute path on-disk where all workspaces should be.
function _P.get_vaults_root_path()
    return _ROOT
end

--- Override the vault root for focused tests.
---
---@param root string The vault root to use.
function _P.set_vaults_root_for_tests(root)
    _ROOT = root
end

---@return string # The absolute path on-disk where the workspace should be.
function _P.get_workspace_path()
    return vim.fs.joinpath(_ROOT, _CURRENT_WORKSPACE)
end

--- Make a note in an Obsidian vault.
---
---@param title string Some word or phrase to identify the note.
---
function _P.create_note(title)
    local vault = _P.get_workspace_path()
    local identifier = _P.get_note_identifier(title)
    local path = vim.fs.joinpath(vault, identifier .. ".md")

    if vim.fn.filereadable(path) == 1 then
        vim.notify(string.format('Note "%s" already exists.', identifier), vim.log.levels.INFO)
        vim.cmd.edit(path)

        return
    end

    path = _P.create_note_in_workspace(vault, title)
    vim.cmd.edit(path)
end

--- Show the Obsidian workspace that notes will be created / searched / etc within.
function _P.print_current_workspace()
    vim.notify(string.format('Current Workspace: "%s"', _CURRENT_WORKSPACE), vim.log.levels.INFO)
end

--- Search all Obsidian notes across all vaults by-alias (basically by-title).
---
---@param query string The selector prompt text.
---@param candidate string The alias text to rank.
---@return number # A bonus for matching longer query chunks inside fewer words.
function _P.get_alias_chunk_match_bonus(query, candidate)
    local normalized_query = query:lower():gsub("[^%w]", "")
    local normalized_candidate = candidate:lower()

    if normalized_query == "" then
        return 0
    end

    local query_index = 1
    local bonus = 0

    for token in normalized_candidate:gmatch("[%w]+") do
        if query_index > #normalized_query then
            break
        end

        local best_length = 0

        for length = #normalized_query - query_index + 1, 1, -1 do
            local chunk = normalized_query:sub(query_index, query_index + length - 1)

            if token:find(chunk, 1, true) then
                best_length = length

                break
            end
        end

        if best_length > 0 then
            bonus = bonus + (best_length * best_length * 250)
            query_index = query_index + best_length
        end
    end

    if query_index <= #normalized_query then
        return 0
    end

    return bonus
end

--- Search all Obsidian notes across all vaults by-alias (basically by-title).
---
---@param entry _my.selector_gui.entry.Selection The alias selector entry to rank.
---@param input string The selector prompt text.
---@return number? # A larger score ranks earlier.
function _P.get_alias_selector_sort_score(entry, input)
    local display = tostring(entry.display or entry.value)
    local score = require("modules.utilities.core_helpers").get_fuzzy_match_score(input, display)

    if not score then
        return nil
    end

    return score + _P.get_alias_chunk_match_bonus(input, display)
end

--- Search all Obsidian notes across all vaults by-alias (basically by-title).
function _P.search_notes_by_aliases()
    ---@type _my.selector_gui.entry.Deserialized[]
    local found = {}

    for _, path in ipairs(_P.get_markdown_files(_ROOT)) do
        for _, alias in ipairs(_P.get_aliases(path)) do
            table.insert(found, { display = alias, value = path })
        end
    end

    local window = vim.api.nvim_get_current_win()

    require("modules.features.core_editor_setup").select_from_options(found, {
        sort_maximum = 1000,
        sort_score = _P.get_alias_selector_sort_score,
        confirm = function(entry)
            vim.api.nvim_set_current_win(window)
            vim.cmd.edit(entry.value)
        end,
    })
end

--- Get every parent tag of `tag`, plus `tag` itself.
---
--- Example:
---     `"a/b/c"` becomes `{"a", "a/b", "a/b/c"}`.
---
---@param tag string A full, possibly-hierarchical tag.
---@return string[] # Each tag, from the outermost parent to `tag`.
---
function _P.get_tag_ancestors(tag)
    ---@type string[]
    local output = {}
    ---@type string?
    local current = nil

    for _, part in ipairs(vim.split(tag, _TAG_SEPARATOR, { plain = true, trimempty = true })) do
        current = current and (current .. _TAG_SEPARATOR .. part) or part
        table.insert(output, current)
    end

    return output
end

--- Check if `tag` is `selected` or one of its children.
---
--- Tags are hierarchical so `"food"` matches a note tagged `"food/protein"`.
---
---@param tag string A tag that some note declares. e.g. `"food/protein"`.
---@param selected string The tag that the user asked for. e.g. `"food"`.
---@return boolean # If `tag` is at-or-under `selected`, return `true`.
---
function _P.is_tag_match(tag, selected)
    if tag == selected then
        return true
    end

    local prefix = selected .. _TAG_SEPARATOR

    return tag:sub(1, #prefix) == prefix
end

--- Check if any of `tags` is at-or-under any of `selected_tags`.
---
---@param tags string[] Every tag that some note declares.
---@param selected_tags string[] The tags that the user asked for.
---@return boolean # If at least one tag matches, return `true`.
---
function _P.has_tag_match(tags, selected_tags)
    for _, tag in ipairs(tags) do
        for _, selected in ipairs(selected_tags) do
            if _P.is_tag_match(tag, selected) then
                return true
            end
        end
    end

    return false
end

--- Make display text for `path` in case the note has no alias to show.
---
---@param path string An absolute path on-disk to some obsidian note.
---@return string # The note file name, without its file extension.
---
function _P.get_note_fallback_display(path)
    return (vim.fs.basename(path):gsub("%.md$", ""))
end

--- Find every note in every vault that declares at least one tag.
---
--- Raises:
---     If some note cannot be read for data.
---
---@return modules.plugins.obsidian.TaggedNote[] # Each tagged note, sorted by-path.
---
function _P.get_tagged_notes()
    ---@type modules.plugins.obsidian.TaggedNote[]
    local output = {}

    for _, path in ipairs(_P.get_markdown_files(_P.get_vaults_root_path())) do
        local frontmatter = _P.get_frontmatter_lists(path, { _ALIASES_KEY, _TAGS_KEY })
        local tags = _P.get_normalized_tags(frontmatter[_TAGS_KEY])

        if not vim.tbl_isempty(tags) then
            table.insert(output, {
                display = frontmatter[_ALIASES_KEY][1] or _P.get_note_fallback_display(path),
                path = path,
                tags = tags,
            })
        end
    end

    return output
end

--- Summarize every selectable tag in `notes`, parent tags included.
---
---@param notes modules.plugins.obsidian.TaggedNote[] Every known tagged note.
---@return modules.plugins.obsidian.TagEntry[] # Each tag and its note count, sorted by-tag.
---
function _P.get_tag_entries(notes)
    ---@type table<string, integer>
    local counts = {}

    for _, note in ipairs(notes) do
        ---@type table<string, boolean>
        local counted = {}

        for _, tag in ipairs(note.tags) do
            for _, ancestor in ipairs(_P.get_tag_ancestors(tag)) do
                if not counted[ancestor] then
                    counted[ancestor] = true
                    counts[ancestor] = (counts[ancestor] or 0) + 1
                end
            end
        end
    end

    ---@type modules.plugins.obsidian.TagEntry[]
    local output = {}

    for tag, count in pairs(counts) do
        table.insert(output, { count = count, tag = tag })
    end

    table.sort(output, function(left, right)
        return left.tag < right.tag
    end)

    return output
end

--- Find every note in `notes` that is tagged with any of `selected_tags`.
---
---@param notes modules.plugins.obsidian.TaggedNote[] Every known tagged note.
---@param selected_tags string[] The tags that the user asked for.
---@return modules.plugins.obsidian.TaggedNote[] # The matching notes, in `notes` order.
---
function _P.get_notes_matching_tags(notes, selected_tags)
    ---@type modules.plugins.obsidian.TaggedNote[]
    local output = {}

    for _, note in ipairs(notes) do
        if _P.has_tag_match(note.tags, selected_tags) then
            table.insert(output, note)
        end
    end

    return output
end

--- Fuzzy-rank selector rows but keep their original order while the prompt is empty.
---
--- Every row scores the same against an empty prompt so, without this, the
--- sort would shuffle rows that were deliberately ordered by the caller.
---
---@param values _my.selector_gui.Value[] Every selectable entry value, in display order.
---@return fun(entry: _my.selector_gui.entry.Selection, input: string): number? # The ranker.
---
function _P.get_stable_alias_sort_score(values)
    -- typer: ignore-next-line[disallowed-any]
    ---@type table<any, integer>
    local ranks = {}

    for index, value in ipairs(values) do
        ranks[value] = index
    end

    return function(entry, input)
        if input == "" then
            return -(ranks[entry.value] or (#values + 1))
        end

        return _P.get_alias_selector_sort_score(entry, input)
    end
end

--- Open the second selector page, which lists the notes that match `selected_tags`.
---
---@param notes modules.plugins.obsidian.TaggedNote[] Every known tagged note.
---@param selected_tags string[] The tags that the user chose in the first page.
---@param window integer The window to open any chosen note within.
---
function _P.select_notes_from_tags(notes, selected_tags, window)
    local matches = _P.get_notes_matching_tags(notes, selected_tags)

    if vim.tbl_isempty(matches) then
        vim.notify(
            string.format('No notes are tagged with "%s".', table.concat(selected_tags, ", ")),
            vim.log.levels.WARN
        )

        return
    end

    ---@type _my.selector_gui.entry.Deserialized[]
    local found = {}
    ---@type _my.selector_gui.Value[]
    local paths = {}

    for _, note in ipairs(matches) do
        table.insert(found, { display = note.display, value = note.path })
        table.insert(paths, note.path)
    end

    local refresh_selector = require("modules.features.core_editor_setup").select_from_options(found, {
        header = { { text = table.concat(selected_tags, ", "), highlight = "Special" } },
        multiple_selection = true,
        sort_maximum = 1000,
        sort_score = _P.get_stable_alias_sort_score(paths),
        confirm = function(entries)
            if vim.api.nvim_win_is_valid(window) then
                vim.api.nvim_set_current_win(window)
            end

            for _, entry in ipairs(entries) do
                vim.cmd.edit(entry.value)
            end
        end,
    })

    refresh_selector()
end

--- Search all Obsidian notes across all vaults by-tag.
---
--- The first page selects one or more tags. <Tab> toggles a tag and <CR>
--- confirms. If no tag was toggled, <CR> confirms whatever the cursor is on.
--- The second page selects the note(s) to open.
---
function _P.search_notes_by_tags()
    local notes = _P.get_tagged_notes()
    local tag_entries = _P.get_tag_entries(notes)

    if vim.tbl_isempty(tag_entries) then
        vim.notify(
            string.format('No tags were found in "%s" directory.', _P.get_vaults_root_path()),
            vim.log.levels.WARN
        )

        return
    end

    ---@type _my.selector_gui.entry.Deserialized[]
    local found = {}
    ---@type _my.selector_gui.Value[]
    local tags = {}

    for _, entry in ipairs(tag_entries) do
        table.insert(found, { display = string.format("%s (%d)", entry.tag, entry.count), value = entry.tag })
        table.insert(tags, entry.tag)
    end

    local window = vim.api.nvim_get_current_win()

    local refresh_selector = require("modules.features.core_editor_setup").select_from_options(found, {
        header = { { text = "Select tag(s)", highlight = "Special" } },
        multiple_selection = true,
        sort_maximum = 1000,
        sort_score = _P.get_stable_alias_sort_score(tags),
        confirm = function(entries)
            ---@type string[]
            local selected_tags = {}

            for _, entry in ipairs(entries) do
                table.insert(selected_tags, entry.value)
            end

            if vim.tbl_isempty(selected_tags) then
                return
            end

            _P.select_notes_from_tags(notes, selected_tags, window)
        end,
    })

    refresh_selector()
end

--- Change Obsidian's workspace to `name`.
---
---@param name string The workspace on-disk to point to. e.g. `"personal"`.
---
function _P.set_workspace_name(name)
    _CURRENT_WORKSPACE = name
end

--- Check if `name` is a visible workspace directory.
---
---@param vault_root string The absolute path containing workspace directories.
---@param name string The directory name to check.
---@return boolean # If `name` is a non-hidden directory, return `true`.
local function _is_visible_workspace_directory(vault_root, name)
    if name:sub(1, 1) == "." then
        return false
    end

    return vim.fn.isdirectory(vim.fs.joinpath(vault_root, name)) == 1
end

--- Select a new current Obsidian workspace in a pop-up GUI.
function _P.select_workspace()
    local vault_root = _P.get_vaults_root_path()

    ---@type string[]
    local directories = {}

    -- TODO: Make this async later
    local entries = vim.fn.readdir(vault_root)

    for _, name in ipairs(entries) do
        if _is_visible_workspace_directory(vault_root, name) then
            table.insert(directories, name)
        end
    end

    if vim.tbl_isempty(directories) then
        vim.notify(string.format('No vaults found in "%s" directory.', vault_root), vim.log.levels.WARN)

        return
    end

    table.sort(directories)

    vim.ui.select(directories, {
        prompt = "Select Obsidian workspace:",
    }, function(choice)
        if not choice then
            return
        end

        _P.set_workspace_name(choice)

        vim.notify("Obsidian workspace set to: " .. choice, vim.log.levels.INFO)
    end)
end

local _SECONDS_PER_DAY = 24 * 60 * 60

--- Get a stable timestamp for today's local date.
---
---@return integer # The current local date at noon, as a timestamp.
---
function _P.get_today_time()
    local today = os.date("*t")

    assert(type(today) == "table")

    today.hour = 12
    today.min = 0
    today.sec = 0

    return os.time(today)
end

---@param time integer A timestamp to check.
---@return boolean # If `time` is a Saturday or Sunday.
function _P.is_weekend(time)
    local weekday = os.date("*t", time).wday

    return weekday == 1 or weekday == 7
end

---@param time integer A timestamp to start from.
---@param direction integer Either `1` for next or `-1` for previous.
---@return integer # The next weekday timestamp in `direction`.
function _P.get_business_day_time(time, direction)
    local current = time

    repeat
        current = current + (_SECONDS_PER_DAY * direction)
    until not _P.is_weekend(current)

    return current
end

---@param time integer The timestamp for the daily note to open.
function _P.open_daily_note(time)
    local date = os.date("%Y-%m-%d", time)
    local path = vim.fs.joinpath(_P.get_workspace_path(), date .. ".md")

    if vim.fn.filereadable(path) ~= 1 then
        ---@type string[]
        local lines = {
            "---",
            "id: " .. date,
            "aliases: []",
            "tags:",
            "  - daily-notes",
            "---",
            "",
            "",
        }

        vim.fn.mkdir(vim.fs.dirname(path), "p")
        vim.fn.writefile(lines, path)
    end

    vim.cmd.edit(vim.fn.fnameescape(path))
    pcall(vim.cmd.stopinsert)
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
end

function _P.today()
    _P.open_daily_note(_P.get_today_time())
end

function _P.yesterday()
    _P.open_daily_note(_P.get_business_day_time(_P.get_today_time(), -1))
end

function _P.tomorrow()
    _P.open_daily_note(_P.get_business_day_time(_P.get_today_time(), 1))
end

---@type table<string, fun(): nil>
local _SUBCOMMANDS = {
    aliases = _P.search_notes_by_aliases,
    get_workspace = _P.print_current_workspace,
    set_workspace = _P.select_workspace,
    tags = _P.search_notes_by_tags,
    today = _P.today,
    tomorrow = _P.tomorrow,
    tommorrow = _P.tomorrow,
    yesterday = _P.yesterday,
}

local _SUBCOMMAND_NAMES = vim.fn.sort(vim.tbl_keys(_SUBCOMMANDS))

--- Complete the `:Obsidian` sub-command name that the user is typing.
---
---@param arglead string The partial sub-command name to complete.
---@param command_line string The whole command-line text, so far.
---@return string[] # The matching sub-command names.
---
function _P.complete_command(arglead, command_line)
    local arguments_text = command_line:gsub("^%s*Obsidian%s*", "", 1)

    if arguments_text:match("^%S+%s+") then
        return {}
    end

    if arglead == "" then
        return _SUBCOMMAND_NAMES
    end

    ---@type string[]
    local output = {}

    for _, name in ipairs(_SUBCOMMAND_NAMES) do
        if name:find(arglead, 1, true) == 1 then
            table.insert(output, name)
        end
    end

    return output
end

--- Run the `:Obsidian` sub-command that `opts` names.
---
---@param opts vim.api.keyset.create_user_command.command_args The parsed `:Obsidian` arguments.
---
function _P.run_command(opts)
    local subcommand = opts.fargs[1]
    local callback = _SUBCOMMANDS[subcommand]

    if not callback then
        vim.notify(string.format('Unknown Obsidian subcommand: "%s"', subcommand or ""), vim.log.levels.ERROR)

        return
    end

    callback()
end

vim.api.nvim_create_user_command(
    "Obsidian",
    _P.run_command,
    { complete = _P.complete_command, nargs = "*", desc = "Run an Obsidian command." }
)

vim.api.nvim_create_user_command("Note", function(opts)
    ---@param text string Some text with possible surrounding whitespace.
    ---@return string # The stripped text.
    local _strip_whitespace = function(text)
        return (text:match("^%s*(.-)%s*$"))
    end

    local title = _strip_whitespace(table.concat(opts.fargs, " "))
    _P.create_note(title)
end, { nargs = "?", desc = "Make a new Obsidian note." })

vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("my.obsidian.keymaps", { clear = true }),
    pattern = "markdown",
    desc = "Add Obsidian markdown navigation mappings.",
    callback = function(args)
        _P.setup_buffer_keymaps(args.buf)
    end,
})

--- Expose the private namespace so the specs can reach it.
---@type _my.obsidian._P
M._P = _P

return M
