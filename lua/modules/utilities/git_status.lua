--- Cached Git status details for statusline display.

local core_helpers = require("modules.utilities.core_helpers")

local M = {}
local _P = {}

---@class _my.git_status.Operation
---@field name string
---@field current integer?
---@field total integer?

---@class _my.git_status.Status
---@field branch string
---@field upstream_branch string
---@field is_dirty boolean
---@field up_to_date boolean
---@field up_to_date_and_clean boolean
---@field ahead integer
---@field behind integer
---@field stashed integer
---@field conflicted integer
---@field deleted integer
---@field modified integer
---@field renamed integer
---@field staged integer
---@field staged_added integer
---@field staged_deleted integer
---@field staged_modified integer
---@field staged_renamed integer
---@field untracked integer
---@field operation _my.git_status.Operation?

---@class _my.git_status.RepositoryDetails
---@field repository string
---@field git_dir string

---@class _my.git_status.CacheEntry
---@field status _my.git_status.Status?
---@field checked_at integer
---@field details _my.git_status.RepositoryDetails?
---@field in_flight boolean
---@field failed boolean
---@field watcher uv_fs_event_t?

---@class _my.git_status.Options
---@field auto_fetch_interval integer
---@field git_status_timeout integer

---@type _my.git_status.Options
M.opts = {
    auto_fetch_interval = 30000,
    git_status_timeout = 1000,
}

local _GIT_STATUS_REFRESH_INTERVAL = 1000
local _GIT_STATUS_BUSY_DELAY = 1000
---@type table<string, _my.git_status.CacheEntry>
local _CACHE = {}
local _IS_GIT_AVAILABLE = nil
local _DID_SETUP = false
local _FETCH_TIMER = nil

---@type table<string, table<string, string>>
local _ICONS = {
    nerd = {
        ahead = "{}",
        behind = "{}",
        conflicted = "{} [CONFLICT]",
        deleted = "󰮉{}",
        modified = "{}",
        operation = "",
        renamed = "{}",
        staged = "{}",
        stashed = "{}",
        untracked = "{}",
    },
    plain = {
        ahead = "{}↑",
        behind = "{}↓",
        conflicted = "{}!",
        deleted = "{}-",
        modified = "{}*",
        operation = "git",
        renamed = "{}~",
        staged = "{}=",
        stashed = "{}$",
        untracked = "{}+",
    },
}

---@type { [integer]: { [1]: string, hl: string } }
local _SECTIONS = {
    { "ahead", hl = "StatusGitAhead" },
    { "behind", hl = "StatusGitBehind" },
    { "conflicted", hl = "StatusGitConflict" },
    { "modified", hl = "StatusGitModified" },
    { "staged", hl = "StatusGitStaged" },
    { "renamed", hl = "StatusGitRenamed" },
    { "deleted", hl = "StatusGitDeleted" },
    { "stashed", hl = "StatusGitStashed" },
    { "untracked", hl = "StatusGitUntracked" },
}

---@return table<string, string>
local function _get_icons()
    if core_helpers.IS_NERDFONT_ALLOWED then
        return _ICONS.nerd
    end

    return _ICONS.plain
end

---@return boolean
local function _is_git_available()
    if _IS_GIT_AVAILABLE == nil then
        _IS_GIT_AVAILABLE = core_helpers.exists_command(core_helpers._GIT_EXECUTABLE)
    end

    return _IS_GIT_AVAILABLE
end

---@param buffer integer
---@return string?
local function _get_terminal_job_directory(buffer)
    local job_id = vim.b[buffer].terminal_job_id

    if not job_id then
        return nil
    end

    local ok, pid = pcall(vim.fn.jobpid, job_id)

    if not ok or pid <= 0 then
        return nil
    end

    local ok_realpath, directory = pcall(vim.uv.fs_realpath, "/proc/" .. pid .. "/cwd")

    if ok_realpath and type(directory) == "string" and vim.fn.isdirectory(directory) == 1 then
        return directory
    end

    return nil
end

---@param buffer integer
---@return string?
local function _get_terminal_buffer_directory(buffer)
    local terminal_job_directory = _get_terminal_job_directory(buffer)

    if terminal_job_directory then
        return terminal_job_directory
    end

    local toggle_terminal_cwd = vim.b[buffer]._toggle_terminal_cwd

    if toggle_terminal_cwd and vim.fn.isdirectory(toggle_terminal_cwd) == 1 then
        return toggle_terminal_cwd
    end

    local name = vim.api.nvim_buf_get_name(buffer)
    local directory = name:match("^term://(.-)//")

    if directory and vim.fn.isdirectory(directory) == 1 then
        return directory
    end

    return nil
end

---@return string
local function _get_reference_path()
    local buffer = vim.api.nvim_get_current_buf()

    if vim.bo[buffer].buftype == "terminal" then
        return _get_terminal_buffer_directory(buffer) or vim.fn.getcwd()
    end

    local path = vim.api.nvim_buf_get_name(buffer)

    if path == "" then
        return vim.fn.getcwd()
    end

    return vim.fs.dirname(path)
end

---@param path string?
---@return string
local function _get_cache_key(path)
    return vim.fs.normalize(path or _get_reference_path())
end

---@param path string?
---@return _my.git_status.CacheEntry
local function _get_entry(path)
    local key = _get_cache_key(path)
    local entry = _CACHE[key]

    if not entry then
        entry = { checked_at = 0, in_flight = false, failed = false }
        _CACHE[key] = entry
    end

    return entry
end

---@param path string
---@param callback fun(details: _my.git_status.RepositoryDetails?): nil
local function _get_repository_details(path, callback)
    vim.system(
        { core_helpers._GIT_EXECUTABLE, "-C", path, "rev-parse", "--show-toplevel", "--absolute-git-dir" },
        { text = true },
        function(process)
            if process.code ~= 0 then
                vim.schedule(function()
                    callback(nil)
                end)

                return
            end

            local lines = vim.split(process.stdout or "", "\n", { plain = true, trimempty = true })
            local repository = lines[1]
            local git_dir = lines[2]

            vim.schedule(function()
                if not repository or not git_dir then
                    callback(nil)

                    return
                end

                callback({ repository = repository, git_dir = git_dir })
            end)
        end
    )
end

---@param path string
---@return integer?
local function _read_number(path)
    if vim.fn.filereadable(path) ~= 1 then
        return nil
    end

    local lines = vim.fn.readfile(path, "", 1)
    local value = tonumber(lines[1])

    return value
end

---@param git_dir string
---@return _my.git_status.Operation?
local function _get_operation(git_dir)
    local rebase_merge = vim.fs.joinpath(git_dir, "rebase-merge")
    local rebase_apply = vim.fs.joinpath(git_dir, "rebase-apply")

    if vim.fn.isdirectory(rebase_merge) == 1 then
        return {
            name = "rebase",
            current = _read_number(vim.fs.joinpath(rebase_merge, "msgnum")),
            total = _read_number(vim.fs.joinpath(rebase_merge, "end")),
        }
    end

    if vim.fn.isdirectory(rebase_apply) == 1 then
        local name = "rebase"

        -- NOTE: Git uses `rebase-apply` for both `git rebase --apply` and
        -- `git am`. The sentinel files inside the directory tell us which
        -- high-level operation is actually active.
        if vim.fn.filereadable(vim.fs.joinpath(rebase_apply, "applying")) == 1 then
            name = "am"
        end

        return {
            name = name,
            current = _read_number(vim.fs.joinpath(rebase_apply, "next")),
            total = _read_number(vim.fs.joinpath(rebase_apply, "last")),
        }
    end

    if vim.fn.filereadable(vim.fs.joinpath(git_dir, "MERGE_HEAD")) == 1 then
        return { name = "merge" }
    end

    if vim.fn.filereadable(vim.fs.joinpath(git_dir, "CHERRY_PICK_HEAD")) == 1 then
        return { name = "cherry-pick" }
    end

    if vim.fn.filereadable(vim.fs.joinpath(git_dir, "REVERT_HEAD")) == 1 then
        return { name = "revert" }
    end

    return nil
end

---@return _my.git_status.Status
local function _make_status()
    return {
        branch = "",
        upstream_branch = "",
        ahead = 0,
        behind = 0,
        stashed = 0,
        conflicted = 0,
        deleted = 0,
        modified = 0,
        renamed = 0,
        staged = 0,
        staged_added = 0,
        staged_deleted = 0,
        staged_modified = 0,
        staged_renamed = 0,
        untracked = 0,
        is_dirty = false,
        up_to_date = true,
        up_to_date_and_clean = true,
    }
end

---@param output string
---@param git_dir string
---@return _my.git_status.Status
function _P.parse_status(output, git_dir)
    local status = _make_status()

    for _, line in ipairs(vim.split(output, "\n", { plain = true, trimempty = true })) do
        local parts = vim.split(line, " ")

        if parts[1] == "#" then
            if parts[2] == "branch.head" then
                status.branch = parts[3] or ""
            elseif parts[2] == "branch.upstream" then
                status.upstream_branch = parts[3] or ""
            elseif parts[2] == "branch.ab" then
                status.ahead = tonumber((parts[3] or ""):sub(2)) or 0
                status.behind = tonumber((parts[4] or ""):sub(2)) or 0
            elseif parts[2] == "stash" then
                status.stashed = tonumber(parts[3]) or 0
            end
        elseif parts[1] == "1" then
            local code_x = (parts[2] or ""):sub(1, 1)
            local code_y = (parts[2] or ""):sub(2, 2)

            if code_x ~= "." and code_x ~= "" then
                status.staged = status.staged + 1

                if code_x == "A" then
                    status.staged_added = status.staged_added + 1
                elseif code_x == "D" then
                    status.staged_deleted = status.staged_deleted + 1
                elseif code_x == "M" then
                    status.staged_modified = status.staged_modified + 1
                elseif code_x == "R" then
                    status.staged_renamed = status.staged_renamed + 1
                end
            end

            if code_y == "M" or code_y == "T" then
                status.modified = status.modified + 1
            elseif code_y == "D" then
                status.deleted = status.deleted + 1
            end
        elseif parts[1] == "2" then
            status.renamed = status.renamed + 1
        elseif parts[1] == "u" then
            status.conflicted = status.conflicted + 1
        elseif parts[1] == "?" then
            status.untracked = status.untracked + 1
        end
    end

    status.operation = _get_operation(git_dir)
    status.is_dirty = status.modified > 0
        or status.deleted > 0
        or status.renamed > 0
        or status.untracked > 0
        or status.conflicted > 0
    status.up_to_date = status.ahead == 0 and status.behind == 0
    status.up_to_date_and_clean = status.up_to_date and not status.is_dirty

    return status
end

---@param entry _my.git_status.CacheEntry
local function _watch_git_dir(entry)
    if entry.watcher and entry.watcher:is_active() then
        return
    end

    if not entry.details then
        return
    end

    local watcher = vim.uv.new_fs_event()

    if not watcher then
        return
    end

    watcher:start(entry.details.git_dir, {}, function(error, filename)
        if error or not filename then
            return
        end

        vim.schedule(function()
            M.refresh()
        end)
    end)

    entry.watcher = watcher
end

---@param entry _my.git_status.CacheEntry
local function _run_status(entry)
    if not entry.details then
        return
    end

    vim.system({
        core_helpers._GIT_EXECUTABLE,
        "-C",
        entry.details.repository,
        "--no-optional-locks",
        "status",
        "--porcelain=2",
        "--branch",
        "--show-stash",
        "--untracked-files=all",
    }, {
        text = true,
        timeout = M.opts.git_status_timeout,
    }, function(process)
        vim.defer_fn(function()
            entry.in_flight = false
        end, _GIT_STATUS_BUSY_DELAY)

        if process.signal == 15 or process.code ~= 0 then
            vim.schedule(function()
                entry.failed = true
                vim.cmd("redrawstatus!")
            end)

            return
        end

        local details = entry.details

        if not details then
            return
        end

        vim.schedule(function()
            entry.status = _P.parse_status(process.stdout or "", details.git_dir)
            entry.checked_at = vim.uv.now()
            entry.failed = false
            _watch_git_dir(entry)
            vim.cmd("redrawstatus!")
        end)
    end)
end

---@param path string?
function M.refresh(path)
    if not _is_git_available() then
        return
    end

    local reference_path = path or _get_reference_path()
    local entry = _get_entry(reference_path)

    if entry.in_flight then
        return
    end

    entry.in_flight = true

    if entry.details then
        _run_status(entry)

        return
    end

    _get_repository_details(reference_path, function(details)
        if not details then
            entry.status = nil
            entry.failed = true
            entry.checked_at = vim.uv.now()
            entry.in_flight = false
            vim.cmd("redrawstatus!")

            return
        end

        entry.details = details
        _run_status(entry)
    end)
end

function M.fetch()
    if not _is_git_available() then
        return
    end

    local entry = _get_entry()

    if not entry.details then
        return
    end

    vim.system(
        { core_helpers._GIT_EXECUTABLE, "-C", entry.details.repository, "fetch" },
        { text = true },
        function(process)
            if process.code == 0 then
                vim.schedule(function()
                    M.refresh()
                end)
            end
        end
    )
end

---@param status _my.git_status.Status
---@return string?
local function _format_operation(status)
    local operation = status.operation

    if not operation then
        return nil
    end

    local icons = _get_icons()
    local text = icons.operation .. " " .. operation.name

    if operation.current and operation.total then
        text = text .. string.format(" %s/%s", operation.current, operation.total)
    end

    if status.conflicted > 0 then
        text = text .. string.format(" %s!", status.conflicted)
    end

    return "%#StatusGitConflict#" .. text
end

---@param name string
---@param value integer
---@param highlight string
---@return string?
local function _format_section(name, value, highlight)
    if value == 0 then
        return nil
    end

    local format = _get_icons()[name]

    return string.format("%%#%s#%s", highlight, format:gsub("{}", tostring(value)))
end

---@param path string?
---@return string
function M.get_statusline(path)
    if not _is_git_available() then
        return ""
    end

    local entry = _get_entry(path or _get_reference_path())
    local now = vim.uv.now()

    if entry.checked_at == 0 or (now - entry.checked_at) > _GIT_STATUS_REFRESH_INTERVAL then
        M.refresh(path)
    end

    if not entry.status then
        return ""
    end

    ---@type string[]
    local parts = {}
    local operation = _format_operation(entry.status)

    if operation then
        table.insert(parts, operation)
    end

    for _, section in ipairs(_SECTIONS) do
        local text = _format_section(section[1], entry.status[section[1]], section.hl)

        if text then
            table.insert(parts, text)
        end
    end

    if vim.tbl_isempty(parts) then
        return ""
    end

    return " " .. table.concat(parts, "%#StatusGitSeparator# ") .. " "
end

function M.setup()
    if _DID_SETUP then
        return
    end

    _DID_SETUP = true

    vim.api.nvim_create_autocmd(
        { "BufEnter", "BufFilePost", "BufWritePost", "DirChanged", "FileChangedShellPost", "FocusGained" },
        {
            callback = function()
                M.refresh()
            end,
        }
    )

    M.refresh()

    if M.opts.auto_fetch_interval and M.opts.auto_fetch_interval > 0 then
        local interval = math.max(M.opts.auto_fetch_interval, 1000)
        _FETCH_TIMER = vim.uv.new_timer()

        if _FETCH_TIMER then
            _FETCH_TIMER:start(interval, interval, function()
                vim.schedule(M.fetch)
            end)
        end
    end
end

return M
