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

---@class _my.git_diff.Operation
---@field type "add" | "delete" | "equal"
---@field old_line integer?
---@field new_line integer?
---@field text string

---@class _my.git_diff.Hunk
---@field type "add" | "change" | "delete"
---@field line integer
---@field old_start integer
---@field old_count integer
---@field new_start integer
---@field new_count integer

---@class _my.git_diff.ChangeGroup
---@field old_start integer
---@field old_count integer
---@field new_start integer
---@field new_count integer
---@field deletes _my.git_diff.Operation[]
---@field adds _my.git_diff.Operation[]

---@class _my.git_diff.SelectionHunk
---@field old_start integer
---@field old_count integer
---@field new_start integer
---@field new_count integer
---@field removed string[]
---@field added string[]

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

--- Join `lines` into a newline-terminated string.
---
---@param lines string[] Some lines to join.
---@return string # The joined text.
---
function _P.join_lines(lines)
    if #lines == 0 then
        return ""
    end

    return table.concat(lines, "\n") .. "\n"
end

--- Run a git command and wait for it to finish.
---
---@param arguments string[] Git arguments, without the leading executable.
---@param directory string The directory to run within.
---@param stdin string? Optional standard input.
---@return _my.git_diff.SystemResult # The command result.
---
function _P.run_git(arguments, directory, stdin)
    ---@type string[]
    local command = { core_helpers._GIT_EXECUTABLE }
    vim.list_extend(command, arguments)

    local success, result = pcall(function()
        return vim.system(command, { cwd = directory, stdin = stdin, text = true }):wait()
    end)

    if not success then
        return {
            code = 1,
            stderr = tostring(result),
            stdout = "",
        }
    end

    return {
        code = result.code or 1,
        stderr = result.stderr or "",
        stdout = result.stdout or "",
    }
end

--- Get git details for `buffer`.
---
---@param buffer integer The buffer to inspect.
---@return _my.git_diff.FileDetails? # The file details, if found.
---@return string? # An error message, if any.
---
function M.get_file_details(buffer)
    local absolute_path = vim.api.nvim_buf_get_name(buffer)

    if absolute_path == "" then
        return nil, "Current buffer has no file path."
    end

    local directory = vim.fs.dirname(absolute_path)

    if not directory or vim.fn.isdirectory(directory) == 0 then
        return nil, "Current buffer directory does not exist."
    end

    local repository = _P.run_git({ "-C", directory, "rev-parse", "--show-toplevel" }, directory)

    if repository.code ~= 0 then
        return nil, "Current buffer is not inside a git repository."
    end

    local repository_path = vim.trim(repository.stdout)
    local relative =
        _P.run_git({ "-C", repository_path, "ls-files", "--full-name", "--", absolute_path }, repository_path)
    local relative_path = vim.trim(relative.stdout)

    if relative_path == "" then
        local prefix = _P.run_git({ "-C", repository_path, "rev-parse", "--show-prefix" }, repository_path)
        local filename = vim.fs.basename(absolute_path)
        relative_path = vim.trim(prefix.stdout) .. filename
    end

    return {
        absolute_path = absolute_path,
        relative_path = relative_path,
        repository = repository_path,
    },
        nil
end

--- Get the HEAD version of `path`.
---
---@param details _my.git_diff.FileDetails The file details to query.
---@return string[] # The HEAD lines.
---@return boolean # If `true`, the file is not in HEAD yet.
---
function _P.get_head_lines(details)
    local result = _P.run_git(
        { "-C", details.repository, "show", "HEAD:" .. details.relative_path },
        details.repository
    )

    if result.code ~= 0 then
        return {}, true
    end

    return _split_lines(result.stdout), false
end

--- Get the index version of `path`.
---
---@param details _my.git_diff.FileDetails The file details to query.
---@return string[] # The index lines.
---@return boolean # If `true`, the file is not in the index yet.
---
function M.get_index_lines(details)
    local result = _P.run_git({ "-C", details.repository, "show", ":" .. details.relative_path }, details.repository)

    if result.code ~= 0 then
        return _P.get_head_lines(details)
    end

    return _split_lines(result.stdout), false
end

--- Build a dynamic-programming table for longest common subsequence.
---
---@param old_lines string[] The old file lines.
---@param new_lines string[] The new file lines.
---@return integer[][] # The LCS table.
---
local function _make_lcs_table(old_lines, new_lines)
    ---@type integer[][]
    local table_ = {}

    for old_index = 0, #old_lines do
        table_[old_index] = {}

        for new_index = 0, #new_lines do
            table_[old_index][new_index] = 0
        end
    end

    for old_index = #old_lines - 1, 0, -1 do
        for new_index = #new_lines - 1, 0, -1 do
            if old_lines[old_index + 1] == new_lines[new_index + 1] then
                table_[old_index][new_index] = table_[old_index + 1][new_index + 1] + 1
            else
                table_[old_index][new_index] =
                    math.max(table_[old_index + 1][new_index], table_[old_index][new_index + 1])
            end
        end
    end

    return table_
end

--- Compute line-level diff operations from `old_lines` to `new_lines`.
---
---@param old_lines string[] The original lines.
---@param new_lines string[] The changed lines.
---@return _my.git_diff.Operation[] # The diff operations.
---
function _P.compute_operations(old_lines, new_lines)
    local table_ = _make_lcs_table(old_lines, new_lines)
    local old_index = 1
    local new_index = 1
    ---@type _my.git_diff.Operation[]
    local operations = {}

    while old_index <= #old_lines and new_index <= #new_lines do
        if old_lines[old_index] == new_lines[new_index] then
            table.insert(operations, {
                old_line = old_index,
                new_line = new_index,
                text = old_lines[old_index],
                type = "equal",
            })
            old_index = old_index + 1
            new_index = new_index + 1
        elseif table_[old_index][new_index - 1] >= table_[old_index - 1][new_index] then
            table.insert(operations, {
                old_line = old_index,
                text = old_lines[old_index],
                type = "delete",
            })
            old_index = old_index + 1
        else
            table.insert(operations, {
                new_line = new_index,
                text = new_lines[new_index],
                type = "add",
            })
            new_index = new_index + 1
        end
    end

    while old_index <= #old_lines do
        table.insert(operations, {
            old_line = old_index,
            text = old_lines[old_index],
            type = "delete",
        })
        old_index = old_index + 1
    end

    while new_index <= #new_lines do
        table.insert(operations, {
            new_line = new_index,
            text = new_lines[new_index],
            type = "add",
        })
        new_index = new_index + 1
    end

    return operations
end

--- Group adjacent changed operations together.
---
---@param operations _my.git_diff.Operation[] The operations to group.
---@return _my.git_diff.ChangeGroup[] # The changed groups.
---
function _P.get_change_groups(operations)
    ---@type _my.git_diff.ChangeGroup[]
    local groups = {}
    local index = 1
    local old_cursor = 1
    local new_cursor = 1

    while index <= #operations do
        local operation = operations[index]

        if operation.type == "equal" then
            old_cursor = old_cursor + 1
            new_cursor = new_cursor + 1
            index = index + 1
        else
            local old_start = old_cursor
            local new_start = new_cursor
            ---@type _my.git_diff.Operation[]
            local deletes = {}
            ---@type _my.git_diff.Operation[]
            local adds = {}

            while operations[index] and operations[index].type ~= "equal" do
                local changed = operations[index]

                if changed.type == "delete" then
                    table.insert(deletes, changed)
                    old_cursor = old_cursor + 1
                else
                    table.insert(adds, changed)
                    new_cursor = new_cursor + 1
                end

                index = index + 1
            end

            table.insert(groups, {
                adds = adds,
                deletes = deletes,
                new_count = #adds,
                new_start = new_start,
                old_count = #deletes,
                old_start = old_start,
            })
        end
    end

    return groups
end

--- Convert line changes into sign-friendly hunks.
---
---@param old_lines string[] The original lines.
---@param new_lines string[] The changed lines.
---@return _my.git_diff.Hunk[] # The hunks.
---
function M.compute_hunks(old_lines, new_lines)
    local groups = _P.get_change_groups(_P.compute_operations(old_lines, new_lines))
    ---@type _my.git_diff.Hunk[]
    local hunks = {}

    for _, group in ipairs(groups) do
        local kind = "add"

        if group.old_count > 0 and group.new_count > 0 then
            kind = "change"
        elseif group.old_count > 0 then
            kind = "delete"
        end

        local line = group.new_start

        if line > #new_lines then
            line = math.max(#new_lines, 1)
        end

        ---@cast kind "add" | "change" | "delete"
        table.insert(hunks, {
            line = line,
            new_count = group.new_count,
            new_start = group.new_start,
            old_count = group.old_count,
            old_start = group.old_start,
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
function _P.parse_selection_diff(diff)
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

--- Parse a zero-context unified diff into hunks.
---
---@param diff string The output from `git diff --unified=0`.
---@return _my.git_diff.SelectionHunk[] # The parsed hunks.
function M.parse_selection_diff(diff)
    return _P.parse_selection_diff(diff)
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
    local hunks = _P.parse_selection_diff(diff)

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

--- Build lines that contain only selected buffer changes applied to HEAD.
---
---@param old_lines string[] The original lines.
---@param new_lines string[] The changed buffer lines.
---@param start_line integer The first selected buffer line.
---@param end_line integer The last selected buffer line.
---@return string[] # The partially-applied file lines.
---
function _P.make_selected_lines(old_lines, new_lines, start_line, end_line)
    local base_text = _P.join_lines(old_lines)
    local target_text = _P.join_lines(new_lines)
    local diff = M.build_zero_context_diff(base_text, target_text)
    local partial_text = M.build_selection_target(base_text, target_text, diff or "", start_line, end_line)

    return _split_lines(partial_text)
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
    if not path:find("[%s\"]") then
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
---@return string? # The diff, if generated.
---@return string? # An error message, if any.
---
local function _build_no_index_diff(base_text, target_text, context)
    local before = vim.fn.tempname()
    local after = vim.fn.tempname()
    local ok, message = _P.write_text(before, base_text)

    if ok then
        ok, message = _P.write_text(after, target_text)
    end

    if not ok then
        pcall(vim.uv.fs_unlink, before)
        pcall(vim.uv.fs_unlink, after)

        return nil, message
    end

    local result = vim.system(
        {
            core_helpers._GIT_EXECUTABLE,
            "diff",
            "--no-index",
            "--unified=" .. context,
            "--no-color",
            "--",
            before,
            after,
        },
        { text = true }
    ):wait()

    pcall(vim.uv.fs_unlink, before)
    pcall(vim.uv.fs_unlink, after)

    if result.code ~= 0 and result.code ~= 1 then
        return nil, result.stderr
    end

    return result.stdout or "", nil
end

--- Generate a zero-context diff from `base_text` to `target_text`.
---
---@param base_text string The text to patch from.
---@param target_text string The text containing all candidate changes.
---@return string? # The diff, if generated.
---@return string? # An error message, if any.
---
function M.build_zero_context_diff(base_text, target_text)
    return _build_no_index_diff(base_text, target_text, 0)
end

--- Create a Git patch from `base_text` to `target_text` for `relative_path`.
---
---@param base_text string The text to patch from.
---@param target_text string The text to patch to.
---@param relative_path string The repository-relative file path.
---@return string? # The patch, if generated.
---@return string? # An error message, if any.
---
function M.build_selection_patch(base_text, target_text, relative_path)
    local diff, diff_error = _build_no_index_diff(base_text, target_text, 3)

    if not diff then
        return nil, diff_error
    end

    local hunks = _get_patch_hunks(diff)

    if not hunks then
        return nil, "No patch hunks were generated."
    end

    relative_path = relative_path:gsub("\\", "/")

    local old_path = _quote_patch_path("a/" .. relative_path)
    local new_path = _quote_patch_path("b/" .. relative_path)
    local header = table.concat({
        string.format("diff --git %s %s", old_path, new_path),
        "--- " .. old_path,
        "+++ " .. new_path,
    }, "\n")

    return header .. "\n" .. hunks, nil
end

--- Get a Git blob as text.
---
---@param details _my.git_diff.FileDetails The file details to use.
---@param object string The object name to read.
---@return string? # The blob text, if found.
---@return string? # An error message, if any.
---
function M.get_blob_text(details, object)
    local result = _P.run_git({ "-C", details.repository, "show", object }, details.repository)

    if result.code ~= 0 then
        return nil, result.stderr
    end

    return result.stdout or "", nil
end

--- Check if a path has unresolved merge entries.
---
---@param details _my.git_diff.FileDetails The file details to use.
---@return boolean # If `true`, unmerged entries exist.
---
function M.has_unmerged_entries(details)
    local result = _P.run_git(
        { "-C", details.repository, "ls-files", "-u", "--", details.relative_path },
        details.repository
    )

    return result.code == 0 and result.stdout ~= ""
end

--- Apply `patch` to the git index.
---
---@param details _my.git_diff.FileDetails The file details to use.
---@param patch string The patch to apply.
---@return boolean # If the patch was applied, return `true`.
---@return string? # An error message, if any.
---
function M.apply_cached_patch(details, patch)
    if patch == "" then
        return false, "No selected git changes found."
    end

    local path = vim.fn.tempname()
    local ok, message = _P.write_text(path, patch)

    if not ok then
        pcall(vim.uv.fs_unlink, path)

        return false, message
    end

    local check = _P.run_git({ "-C", details.repository, "apply", "--cached", "--check", path }, details.repository)

    if check.code ~= 0 then
        pcall(vim.uv.fs_unlink, path)

        return false, vim.trim(check.stderr)
    end

    local result = _P.run_git({ "-C", details.repository, "apply", "--cached", path }, details.repository)
    pcall(vim.uv.fs_unlink, path)

    if result.code ~= 0 then
        return false, vim.trim(result.stderr)
    end

    return true, nil
end

return M
