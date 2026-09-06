--- Navigate cached repository Git hunks without using the quickfix list.

local M = {}
local _P = {}

local _AUGROUP = vim.api.nvim_create_augroup("my.git_hunk_navigation", { clear = true })

---@class _my.git_hunk_navigation.Entry
---@field absolute_path string The absolute file path for the hunk.
---@field relative_path string The repository-relative file path for the hunk.
---@field lnum integer The best target line for the hunk.
---@field end_lnum integer The last line covered by the hunk selection range.
---@field old_start integer The hunk's original starting line.
---@field old_count integer The hunk's original line count.
---@field new_start integer The hunk's target starting line.
---@field new_count integer The hunk's target line count.
---@field text string The quickfix display text.

---@class _my.git_hunk_navigation.State
---@field active_repository string? The repository used by the latest load or jump.
---@field repositories table<string, _my.git_hunk_navigation.RepositoryState> The cached hunks by repository root.

---@class _my.git_hunk_navigation.RepositoryState
---@field arguments string[] The last `git diff` arguments used after `diff`.
---@field entries _my.git_hunk_navigation.Entry[] The cached hunks.
---@field index integer The current hunk index.
---@field repository string The repository root.
---@field stale boolean If `true`, the repository hunks should be reloaded before navigation.

---@type _my.git_hunk_navigation.State
local _STATE = {
    active_repository = nil,
    repositories = {},
}

--- Get the path that should be used to resolve the current Git repository.
---
---@return string # The current buffer path or working directory.
local function _get_current_path()
    local buffer_path = vim.api.nvim_buf_get_name(0)

    if buffer_path ~= "" then
        return vim.fn.fnamemodify(buffer_path, ":p:h")
    end

    return vim.fn.getcwd()
end

--- Get the normalized path for `buffer`.
---
---@param buffer integer The buffer to inspect.
---@return string? # The normalized file path, if present.
local function _get_buffer_path(buffer)
    local path = vim.api.nvim_buf_get_name(buffer)

    if path == "" then
        return nil
    end

    return vim.fn.fnamemodify(path, ":p")
end

--- Normalize a path for cross-platform repository comparisons.
---
---@param path string The path to normalize.
---@return string # The absolute path with forward slashes and no trailing separator.
local function _normalize_path(path)
    local normalized = vim.fn.fnamemodify(path, ":p"):gsub("\\", "/")

    if normalized ~= "/" and not normalized:match("^%a:/$") then
        normalized = normalized:gsub("/+$", "")
    end

    return normalized
end

--- Normalize path case for comparison on Windows drive-letter paths.
---
---@param path string The already separator-normalized path.
---@return string # A path suitable for prefix comparisons.
local function _get_comparison_path(path)
    if path:match("^%a:") then
        return path:lower()
    end

    return path
end

--- Get `path` relative to `repository`, if `path` is inside it.
---
---@param repository string The repository root.
---@param path string The absolute file path.
---@return string? # The repository-relative path, if `path` is inside `repository`.
local function _get_relative_path_from_repository(repository, path)
    local repository_path = _normalize_path(repository)
    local normalized_path = _normalize_path(path)
    local separator = repository_path:sub(-1) == "/" and "" or "/"
    local repository_prefix = repository_path .. separator

    if _get_comparison_path(normalized_path):sub(1, #repository_prefix) ~= _get_comparison_path(repository_prefix) then
        return nil
    end

    return normalized_path:sub(#repository_prefix + 1)
end

--- Get the cached repository state for the current buffer, without running Git.
---
---@return string? # The repository root, if cached.
---@return _my.git_hunk_navigation.RepositoryState? # The cached repository state.
---@return string? # The current repository-relative path.
local function _get_current_cached_repository()
    local path = _get_buffer_path(0)

    if not path then
        return nil, nil, nil
    end

    for repository, repository_state in pairs(_STATE.repositories) do
        if not repository_state.stale then
            local relative_path = _get_relative_path_from_repository(repository, path)

            if relative_path then
                return repository, repository_state, relative_path
            end
        end
    end

    return nil, nil, nil
end

--- Get a Git repository root from `path`.
---
---@param path string The path to search from.
---@param callback fun(repository: string?, message: string?): nil Callback with the repository root.
local function _get_repository(path, callback)
    local git_diff = require("modules.utilities.git_diff")

    git_diff.run_git({ "-C", path, "rev-parse", "--show-toplevel" }, path, nil, function(result)
        if result.code ~= 0 then
            callback(nil, vim.trim(result.stderr))

            return
        end

        callback(vim.trim(result.stdout), nil)
    end)
end

--- Build the command-line arguments for `git diff`.
---
--- CAVEAT: These arguments do not pin the diff header format, so the user's Git
--- configuration can change output that `_parse_diff_path` and
--- `_unescape_diff_path` expect. Adding `--src-prefix=a/ --dst-prefix=b/
--- --no-ext-diff` here, and `-c core.quotePath=false` before `diff` in the
--- command list, normalizes every known case.
---
---@param arguments string[] User-provided arguments after `:LoadGitDiff`.
---@return string[] # The complete Git arguments.
local function _make_diff_arguments(arguments)
    ---@type string[]
    local command = { "diff", "--unified=0", "--no-color", "--find-renames" }
    vim.list_extend(command, arguments)

    return command
end

--- Unescape a path parsed from a quoted Git diff header.
---
--- CAVEAT: This only undoes `\"` and `\\`. It does not decode the octal escapes
--- that `core.quotePath` (on by default) applies to non-ASCII paths, so `café.txt`
--- arrives as `"caf\303\251.txt"` and yields an entry pointing at a file named
--- literally `caf\303\251.txt`. Running the diff with `-c core.quotePath=false`
--- avoids the escaping entirely. Paths containing spaces are not quoted by Git,
--- so they are unaffected.
---
---@param path string The escaped path to normalize.
---@return string # The unescaped path.
local function _unescape_diff_path(path)
    return (path:gsub('\\"', '"'):gsub("\\\\", "\\"))
end

--- Parse the current target file path from a `diff --git` line.
---
--- Hunk target line numbers are relative to the `b/...` side of a diff. This
--- matters for renames because jumping to the old `a/...` path can open an
--- empty buffer and make otherwise-valid target line numbers out of range.
---
--- CAVEAT: Both patterns hard-code the default `a/` and `b/` prefixes, so a user
--- with `diff.noprefix=true` (`diff --git file.txt file.txt`) or
--- `diff.mnemonicPrefix=true` (`diff --git i/file.txt w/file.txt`) matches
--- neither and gets zero hunks with no error. Passing explicit
--- `--src-prefix=a/ --dst-prefix=b/` to `git diff` overrides both settings.
---
---@param line string The diff line to parse.
---@return string? # The target repository-relative path, if found.
local function _parse_diff_path(line)
    local path = line:match("^diff %-%-git a/.- b/(.+)$")

    if path then
        return path
    end

    path = line:match('^diff %-%-git "a/.-" "b/(.+)"$')

    if path then
        return _unescape_diff_path(path)
    end

    return nil
end

--- Get the target line range that selects all changes in `hunk`.
---
---@param hunk _my.git_diff.Hunk|_my.git_diff.SelectionHunk The parsed diff hunk.
---@return integer # The first target line.
---@return integer # The last target line.
local function _get_hunk_range(hunk)
    if hunk.new_count == 0 then
        local first = math.max(hunk.new_start, 1)

        return first, math.max(first, hunk.new_start + 1)
    end

    local first = math.max(hunk.new_start, 1)
    local size = math.max(hunk.old_count, hunk.new_count)

    return first, first + size - 1
end

--- Get the closest line to `index` in `lines` that has visible characters.
---
--- Later lines win ties because a blank line usually leads into the change that
--- it belongs to, rather than trailing the change before it.
---
---@param lines string[]? The lines to search.
---@param index integer The line to search around.
---@return string? # The nearest non-empty line, if `lines` has one.
local function _find_nearest_non_empty(lines, index)
    if not lines then
        return nil
    end

    for offset = 0, #lines do
        local after = lines[index + offset]

        if after and vim.trim(after) ~= "" then
            return after
        end

        local before = lines[index - offset]

        if before and vim.trim(before) ~= "" then
            return before
        end
    end

    return nil
end

--- Get the quickfix display text for `hunk`.
---
--- The quickfix list already shows the file path and line number in its own
--- columns, so the display text shows the changed line's contents instead.
--- Delete-only hunks have no line left to show, so they fall back to the first
--- removed line. A whitespace-only line says nothing about the change, so those
--- show the nearest non-empty line instead.
---
---@param hunk _my.git_diff.Hunk|_my.git_diff.SelectionHunk The parsed diff hunk.
---@param lnum integer The best target line for the hunk.
---@param new_lines string[]? The current file lines, when they are known.
---@param old_lines string[]? The indexed file lines, when they are known.
---@return string # The changed line's contents, if any could be found.
local function _get_entry_text(hunk, lnum, new_lines, old_lines)
    ---@type string?
    local text

    if hunk.new_count > 0 then
        ---@diagnostic disable-next-line: undefined-field
        local added = hunk.added
        text = _find_nearest_non_empty(added, 1) or _find_nearest_non_empty(new_lines, lnum)
    else
        ---@diagnostic disable-next-line: undefined-field
        local removed = hunk.removed
        text = _find_nearest_non_empty(removed, 1) or _find_nearest_non_empty(old_lines, hunk.old_start)
    end

    return vim.trim(text or "")
end

--- Convert a parsed diff hunk into a cached navigation entry.
---
---@param repository string The repository root.
---@param relative_path string The repository-relative file path.
---@param hunk _my.git_diff.Hunk|_my.git_diff.SelectionHunk The parsed diff hunk.
---@param new_lines string[]? The current file lines, when they are known.
---@param old_lines string[]? The indexed file lines, when they are known.
---@return _my.git_hunk_navigation.Entry # The cached entry.
local function _make_entry(repository, relative_path, hunk, new_lines, old_lines)
    local lnum, end_lnum = _get_hunk_range(hunk)

    return {
        absolute_path = vim.fs.joinpath(repository, relative_path),
        end_lnum = end_lnum,
        lnum = lnum,
        new_count = hunk.new_count,
        new_start = hunk.new_start,
        old_count = hunk.old_count,
        old_start = hunk.old_start,
        relative_path = relative_path,
        text = _get_entry_text(hunk, lnum, new_lines, old_lines),
    }
end

--- Compare two navigation entries in repository order.
---
---@param left _my.git_hunk_navigation.Entry The first entry.
---@param right _my.git_hunk_navigation.Entry The second entry.
---@return boolean # If `left` should sort before `right`, return `true`.
local function _sort_entries(left, right)
    if left.relative_path == right.relative_path then
        return left.lnum < right.lnum
    end

    return left.relative_path < right.relative_path
end

--- Sort cached entries into deterministic repository order.
---
---@param entries _my.git_hunk_navigation.Entry[] The entries to sort in place.
local function _sort_cached_entries(entries)
    table.sort(entries, _sort_entries)
end

--- Remove cached entries for one repository-relative path.
---
---@param entries _my.git_hunk_navigation.Entry[] The entries to modify in place.
---@param relative_path string The repository-relative path to remove.
local function _remove_file_entries(entries, relative_path)
    for index = #entries, 1, -1 do
        if entries[index].relative_path == relative_path then
            table.remove(entries, index)
        end
    end
end

--- Build unsaved-buffer hunk entries for a buffer in `repository`.
---
--- An unmodified buffer's content matches disk exactly. If disk already has no
--- diff for it either, there is nothing to override, so this skips the git
--- subprocess round trip entirely -- the common case for the many untouched
--- buffers that can be open in a large repository. An unmodified buffer whose
--- file *does* have a disk diff still goes through the full lookup, since the
--- entry text uses the buffer's live lines for a better "nearest non-empty
--- line" fallback than the raw diff hunk can provide.
---
---@param repository string The repository root.
---@param buffer integer The buffer to inspect.
---@param diffed_relative_paths table<string, boolean> Relative paths with a disk-diff entry.
---@param callback fun(entries: _my.git_hunk_navigation.Entry[], relative_path: string?): nil
---    Callback with buffer hunks.
local function _make_buffer_entries(repository, buffer, diffed_relative_paths, callback)
    if
        not vim.api.nvim_buf_is_valid(buffer)
        or not vim.api.nvim_buf_is_loaded(buffer)
        or vim.api.nvim_buf_get_name(buffer) == ""
    then
        callback({}, nil)

        return
    end

    if not vim.bo[buffer].modified then
        local path = _get_buffer_path(buffer)
        local relative_path = path and _get_relative_path_from_repository(repository, path)

        if not relative_path or not diffed_relative_paths[relative_path] then
            callback({}, nil)

            return
        end
    end

    local git_diff = require("modules.utilities.git_diff")

    git_diff.get_file_details(buffer, function(details)
        if not details or details.repository ~= repository then
            callback({}, nil)

            return
        end

        git_diff.get_index_lines(details, function(old_lines)
            local new_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
            ---@type _my.git_hunk_navigation.Entry[]
            local entries = {}

            for _, hunk in ipairs(git_diff.compute_hunks(old_lines, new_lines)) do
                table.insert(entries, _make_entry(repository, details.relative_path, hunk, new_lines, old_lines))
            end

            callback(entries, details.relative_path)
        end)
    end)
end

--- Replace disk-based entries with unsaved hunks from loaded buffers.
---
---@param repository string The repository root.
---@param entries _my.git_hunk_navigation.Entry[] The loaded entries to modify.
---@param callback fun(): nil Callback after loaded buffer hunks are merged.
local function _merge_loaded_buffer_hunks(repository, entries, callback)
    local buffers = vim.api.nvim_list_bufs()

    ---@type table<string, boolean>
    local diffed_relative_paths = {}

    for _, entry in ipairs(entries) do
        diffed_relative_paths[entry.relative_path] = true
    end

    if #buffers == 0 then
        _sort_cached_entries(entries)
        callback()

        return
    end

    local pending = #buffers
    ---@type table<integer, {entries: _my.git_hunk_navigation.Entry[], relative_path: string?}>
    local results = {}

    --- Save one buffer's result and merge all results after every fetch finishes.
    ---
    ---@param buffer integer The buffer that finished.
    ---@param buffer_entries _my.git_hunk_navigation.Entry[] The buffer's hunks.
    ---@param relative_path string? The buffer's repository-relative path.
    local function _finish_buffer(buffer, buffer_entries, relative_path)
        results[buffer] = { entries = buffer_entries, relative_path = relative_path }
        pending = pending - 1

        if pending > 0 then
            return
        end

        for _, ordered_buffer in ipairs(buffers) do
            local result = results[ordered_buffer]

            if result and result.relative_path then
                _remove_file_entries(entries, result.relative_path)
                vim.list_extend(entries, result.entries)
            end
        end

        _sort_cached_entries(entries)
        callback()
    end

    for _, buffer in ipairs(buffers) do
        _make_buffer_entries(repository, buffer, diffed_relative_paths, function(buffer_entries, relative_path)
            _finish_buffer(buffer, buffer_entries, relative_path)
        end)
    end
end

--- Parse `git diff --unified=0` output into cached navigation entries.
---
---@param repository string The repository root.
---@param diff string The unified diff text.
---@return _my.git_hunk_navigation.Entry[] # The parsed entries.
function M._parse_diff(repository, diff)
    local git_diff = require("modules.utilities.git_diff")

    ---@type _my.git_hunk_navigation.Entry[]
    local entries = {}
    ---@type string?
    local relative_path
    local is_deleted_file = false
    ---@type string[]
    local hunk_lines = {}

    --- Flush the current file hunk buffer into `entries`.
    ---
    local function _flush_file()
        if not relative_path or is_deleted_file or #hunk_lines == 0 then
            ---@type string[]
            hunk_lines = {}
            is_deleted_file = false

            return
        end

        for _, hunk in ipairs(git_diff.parse_selection_diff(table.concat(hunk_lines, "\n"))) do
            table.insert(entries, _make_entry(repository, relative_path, hunk))
        end

        ---@type string[]
        hunk_lines = {}
        is_deleted_file = false
    end

    for line in vim.gsplit(diff, "\n", { plain = true }) do
        local found_path = _parse_diff_path(line)

        if found_path then
            _flush_file()
            relative_path = found_path
            is_deleted_file = false
        elseif line:match("^deleted file mode ") then
            is_deleted_file = true
        elseif line:sub(1, 3) == "@@ " or line:sub(1, 1) == "-" or line:sub(1, 1) == "+" then
            table.insert(hunk_lines, line)
        end
    end

    _flush_file()

    return entries
end

--- Replace the cached Git hunk state.
---
---@param repository string The repository root.
---@param arguments string[] The Git diff arguments used.
---@param entries _my.git_hunk_navigation.Entry[] The hunks to cache.
function _P.set_state(repository, arguments, entries)
    _STATE.active_repository = repository
    _sort_cached_entries(entries)
    _STATE.repositories[repository] = {
        arguments = vim.deepcopy(arguments),
        entries = entries,
        index = 0,
        repository = repository,
        stale = false,
    }
end

--- Get the cached Git hunk state.
---
---@return _my.git_hunk_navigation.State # The current state.
function M._get_state()
    return _STATE
end

--- Get the cached Git hunk state for a repository.
---
---@param repository string? The repository root. Defaults to the active repository.
---@return _my.git_hunk_navigation.RepositoryState? # The cached repository state, if present.
function M._get_repository_state(repository)
    repository = repository or _STATE.active_repository

    if not repository then
        return nil
    end

    return _STATE.repositories[repository]
end

--- Remove staged hunks from the active repository cache without re-running Git.
---
--- When `line` is given, only the closest hunk in the buffer is removed.
--- Otherwise every hunk for the buffer is removed.
---
---@param buffer integer The buffer whose hunks were staged.
---@param line integer? The cursor line used to choose one hunk.
---@return integer? # The remaining hunk count, or `nil` if the cache could not be reconciled.
function M.remove_cached_hunks_for_buffer(buffer, line)
    local repository_state = M._get_repository_state()
    local path = _get_buffer_path(buffer)

    if not repository_state or not path then
        return nil
    end

    ---@type integer[]
    local matching = {}

    for index, entry in ipairs(repository_state.entries) do
        if vim.fn.fnamemodify(entry.absolute_path, ":p") == path then
            table.insert(matching, index)
        end
    end

    if #matching == 0 then
        return nil
    end

    if line then
        ---@type integer?
        local closest_index
        local closest_distance = math.huge

        for _, index in ipairs(matching) do
            local entry = repository_state.entries[index]
            local distance

            if entry.lnum <= line and line <= entry.end_lnum then
                distance = 0
            elseif line < entry.lnum then
                distance = entry.lnum - line
            else
                distance = line - entry.end_lnum
            end

            if distance < closest_distance then
                closest_index = index
                closest_distance = distance
            end
        end

        table.remove(repository_state.entries, assert(closest_index))
    else
        for index = #matching, 1, -1 do
            table.remove(repository_state.entries, matching[index])
        end
    end

    repository_state.index = math.min(repository_state.index, #repository_state.entries)
    return #repository_state.entries
end

--- Mark a cached repository as stale.
---
---@param repository string The repository root to mark stale.
function _P.mark_stale(repository)
    local repository_state = M._get_repository_state(repository)

    if repository_state then
        repository_state.stale = true
    end
end

--- Mark any cached repositories containing `buffer` as stale.
---
--- CAVEAT: Staleness is only ever driven by buffer edits, so repository changes
--- made outside Neovim (`git checkout`, `rebase`, `stash`, another editor) leave
--- the cache marked current. `[g` and `]g` then navigate hunks from the previous
--- diff until `:LoadGitDiff` reloads them by hand.
---
---@param buffer integer The changed buffer.
function M.mark_stale_for_buffer(buffer)
    local path = _get_buffer_path(buffer)

    if not path then
        return
    end

    for repository in pairs(_STATE.repositories) do
        if _get_relative_path_from_repository(repository, path) then
            _P.mark_stale(repository)
        end
    end
end

--- Load repository hunks from `git diff`.
---
---@param arguments string[]? User-provided arguments after `:LoadGitDiff`.
---@param callback fun(success: boolean): nil Callback with whether hunks loaded.
function M._load(arguments, callback)
    local git_diff = require("modules.utilities.git_diff")

    arguments = arguments or {}
    callback = callback or function() end

    _get_repository(_get_current_path(), function(repository, repository_error)
        if not repository then
            vim.notify(string.format("Cannot load Git hunks: %s", repository_error or ""), vim.log.levels.ERROR)

            callback(false)

            return
        end

        ---@type string[]
        local command = { "-C", repository }
        vim.list_extend(command, _make_diff_arguments(arguments))
        git_diff.run_git(command, repository, nil, function(diff)
            if diff.code ~= 0 then
                vim.notify(string.format("Cannot load Git hunks: %s", vim.trim(diff.stderr)), vim.log.levels.ERROR)

                callback(false)

                return
            end

            local entries = M._parse_diff(repository, diff.stdout)

            _merge_loaded_buffer_hunks(repository, entries, function()
                _P.set_state(repository, arguments, entries)
                vim.notify(string.format("Loaded %s Git hunks.", #entries), vim.log.levels.INFO)

                callback(true)
            end)
        end)
    end)
end

--- Jump to `entry`.
---
---@param entry _my.git_hunk_navigation.Entry The entry to open.
local function _jump_to_entry_line(entry)
    local line_count = math.max(vim.api.nvim_buf_line_count(0), 1)
    local line = math.min(math.max(entry.lnum, 1), line_count)

    vim.api.nvim_win_set_cursor(0, { line, 0 })
    vim.cmd("normal! zz")
end

--- Find a loaded buffer by exact absolute path.
---
---@param path string The absolute file path to find.
---@return integer? # The loaded buffer number, if found.
local function _find_loaded_buffer(path)
    local target = vim.fn.fnamemodify(path, ":p")

    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buffer) then
            local buffer_path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer), ":p")

            if buffer_path == target then
                return buffer
            end
        end
    end

    return nil
end

--- Jump to `entry` while avoiding unnecessary buffer reloads that reset syntax highlighting.
---
---@param entry _my.git_hunk_navigation.Entry The entry to open.
local function _jump_to_entry(entry)
    if _get_buffer_path(0) == vim.fn.fnamemodify(entry.absolute_path, ":p") then
        _jump_to_entry_line(entry)

        return
    end

    local buffer = _find_loaded_buffer(entry.absolute_path)

    if buffer then
        vim.api.nvim_set_current_buf(buffer)
    else
        vim.cmd("keepalt silent edit " .. vim.fn.fnameescape(entry.absolute_path))
    end

    _jump_to_entry_line(entry)
end

--- Get the best current location for position-aware hunk navigation.
---
---@param repository string The repository root.
---@param callback fun(relative_path: string?, line: integer): nil Callback with the current location.
local function _get_current_location(repository, callback)
    local buffer_path = _get_buffer_path(0)

    if not buffer_path then
        callback(nil, 1)

        return
    end

    local git_diff = require("modules.utilities.git_diff")

    git_diff.get_file_details(0, function(details)
        if not details or details.repository ~= repository then
            callback(nil, 1)

            return
        end

        callback(details.relative_path, vim.api.nvim_win_get_cursor(0)[1])
    end)
end

--- Check if `entry` is after a repository-relative cursor location.
---
---@param entry _my.git_hunk_navigation.Entry The entry to compare.
---@param relative_path string The current repository-relative path.
---@param line integer The current cursor line.
---@return boolean # If the entry comes after the cursor, return `true`.
local function _is_after_location(entry, relative_path, line)
    return entry.relative_path > relative_path or (entry.relative_path == relative_path and entry.lnum > line)
end

--- Check if `entry` is before a repository-relative cursor location.
---
---@param entry _my.git_hunk_navigation.Entry The entry to compare.
---@param relative_path string The current repository-relative path.
---@param line integer The current cursor line.
---@return boolean # If the entry comes before the cursor, return `true`.
local function _is_before_location(entry, relative_path, line)
    return entry.relative_path < relative_path or (entry.relative_path == relative_path and entry.lnum < line)
end

--- Find a position-aware navigation target.
---
---@param repository_state _my.git_hunk_navigation.RepositoryState The cached repository state.
---@param direction 1 | -1 The direction to move.
---@param relative_path string? The current repository-relative path.
---@param line integer The current cursor line.
---@return integer # The matching hunk index.
local function _find_target_index(repository_state, direction, relative_path, line)
    if not relative_path then
        return ((repository_state.index - 1 + direction) % #repository_state.entries) + 1
    end

    if direction == 1 then
        for index, entry in ipairs(repository_state.entries) do
            if _is_after_location(entry, relative_path, line) then
                return index
            end
        end

        return 1
    end

    for index = #repository_state.entries, 1, -1 do
        if _is_before_location(repository_state.entries[index], relative_path, line) then
            return index
        end
    end

    return #repository_state.entries
end

--- Jump to the next or previous cached hunk.
---
---@param direction 1 | -1 The direction to move.
function _P.jump(direction)
    local cached_repository, cached_state, cached_relative_path = _get_current_cached_repository()

    if cached_state and #cached_state.entries > 0 then
        _STATE.active_repository = cached_repository
        cached_state.index =
            _find_target_index(cached_state, direction, cached_relative_path, vim.api.nvim_win_get_cursor(0)[1])
        _jump_to_entry(cached_state.entries[cached_state.index])

        return
    end

    if cached_state then
        vim.notify("No Git hunks loaded.", vim.log.levels.INFO)

        return
    end

    _get_repository(_get_current_path(), function(repository, repository_error)
        if not repository then
            vim.notify(string.format("Cannot jump to Git hunk: %s", repository_error or ""), vim.log.levels.ERROR)

            return
        end

        local repository_state = M._get_repository_state(repository)
        local arguments = repository_state and repository_state.arguments or {}

        --- Finish jumping after the cache is current.
        ---
        ---@param success boolean If `true`, loading succeeded.
        local function _finish(success)
            if not success then
                return
            end

            repository_state = M._get_repository_state(repository)

            if not repository_state or #repository_state.entries == 0 then
                vim.notify("No Git hunks loaded.", vim.log.levels.INFO)

                return
            end

            _STATE.active_repository = repository
            _get_current_location(repository, function(relative_path, line)
                repository_state.index = _find_target_index(repository_state, direction, relative_path, line)
                _jump_to_entry(repository_state.entries[repository_state.index])
            end)
        end

        if not repository_state or repository_state.stale then
            M._load(arguments, _finish)

            return
        end

        _finish(true)
    end)
end

--- Convert the cached hunks to quickfix entries.
---
---@param repository string? The repository root. Defaults to the active repository.
---@return vim.quickfix.entry[] # The quickfix entries.
function _P.to_quickfix(repository)
    ---@type vim.quickfix.entry[]
    local items = {}
    local repository_state = M._get_repository_state(repository)

    if not repository_state then
        return items
    end

    for _, entry in ipairs(repository_state.entries) do
        table.insert(items, {
            filename = entry.absolute_path,
            lnum = entry.lnum,
            text = entry.text,
        })
    end

    return items
end

--- Get the quickfix title to show for `repository`.
---
--- The `Git: ` prefix says where the list came from. A bare path looks like any
--- other quickfix list, so it is impossible to tell Git hunks apart from, say, a
--- search whose results happen to sit under the same directory.
---
--- `:~` collapses the home directory to `~` and leaves paths outside it alone,
--- which keeps the title short without hiding where the repository is. `:.`
--- is deliberately not used because it would shorten the repository root to `.`
--- whenever the current directory already is that root.
---
---@param repository string The repository root.
---@return string # The labelled, shortened repository root.
function M._get_quickfix_title(repository)
    return "Git: " .. vim.fn.fnamemodify(repository, ":~")
end

--- Load repository hunks into the cache and quickfix list.
---
---@param arguments string[]? User-provided arguments after `:LoadGitDiff`.
function _P.load_quickfix(arguments)
    _get_repository(_get_current_path(), function(repository, repository_error)
        if not repository then
            vim.notify(string.format("Cannot load Git hunks: %s", repository_error or ""), vim.log.levels.ERROR)

            return
        end

        local repository_state = M._get_repository_state(repository)

        --- Finish loading the quickfix list.
        ---
        ---@param success boolean If `true`, loading succeeded.
        local function _finish(success)
            if not success then
                return
            end

            repository_state = M._get_repository_state(repository)

            local title = M._get_quickfix_title(repository)

            if not repository_state or #repository_state.entries == 0 then
                vim.fn.setqflist({}, "r", { items = {}, title = title })

                return
            end

            vim.fn.setqflist({}, "r", { items = _P.to_quickfix(repository), title = title })
            require("modules.utilities.core_helpers").with_file_messages_suppressed(function()
                vim.cmd.copen()
            end)
        end

        if arguments or not repository_state or repository_state.stale then
            M._load(arguments or (repository_state and repository_state.arguments or {}), _finish)

            return
        end

        _finish(true)
    end)
end

vim.api.nvim_create_user_command("LoadGitDiff", function(options)
    _P.load_quickfix(options.fargs)
end, {
    complete = "file",
    desc = "Load repository Git hunks into the quickfix list.",
    nargs = "*",
})

vim.api.nvim_create_user_command("GitDiffNext", function()
    _P.jump(1)
end, { desc = "Jump to the next cached Git hunk." })

vim.api.nvim_create_user_command("GitDiffPrevious", function()
    _P.jump(-1)
end, { desc = "Jump to the previous cached Git hunk." })

vim.keymap.set("n", "]g", function()
    _P.jump(1)
end, { desc = "Jump to the next cached Git hunk." })

vim.keymap.set("n", "[g", function()
    _P.jump(-1)
end, { desc = "Jump to the previous cached Git hunk." })

vim.api.nvim_create_autocmd({ "BufWritePost", "TextChanged", "TextChangedI" }, {
    callback = function(event)
        M.mark_stale_for_buffer(event.buf)
    end,
    group = _AUGROUP,
})

return M
