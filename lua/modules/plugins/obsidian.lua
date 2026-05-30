--- Basic [obsidian](https://obsidian.md) support.
---
--- Instead of supporting
--- [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim), which is
--- a huge I just port the commands that I want to keep. And I only need a few commands.

local _P = {}

-- NOTE: obsidian.nvim separates the top-level note data from the rest of the
-- document using these characters.
--
local _METADATA_MARKER = "---"
-- NOTE: obsidian.nvim uses YAML and aliases is a string[] that starts with "aliases:"
local _ALIASES_START_MARKER = "aliases:"
local _CURRENT_WORKSPACE = "politics"
local _ROOT = os.getenv("NEOVIM_VAULTS_DIRECTORY") or vim.fs.joinpath(vim.fn.expand("~"), "vaults")

---@class modules.plugins.obsidian.AliasEntry
---@field path string The markdown file path containing the alias.
---@field alias string The exact alias text from frontmatter.

--- Find the alias from `text`, if any.
---
---@param text string The line to query. e.g. ` - some_tag/here`.
---@return string? # The found match, if any.
---
function _P.get_alias_text(text)
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

--- Iterate aliases from a note's top YAML frontmatter.
---
--- Raises:
---     If `path` cannot be read for data.
---
---@param path string An absolute path on-disk to some obsidian note to query from.
---@return fun(): string? # A generator that yields one alias at a time.
function _P.iter_aliases(path)
    local handler = io.open(path)

    if not handler then
        error(string.format('File "%s" could not be opened.', path), 0)
    end

    local aliases_started = false
    ---@type string[]
    local aliases = {}
    local line_number = 0

    for line in handler:lines() do
        line_number = line_number + 1

        if line_number == 1 then
            if line ~= _METADATA_MARKER then
                break
            end
        elseif line == _METADATA_MARKER then
            break
        elseif line == _ALIASES_START_MARKER or line == "aliases: []" then
            aliases_started = line == _ALIASES_START_MARKER
        elseif aliases_started then
            local alias = _P.get_alias_text(line)

            if alias then
                table.insert(aliases, alias)
            elseif _P.is_metadata_key_line(line) then
                aliases_started = false
            end
        end
    end

    handler:close()

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

--- Normalize a path for comparisons.
---
---@param path string Some file or directory path.
---@return string # The normalized path.
function _P.normalize_path(path)
    return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

--- Check if `path` is inside `directory`.
---
---@param directory string The possible parent directory.
---@param path string The possible child path.
---@return boolean # If `path` is inside `directory`, return `true`.
function _P.is_path_inside(directory, path)
    local ok, relative = pcall(vim.fs.relpath, _P.normalize_path(directory), _P.normalize_path(path))

    if not ok or not relative then
        return false
    end

    return relative ~= ".." and not relative:match("^%.%.[/\\]")
end

--- Get the Obsidian workspace root for `path`, if any.
---
---@param path string A buffer path.
---@return string? # The workspace root, if `path` is inside a vault workspace.
function _P.get_workspace_root_for_path(path)
    local vault_root = _P.get_vaults_root_path()
    local ok, relative = pcall(vim.fs.relpath, _P.normalize_path(vault_root), _P.normalize_path(path))

    if not ok or not relative or relative == ".." or relative:match("^%.%.[/\\]") then
        return nil
    end

    local workspace_name = relative:match("^([^/\\]+)[/\\]")

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
---@return string[] # Sorted markdown file paths.
function _P.get_markdown_files(workspace_root)
    local template = vim.fs.joinpath(workspace_root, "**", "*.md")
    local paths = vim.fn.glob(template, true, true)

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
    local template = vim.fs.joinpath(_ROOT, "**", "*.md")
    ---@type _my.selector_gui.entry.Deserialized[]
    local found = {}

    for _, path in ipairs(vim.fn.glob(template, true, true)) do
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
    today = _P.today,
    tomorrow = _P.tomorrow,
    tommorrow = _P.tomorrow,
    yesterday = _P.yesterday,
}

local _SUBCOMMAND_NAMES = vim.fn.sort(vim.tbl_keys(_SUBCOMMANDS))

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

return _P
