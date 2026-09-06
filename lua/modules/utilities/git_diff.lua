--- Shared git diff helpers for buffer signs and hunk staging.

local core_helpers = require("modules.utilities.core_helpers")

local M = {}
local _P = {}

---@class _my.git_diff.FileDetails
---@field absolute_path string
---@field relative_path string
---@field repository string

---@class _my.git_diff.SystemResult
---@field code integer
---@field stdout string
---@field stderr string

---@alias _my.git_diff.SystemCallback fun(result: _my.git_diff.SystemResult): nil

---@class _my.git_diff.Hunk
---@field type "add" | "change" | "delete"
---@field line integer
---@field old_start integer
---@field old_count integer
---@field new_start integer
---@field new_count integer

---@class _my.git_diff.SelectionHunk
---@field old_start integer
---@field old_count integer
---@field new_start integer
---@field new_count integer
---@field removed string[]
---@field added string[]

--- Strip a trailing carriage return from a line for hunk comparisons.
---
---@param line string The line to normalize.
---@return string # The line without a trailing carriage return.
---
local function _strip_trailing_carriage_return(line)
    return (line:gsub("\r$", ""))
end

--- Normalize lines for line-oriented git hunk comparisons.
---
--- Neovim can expose CRLF or mixed line endings as literal trailing `\r`
--- characters in buffer lines, while `git diff --unified=0` may not report a
--- content hunk for those endings. Gutter signs should follow git's hunk view
--- instead of treating the displayed `^M` marker as a changed line.
---
---@param lines string[] The lines to normalize.
---@return string[] # The normalized lines.
---
local function _normalize_hunk_lines(lines)
    ---@type string[]
    local normalized = {}

    for _, line in ipairs(lines) do
        table.insert(normalized, _strip_trailing_carriage_return(line))
    end

    return normalized
end

--- Split `text` into lines without keeping a trailing empty item from final newline.
---
---@param text string Some text to split.
---@return string[] # The split lines.
---
local function _split_lines(text)
    if text == "" then
        return {}
    end

    local lines = vim.split(text, "\n", { plain = true })

    if lines[#lines] == "" then
        table.remove(lines)
    end

    return lines
end

--- Run a git command asynchronously.
---
---@param arguments string[] Git arguments, without the leading executable.
---@param directory string The directory to run within.
---@param stdin string? Optional standard input.
---@param callback _my.git_diff.SystemCallback The callback that receives the command result.
---
function M.run_git(arguments, directory, stdin, callback)
    ---@type string[]
    local command = { core_helpers.GIT_EXECUTABLE }
    vim.list_extend(command, arguments)

    local success, message = pcall(function()
        vim.system(command, { cwd = directory, stdin = stdin, text = true }, function(result)
            vim.schedule(function()
                callback({
                    code = result.code or 1,
                    stderr = result.stderr or "",
                    stdout = result.stdout or "",
                })
            end)
        end)
    end)

    if not success then
        vim.schedule(function()
            callback({
                code = 1,
                stderr = tostring(message),
                stdout = "",
            })
        end)
    end
end

--- Get the first path from Git path-list output.
---
---@param text string The Git command stdout.
---@return string # The first path, or an empty string.
function _P.first_git_path(text)
    local first = text:match("([^\n]+)")

    return first and vim.trim(first) or ""
end

---@type table<integer, integer>
local _DETAILS_GENERATION = {}
---@type table<integer, {generation: integer, details: _my.git_diff.FileDetails?, message: string?}>
local _DETAILS_CACHE = {}
---@type table<integer, {generation: integer, callbacks: fun(details: _my.git_diff.FileDetails?, message: string?)[]}>
local _DETAILS_PENDING = {}

---@type table<string, integer>
local _INDEX_GENERATION = {}
---@type table<string, {generation: integer, lines: string[], missing: boolean}>
local _INDEX_CACHE = {}
---@type table<string, {generation: integer, callbacks: fun(lines: string[], missing: boolean)[]}>
local _INDEX_PENDING = {}

--- Resolve Neovim's special current-buffer handle to a stable buffer number.
---
--- A literal `0` cannot be used as a cache key because it names a different
--- buffer whenever the current window changes.
---
---@param buffer integer The buffer handle to resolve.
---@return integer # The stable buffer handle.
local function _resolve_buffer(buffer)
    if buffer == 0 then
        return vim.api.nvim_get_current_buf()
    end

    return buffer
end

--- Get the cache key for an indexed file.
---
---@param details _my.git_diff.FileDetails The file details to key.
---@return string # A key unique to the repository-relative path.
local function _get_index_key(details)
    return details.repository .. "\0" .. details.relative_path
end

--- Fetch git details for `buffer` without consulting the cache.
---
---@param buffer integer The buffer to inspect.
---@param callback fun(details: _my.git_diff.FileDetails?, message: string?): nil
---    Callback with file details or an error.
---
local function _fetch_file_details_uncached(buffer, callback)
    local absolute_path = vim.api.nvim_buf_get_name(buffer)

    if absolute_path == "" then
        callback(nil, "Current buffer has no file path.")

        return
    end

    local directory = vim.fs.dirname(absolute_path)

    if not directory or vim.fn.isdirectory(directory) == 0 then
        callback(nil, "Current buffer directory does not exist.")

        return
    end

    M.run_git({ "-C", directory, "rev-parse", "--show-toplevel" }, directory, nil, function(repository)
        if repository.code ~= 0 then
            callback(nil, "Current buffer is not inside a git repository.")

            return
        end

        local repository_path = vim.trim(repository.stdout)

        M.run_git(
            { "-C", repository_path, "ls-files", "--full-name", "--deduplicate", "--", absolute_path },
            repository_path,
            nil,
            function(relative)
                local relative_path = _P.first_git_path(relative.stdout)

                if relative_path ~= "" then
                    callback({
                        absolute_path = absolute_path,
                        relative_path = relative_path,
                        repository = repository_path,
                    }, nil)

                    return
                end

                M.run_git(
                    { "-C", repository_path, "rev-parse", "--show-prefix" },
                    repository_path,
                    nil,
                    function(prefix)
                        local filename = vim.fs.basename(absolute_path)
                        callback({
                            absolute_path = absolute_path,
                            relative_path = vim.trim(prefix.stdout) .. filename,
                            repository = repository_path,
                        }, nil)
                    end
                )
            end
        )
    end)
end

--- Forget the cached file details for `buffer` after its path changes.
---
---@param buffer integer The renamed buffer.
function M.invalidate_file_details(buffer)
    buffer = _resolve_buffer(buffer)
    local cached = _DETAILS_CACHE[buffer]

    if cached and cached.details then
        local key = _get_index_key(cached.details)
        _INDEX_GENERATION[key] = (_INDEX_GENERATION[key] or 0) + 1
    end

    _DETAILS_GENERATION[buffer] = (_DETAILS_GENERATION[buffer] or 0) + 1
end

--- Get git details for `buffer`, sharing cached and in-flight results.
---
---@param buffer integer The buffer to inspect.
---@param callback fun(details: _my.git_diff.FileDetails?, message: string?): nil
---    Callback with file details or an error.
function M.get_file_details(buffer, callback)
    buffer = _resolve_buffer(buffer)
    local generation = _DETAILS_GENERATION[buffer] or 0
    local cached = _DETAILS_CACHE[buffer]

    if cached and cached.generation == generation then
        callback(cached.details, cached.message)

        return
    end

    local pending = _DETAILS_PENDING[buffer]

    if pending and pending.generation == generation then
        table.insert(pending.callbacks, callback)

        return
    end

    pending = { generation = generation, callbacks = { callback } }
    _DETAILS_PENDING[buffer] = pending

    _fetch_file_details_uncached(buffer, function(details, message)
        if (_DETAILS_GENERATION[buffer] or 0) == generation then
            _DETAILS_CACHE[buffer] = { generation = generation, details = details, message = message }
        end

        if _DETAILS_PENDING[buffer] == pending then
            _DETAILS_PENDING[buffer] = nil
        end

        for _, waiting in ipairs(pending.callbacks) do
            waiting(details, message)
        end
    end)
end

--- Get the HEAD version of `path`.
---
---@param details _my.git_diff.FileDetails The file details to query.
---@param callback fun(lines: string[], missing: boolean): nil Callback with the HEAD lines.
---
function _P.get_head_lines(details, callback)
    M.run_git(
        { "-C", details.repository, "show", "HEAD:" .. details.relative_path },
        details.repository,
        nil,
        function(result)
            if result.code ~= 0 then
                callback({}, true)

                return
            end

            callback(_split_lines(result.stdout), false)
        end
    )
end

--- Fetch the index version of `path` without consulting the cache.
---
---@param details _my.git_diff.FileDetails The file details to query.
---@param callback fun(lines: string[], missing: boolean): nil Callback with the index lines.
---
local function _fetch_index_lines_uncached(details, callback)
    M.run_git(
        { "-C", details.repository, "show", ":" .. details.relative_path },
        details.repository,
        nil,
        function(result)
            if result.code ~= 0 then
                _P.get_head_lines(details, callback)

                return
            end

            callback(_split_lines(result.stdout), false)
        end
    )
end

--- Forget the cached index contents for the file shown by `buffer`.
---
---@param buffer integer The buffer whose index entry changed.
function M.invalidate_index_lines(buffer)
    buffer = _resolve_buffer(buffer)
    local cached = _DETAILS_CACHE[buffer]

    if not cached or not cached.details then
        return
    end

    local key = _get_index_key(cached.details)
    _INDEX_GENERATION[key] = (_INDEX_GENERATION[key] or 0) + 1
end

--- Get the index version of `path`, sharing cached and in-flight results.
---
---@param details _my.git_diff.FileDetails The file details to query.
---@param callback fun(lines: string[], missing: boolean): nil Callback with the index lines.
function M.get_index_lines(details, callback)
    local key = _get_index_key(details)
    local generation = _INDEX_GENERATION[key] or 0
    local cached = _INDEX_CACHE[key]

    if cached and cached.generation == generation then
        callback(cached.lines, cached.missing)

        return
    end

    local pending = _INDEX_PENDING[key]

    if pending and pending.generation == generation then
        table.insert(pending.callbacks, callback)

        return
    end

    pending = { generation = generation, callbacks = { callback } }
    _INDEX_PENDING[key] = pending

    _fetch_index_lines_uncached(details, function(lines, missing)
        if (_INDEX_GENERATION[key] or 0) == generation then
            _INDEX_CACHE[key] = { generation = generation, lines = lines, missing = missing }
        end

        if _INDEX_PENDING[key] == pending then
            _INDEX_PENDING[key] = nil
        end

        for _, waiting in ipairs(pending.callbacks) do
            waiting(lines, missing)
        end
    end)
end

--- Neovim renamed `vim.diff` to `vim.text.diff`. Prefer the newer name.
---
---@diagnostic disable-next-line: undefined-field, deprecated
local _diff = vim.text and vim.text.diff or vim.diff

--- Join lines into diff-ready text.
---
---@param lines string[] The lines to join.
---@return string # The text, always ending in a newline unless it is empty.
---
local function _join_diff_lines(lines)
    if #lines == 0 then
        return ""
    end

    return table.concat(lines, "\n") .. "\n"
end

--- Convert line changes into sign-friendly hunks.
---
--- Delegates to the native `vim.diff`/`vim.text.diff` (the same xdiff engine
--- `git` itself uses) instead of a hand-rolled LCS diff, since the LCS table is
--- O(#old_lines * #new_lines) and became a multi-second stall on large files.
---
--- `vim.diff`'s zero-count (pure add/delete) hunks anchor one line earlier than
--- this module's callers expect (real unified-diff convention anchors on the
--- line *before* the change; callers here anchor on the line *after*), so
--- zero-count sides get shifted by one to keep the existing anchor contract.
---
---@param old_lines string[] The original lines.
---@param new_lines string[] The changed lines.
---@return _my.git_diff.Hunk[] # The hunks.
---
function M.compute_hunks(old_lines, new_lines)
    old_lines = _normalize_hunk_lines(old_lines)
    new_lines = _normalize_hunk_lines(new_lines)

    local ok, raw_hunks =
        pcall(_diff, _join_diff_lines(old_lines), _join_diff_lines(new_lines), { result_type = "indices", ctxlen = 0 })

    if not ok or type(raw_hunks) ~= "table" then
        return {}
    end

    ---@type _my.git_diff.Hunk[]
    local hunks = {}

    for _, entry in ipairs(raw_hunks) do
        local old_start, old_count, new_start, new_count = entry[1], entry[2], entry[3], entry[4]

        if old_count == 0 then
            old_start = old_start + 1
        end

        if new_count == 0 then
            new_start = new_start + 1
        end

        local kind = "add"

        if old_count > 0 and new_count > 0 then
            kind = "change"
        elseif old_count > 0 then
            kind = "delete"
        end

        local line = new_start

        if line > #new_lines then
            line = math.max(#new_lines, 1)
        end

        ---@cast kind "add" | "change" | "delete"
        table.insert(hunks, {
            line = line,
            new_count = new_count,
            new_start = new_start,
            old_count = old_count,
            old_start = old_start,
            type = kind,
        })
    end

    return hunks
end

--- Check if `line` is inside an inclusive range.
---
---@param line integer The line to check.
---@param start_line integer The first allowed line.
---@param end_line integer The last allowed line.
---@return boolean # If `line` is in range, return `true`.
---
local function _is_line_selected(line, start_line, end_line)
    return start_line <= line and line <= end_line
end

--- Check whether a deletion-only hunk intersects the visual selection.
---
---@param hunk _my.git_diff.SelectionHunk The parsed deletion hunk.
---@param start_line integer The first selected target line.
---@param end_line integer The last selected target line.
---@return boolean # If `true`, the deleted lines are selected.
---
local function _is_deleted_hunk_selected(hunk, start_line, end_line)
    local before_anchor = math.max(hunk.new_start, 1)
    local after_anchor = math.max(hunk.new_start + 1, 1)

    return _is_line_selected(before_anchor, start_line, end_line)
        or _is_line_selected(after_anchor, start_line, end_line)
        or (start_line <= before_anchor and after_anchor <= end_line)
end

--- Split file text into lines and remember whether it ended in a newline.
---
---@param text string Some file contents.
---@return string[] # The file lines.
---@return boolean # If `true`, the original text ended in a newline.
---
function _P.split_git_text(text)
    local has_eol = text:sub(-1) == "\n"
    local body = has_eol and text:sub(1, -2) or text

    if body == "" then
        if has_eol then
            return { "" }, has_eol
        end

        return {}, has_eol
    end

    return vim.split(body, "\n", { plain = true }), has_eol
end

--- Join file lines back into text.
---
---@param lines string[] Some file contents without newline characters.
---@param has_eol boolean If `true`, add a final newline.
---@return string # The joined file text.
---
function _P.join_git_text(lines, has_eol)
    if #lines == 0 then
        return ""
    end

    local text = table.concat(lines, "\n")

    if has_eol then
        text = text .. "\n"
    end

    return text
end

--- Parse a zero-context unified diff into hunks.
---
---@param diff string The output from `git diff --unified=0`.
---@return _my.git_diff.SelectionHunk[] # The parsed hunks.
---
function M.parse_selection_diff(diff)
    ---@type _my.git_diff.SelectionHunk[]
    local hunks = {}
    ---@type _my.git_diff.SelectionHunk?
    local current = nil

    for line in diff:gmatch("[^\r\n]+") do
        local old_start, old_count, new_start, new_count = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

        if old_start and new_start then
            old_count = old_count == "" and "1" or old_count
            new_count = new_count == "" and "1" or new_count

            current = {
                added = {},
                new_count = tonumber(new_count) or 0,
                new_start = tonumber(new_start) or 0,
                old_count = tonumber(old_count) or 0,
                old_start = tonumber(old_start) or 0,
                removed = {},
            }
            table.insert(hunks, current)
        elseif current and line:sub(1, 1) == "-" then
            table.insert(current.removed, line:sub(2))
        elseif current and line:sub(1, 1) == "+" then
            table.insert(current.added, line:sub(2))
        end
    end

    return hunks
end

--- Build text containing only selected changes from `base_text` to `target_text`.
---
---@param base_text string The text to patch from.
---@param target_text string The text containing all candidate changes.
---@param diff string A zero-context diff from `base_text` to `target_text`.
---@param start_line integer The first selected target line.
---@param end_line integer The last selected target line.
---@param invert boolean? If `true`, keep unselected changes instead of selected changes.
---@return string # The partially-applied file text.
---@return integer # The number of selected changed lines.
---
function M.build_selection_target(base_text, target_text, diff, start_line, end_line, invert)
    invert = invert == true

    local base_lines, base_has_eol = _P.split_git_text(base_text)
    local _, target_has_eol = _P.split_git_text(target_text)
    local hunks = M.parse_selection_diff(diff)

    ---@type string[]
    local output = {}
    local old_cursor = 1
    local selected_changes = 0

    --- Copy base lines up to `stop`.
    ---
    ---@param stop integer The last base line to copy.
    local function _copy_base_until(stop)
        for index = old_cursor, stop do
            table.insert(output, base_lines[index])
        end
    end

    for _, hunk in ipairs(hunks) do
        if hunk.old_count == 0 then
            _copy_base_until(hunk.old_start)
            old_cursor = hunk.old_start + 1
        else
            _copy_base_until(hunk.old_start - 1)
            old_cursor = hunk.old_start + hunk.old_count
        end

        local max_count = math.max(hunk.old_count, hunk.new_count)

        for index = 1, max_count do
            local removed = hunk.removed[index]
            local added = hunk.added[index]

            if removed and added then
                local line = hunk.new_start + index - 1
                local selected = _is_line_selected(line, start_line, end_line)

                if selected then
                    selected_changes = selected_changes + 1
                end

                if selected ~= invert then
                    table.insert(output, added)
                else
                    table.insert(output, removed)
                end
            elseif added then
                local line = hunk.new_start + index - 1
                local selected = _is_line_selected(line, start_line, end_line)

                if selected then
                    selected_changes = selected_changes + 1
                end

                if selected ~= invert then
                    table.insert(output, added)
                end
            elseif removed then
                ---@type boolean
                local selected

                if hunk.new_count == 0 then
                    selected = _is_deleted_hunk_selected(hunk, start_line, end_line)
                else
                    local anchor = hunk.new_start + index - 1
                    selected = _is_line_selected(anchor, start_line, end_line)
                end

                if selected then
                    selected_changes = selected_changes + 1
                end

                if selected == invert then
                    table.insert(output, removed)
                end
            end
        end
    end

    _copy_base_until(#base_lines)

    local has_eol = selected_changes > 0 and target_has_eol or base_has_eol

    return _P.join_git_text(output, has_eol), selected_changes
end

--- Write `text` without using Vim's line-based writefile behavior.
---
---@param path string The path to write.
---@param text string The text to write into `path`.
---@return boolean # If `true`, the file was written.
---@return string? # The error message, if any.
---
function _P.write_text(path, text)
    local file, open_error = vim.uv.fs_open(path, "w", 438)

    if not file then
        return false, open_error
    end

    local ok, write_error = vim.uv.fs_write(file, text, 0)
    vim.uv.fs_close(file)

    return ok ~= nil, write_error
end

--- Quote a path for a Git patch header, if needed.
---
---@param path string A patch path, e.g. `a/foo.txt`.
---@return string # The quoted path.
---
local function _quote_patch_path(path)
    if not path:find('[%s"]') then
        return path
    end

    path = path:gsub("\\", "\\\\"):gsub('"', '\\"')

    return '"' .. path .. '"'
end

--- Get the hunks from a unified diff, without file headers.
---
---@param diff string The output from `git diff`.
---@return string? # The hunk text, if found.
---
local function _get_patch_hunks(diff)
    local start = diff:find("\n@@ ", 1, true)

    if start then
        return diff:sub(start + 1)
    end

    if diff:sub(1, 3) == "@@ " then
        return diff
    end

    return nil
end

--- Build a no-index diff from `base_text` to `target_text`.
---
---@param base_text string The text to patch from.
---@param target_text string The text to patch to.
---@param context integer The unified diff context line count.
---@param callback fun(diff: string?, message: string?): nil Callback with the diff or an error.
---
local function _build_no_index_diff(base_text, target_text, context, callback)
    local before = vim.fn.tempname()
    local after = vim.fn.tempname()
    local ok, message = _P.write_text(before, base_text)

    if ok then
        ok, message = _P.write_text(after, target_text)
    end

    if not ok then
        pcall(vim.uv.fs_unlink, before)
        pcall(vim.uv.fs_unlink, after)

        callback(nil, message)

        return
    end

    local success, start_error = pcall(function()
        vim.system({
            core_helpers.GIT_EXECUTABLE,
            "diff",
            "--no-index",
            "--unified=" .. context,
            "--no-color",
            "--",
            before,
            after,
        }, { text = true }, function(result)
            vim.schedule(function()
                pcall(vim.uv.fs_unlink, before)
                pcall(vim.uv.fs_unlink, after)

                if result.code ~= 0 and result.code ~= 1 then
                    callback(nil, result.stderr)

                    return
                end

                callback(result.stdout or "", nil)
            end)
        end)
    end)

    if not success then
        pcall(vim.uv.fs_unlink, before)
        pcall(vim.uv.fs_unlink, after)
        callback(nil, tostring(start_error))
    end
end

--- Generate a zero-context diff from `base_text` to `target_text`.
---
---@param base_text string The text to patch from.
---@param target_text string The text containing all candidate changes.
---@param callback fun(diff: string?, message: string?): nil Callback with the diff or an error.
function M.build_zero_context_diff(base_text, target_text, callback)
    _build_no_index_diff(base_text, target_text, 0, callback)
end

--- Create a Git patch from `base_text` to `target_text` for `relative_path`.
---
---@param base_text string The text to patch from.
---@param target_text string The text to patch to.
---@param relative_path string The repository-relative file path.
---@param callback fun(patch: string?, message: string?): nil Callback with the patch or an error.
function M.build_selection_patch(base_text, target_text, relative_path, callback)
    _build_no_index_diff(base_text, target_text, 3, function(diff, diff_error)
        if not diff then
            callback(nil, diff_error)

            return
        end

        local hunks = _get_patch_hunks(diff)

        if not hunks then
            callback(nil, "No patch hunks were generated.")

            return
        end

        relative_path = relative_path:gsub("\\", "/")

        local old_path = _quote_patch_path("a/" .. relative_path)
        local new_path = _quote_patch_path("b/" .. relative_path)
        local header = table.concat({
            string.format("diff --git %s %s", old_path, new_path),
            "--- " .. old_path,
            "+++ " .. new_path,
        }, "\n")

        callback(header .. "\n" .. hunks, nil)
    end)
end

--- Get a Git blob as text.
---
---@param details _my.git_diff.FileDetails The file details to use.
---@param object string The object name to read.
---@param callback fun(text: string?, message: string?): nil Callback with blob text or an error.
function M.get_blob_text(details, object, callback)
    M.run_git({ "-C", details.repository, "show", object }, details.repository, nil, function(result)
        if result.code ~= 0 then
            callback(nil, result.stderr)

            return
        end

        callback(result.stdout or "", nil)
    end)
end

--- Check if a path has unresolved merge entries.
---
---@param details _my.git_diff.FileDetails The file details to use.
---@param callback fun(has_unmerged: boolean): nil Callback with whether unmerged entries exist.
function M.has_unmerged_entries(details, callback)
    M.run_git(
        {
            "-C",
            details.repository,
            "ls-files",
            "-u",
            "--",
            details.relative_path,
        },
        details.repository,
        nil,
        function(result)
            callback(result.code == 0 and result.stdout ~= "")
        end
    )
end

--- Apply `patch` to the git index.
---
---@param details _my.git_diff.FileDetails The file details to use.
---@param patch string The patch to apply.
---@param callback fun(success: boolean, message: string?): nil Callback with whether the patch was applied.
---
function M.apply_cached_patch(details, patch, callback)
    if patch == "" then
        callback(false, "No selected git changes found.")

        return
    end

    local path = vim.fn.tempname()
    local ok, message = _P.write_text(path, patch)

    if not ok then
        pcall(vim.uv.fs_unlink, path)

        callback(false, message)

        return
    end

    M.run_git({ "-C", details.repository, "apply", "--cached", path }, details.repository, nil, function(result)
        pcall(vim.uv.fs_unlink, path)

        if result.code ~= 0 then
            callback(false, vim.trim(result.stderr))

            return
        end

        callback(true, nil)
    end)
end

return M
