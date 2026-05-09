--- Shared git diff helpers for buffer signs and hunk staging.

local core_helpers = require("modules.utilities.core_helpers")

local M = {}

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

local _CONTEXT_LINE_COUNT = 3

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
local function _join_lines(lines)
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
function M.run_git(arguments, directory, stdin)
    ---@type string[]
    local command = { core_helpers._GIT_EXECUTABLE }
    vim.list_extend(command, arguments)

    local result = vim.system(command, { cwd = directory, stdin = stdin, text = true }):wait()

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
    local repository = M.run_git({ "-C", directory, "rev-parse", "--show-toplevel" }, directory)

    if repository.code ~= 0 then
        return nil, "Current buffer is not inside a git repository."
    end

    local repository_path = vim.trim(repository.stdout)
    local relative =
        M.run_git({ "-C", repository_path, "ls-files", "--full-name", "--", absolute_path }, repository_path)
    local relative_path = vim.trim(relative.stdout)

    if relative_path == "" then
        local prefix = M.run_git({ "-C", repository_path, "rev-parse", "--show-prefix" }, repository_path)
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
function M.get_head_lines(details)
    local result = M.run_git({ "-C", details.repository, "show", "HEAD:" .. details.relative_path }, details.repository)

    if result.code ~= 0 then
        return {}, true
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
function M.compute_operations(old_lines, new_lines)
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
function M.get_change_groups(operations)
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
    local groups = M.get_change_groups(M.compute_operations(old_lines, new_lines))
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

--- Build lines that contain only selected buffer changes applied to HEAD.
---
---@param old_lines string[] The original lines.
---@param new_lines string[] The changed buffer lines.
---@param start_line integer The first selected buffer line.
---@param end_line integer The last selected buffer line.
---@return string[] # The partially-applied file lines.
---
function M.make_selected_lines(old_lines, new_lines, start_line, end_line)
    local groups = M.get_change_groups(M.compute_operations(old_lines, new_lines))
    ---@type string[]
    local output = {}
    local old_cursor = 1

    for _, group in ipairs(groups) do
        while old_cursor < group.old_start do
            table.insert(output, old_lines[old_cursor])
            old_cursor = old_cursor + 1
        end

        if group.old_count == 0 then
            for _, operation in ipairs(group.adds) do
                if operation.new_line and _is_line_selected(operation.new_line, start_line, end_line) then
                    table.insert(output, operation.text)
                end
            end
        elseif group.new_count == 0 then
            local anchor = math.max(1, group.new_start)

            if not _is_line_selected(anchor, start_line, end_line) then
                for _, operation in ipairs(group.deletes) do
                    table.insert(output, operation.text)
                end
            end
        else
            local count = math.max(#group.deletes, #group.adds)

            for index = 1, count do
                local delete = group.deletes[index]
                local add = group.adds[index]

                if add and add.new_line and _is_line_selected(add.new_line, start_line, end_line) then
                    table.insert(output, add.text)
                elseif delete then
                    table.insert(output, delete.text)
                end
            end
        end

        old_cursor = group.old_start + group.old_count
    end

    while old_cursor <= #old_lines do
        table.insert(output, old_lines[old_cursor])
        old_cursor = old_cursor + 1
    end

    return output
end

--- Get counts of old / new lines consumed before each operation.
---
---@param operations _my.git_diff.Operation[] The operations to inspect.
---@return integer[] # Old-line counts before each operation.
---@return integer[] # New-line counts before each operation.
---
local function _get_operation_offsets(operations)
    ---@type integer[]
    local old_offsets = {}
    ---@type integer[]
    local new_offsets = {}
    local old_count = 0
    local new_count = 0

    for index, operation in ipairs(operations) do
        old_offsets[index] = old_count
        new_offsets[index] = new_count

        if operation.type ~= "add" then
            old_count = old_count + 1
        end

        if operation.type ~= "delete" then
            new_count = new_count + 1
        end
    end

    return old_offsets, new_offsets
end

--- Build operation index ranges that should become unified hunks.
---
---@param operations _my.git_diff.Operation[] The operations to inspect.
---@return _my._datatypes.IntBounds[] # The operation index ranges.
---
local function _get_patch_ranges(operations)
    ---@type _my._datatypes.IntBounds[]
    local ranges = {}
    local index = 1

    while index <= #operations do
        if operations[index].type == "equal" then
            index = index + 1
        else
            local first = math.max(1, index - _CONTEXT_LINE_COUNT)

            while operations[index] and operations[index].type ~= "equal" do
                index = index + 1
            end

            local last = math.min(#operations, index + _CONTEXT_LINE_COUNT - 1)
            local previous = ranges[#ranges]

            if previous and first <= previous.last + 1 then
                previous.last = last
            else
                table.insert(ranges, { first = first, last = last })
            end
        end
    end

    return ranges
end

--- Convert a zero-or-more line count to a unified-diff starting line.
---
---@param offset integer The number of lines before a hunk.
---@param count integer The number of lines inside a hunk.
---@return integer # The unified diff starting line.
---
local function _make_patch_start(offset, count)
    if count == 0 then
        return offset
    end

    return offset + 1
end

--- Build one unified diff hunk.
---
---@param operations _my.git_diff.Operation[] The diff operations.
---@param old_offsets integer[] Old-line counts before each operation.
---@param new_offsets integer[] New-line counts before each operation.
---@param range _my._datatypes.IntBounds The operation range to render.
---@return string[] # The patch lines.
---
local function _make_patch_hunk(operations, old_offsets, new_offsets, range)
    local old_count = 0
    local new_count = 0
    ---@type string[]
    local lines = {}

    for index = range.first, range.last do
        local operation = operations[index]

        if operation.type == "equal" then
            old_count = old_count + 1
            new_count = new_count + 1
            table.insert(lines, " " .. operation.text)
        elseif operation.type == "delete" then
            old_count = old_count + 1
            table.insert(lines, "-" .. operation.text)
        else
            new_count = new_count + 1
            table.insert(lines, "+" .. operation.text)
        end
    end

    table.insert(
        lines,
        1,
        string.format(
            "@@ -%s,%s +%s,%s @@",
            _make_patch_start(old_offsets[range.first], old_count),
            old_count,
            _make_patch_start(new_offsets[range.first], new_count),
            new_count
        )
    )

    return lines
end

--- Build a patch from `old_lines` to `new_lines`.
---
---@param old_lines string[] The original lines.
---@param new_lines string[] The desired lines.
---@param relative_path string The repository-relative file path.
---@param is_new_file boolean If `true`, render a new-file patch.
---@return string # The unified patch.
---
function M.build_patch(old_lines, new_lines, relative_path, is_new_file)
    local operations = M.compute_operations(old_lines, new_lines)
    local ranges = _get_patch_ranges(operations)

    if #ranges == 0 then
        return ""
    end

    local old_offsets, new_offsets = _get_operation_offsets(operations)
    ---@type string[]
    local lines = {
        string.format("diff --git a/%s b/%s", relative_path, relative_path),
    }

    if is_new_file then
        table.insert(lines, "new file mode 100644")
        table.insert(lines, "--- /dev/null")
    else
        table.insert(lines, string.format("--- a/%s", relative_path))
    end

    table.insert(lines, string.format("+++ b/%s", relative_path))

    for _, range in ipairs(ranges) do
        vim.list_extend(lines, _make_patch_hunk(operations, old_offsets, new_offsets, range))
    end

    return _join_lines(lines)
end

--- Build a patch containing only selected changed lines.
---
---@param old_lines string[] The original lines.
---@param new_lines string[] The changed buffer lines.
---@param relative_path string The repository-relative file path.
---@param start_line integer The first selected buffer line.
---@param end_line integer The last selected buffer line.
---@param is_new_file boolean If `true`, render a new-file patch.
---@return string # The selected patch.
---
function M.build_selected_patch(old_lines, new_lines, relative_path, start_line, end_line, is_new_file)
    local selected_lines = M.make_selected_lines(old_lines, new_lines, start_line, end_line)

    return M.build_patch(old_lines, selected_lines, relative_path, is_new_file)
end

--- Apply `patch` to the git index.
---
---@param details _my.git_diff.FileDetails The file details to use.
---@param patch string The patch to apply.
---@param reverse boolean If `true`, apply the patch in reverse.
---@return boolean # If the patch was applied, return `true`.
---@return string? # An error message, if any.
---
function M.apply_cached_patch(details, patch, reverse)
    if patch == "" then
        return false, "No selected git changes found."
    end

    ---@type string[]
    local arguments = { "-C", details.repository, "apply", "--cached" }

    if reverse then
        table.insert(arguments, "--reverse")
    end

    table.insert(arguments, "-")

    local result = M.run_git(arguments, details.repository, patch)

    if result.code ~= 0 then
        return false, vim.trim(result.stderr)
    end

    return true, nil
end

return M
