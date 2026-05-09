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

--- Find the alias from `text`, if any.
---
---@param text string The line to query. e.g. ` - some_tag/here`.
---@return string? # The found match, if any.
---
function _P.get_alias_text(text)
    return (string.match(text, "%s*-%s*(.*)"))
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
    --- Check if `line` defines an alias/title for us to read.
    ---
    ---@param line string Some line to check. e.g. `"tags:"`
    ---@return boolean # If `line` defines the start of a non-alias metadata, return `false`.
    ---
    local function _is_alias_line(line)
        local character = line[1]

        return character and character ~= " "
    end

    local handler = io.open(path)

    if not handler then
        error(string.format('File "%s" could not be opened.', path), 0)
    end

    local started = false
    local aliases_started = false
    ---@type string[]
    local output = {}

    for line in handler:lines() do
        if line == _METADATA_MARKER then
            if not started then
                started = true
            else
                break
            end
        elseif line == _ALIASES_START_MARKER then
            aliases_started = true
        elseif aliases_started then
            local alias = _P.get_alias_text(line)

            if alias then
                table.insert(output, alias)
            elseif not _is_alias_line(line) then
                break
            end
        end
    end

    return output
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

    local date = os.date("%Y-%m-%d")
    local time = os.date("%H:%M")

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
    vim.cmd.edit(path)
end

--- Show the Obsidian workspace that notes will be created / searched / etc within.
function _P.print_current_workspace()
    vim.notify(string.format('Current Workspace: "%s"', _CURRENT_WORKSPACE), vim.log.levels.INFO)
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
    local today_data = os.date("*t")

    if type(today_data) == "string" then
        error("Expected os.date('*t') to return a date table.", 0)
    end

    ---@type osdateparam
    local today = {
        year = today_data.year,
        month = today_data.month,
        day = today_data.day,
        hour = 12,
        min = 0,
        sec = 0,
        isdst = today_data.isdst,
    }

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
