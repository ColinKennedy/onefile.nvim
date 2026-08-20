--- Stage and unstage visual selections from unsaved buffer edits.

local _P = {}

--- Get all current buffer text as a single string.
---
---@param buffer integer The Vim buffer to inspect.
---@return string # The buffer text.
---
local function _get_buffer_text(buffer)
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    local text = table.concat(lines, "\n")

    if vim.bo[buffer].endofline then
        text = text .. "\n"
    end

    return text
end

--- Replace all text in `buffer` with exact file `text`.
---
--- Only the changed line span is written so signs, extmarks, and folds on the
--- untouched lines survive. A whole-buffer replacement would drop every git
--- gutter sign until the next async refresh, which makes `signcolumn=auto`
--- collapse and re-expand.
---
---@param buffer integer The Vim buffer to modify.
---@param text string The full text to place into the buffer.
local function _set_buffer_text(buffer, text)
    local has_eol = text:sub(-1) == "\n"
    local body = has_eol and text:sub(1, -2) or text
    ---@type string[]
    local lines = {}

    if body ~= "" then
        lines = vim.split(body, "\n", { plain = true })
    end

    local current = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    local prefix = 0

    while prefix < #current and prefix < #lines and current[prefix + 1] == lines[prefix + 1] do
        prefix = prefix + 1
    end

    local suffix = 0

    while
        suffix < #current - prefix
        and suffix < #lines - prefix
        and current[#current - suffix] == lines[#lines - suffix]
    do
        suffix = suffix + 1
    end

    if prefix ~= #current or prefix ~= #lines then
        vim.api.nvim_buf_set_lines(
            buffer,
            prefix,
            #current - suffix,
            false,
            vim.list_slice(lines, prefix + 1, #lines - suffix)
        )
    end

    vim.bo[buffer].endofline = has_eol
end

--- Notify the user about a git hunk operation failure.
---
---@param message string The failure message to show.
local function _notify_error(message)
    vim.notify(message, vim.log.levels.ERROR)
end

--- Refresh Git-dependent UI after an index mutation.
---
---@param buffer integer The buffer that changed.
local function _refresh_git_views(buffer)
    require("modules.features.git_gutter").update(buffer)
    require("modules.features.git_hunk_navigation").mark_stale_for_buffer(buffer)
end

---@class _my.git_hunks.RangeCommandOptions
---@field line1 integer The first command range line.
---@field line2 integer The last command range line.

---@class _my.git_hunks.ActionDetails
---@field base_text string The text to patch from.
---@field target_text string The text containing all candidate changes.
---@field details _my.git_diff.FileDetails The Git file details.
---@field success_message string The user-facing success message.

---@alias _my.git_hunks.Action "stage" | "reset" | "checkout"

--- Get action-specific texts for a hunk operation.
---
---@param action _my.git_hunks.Action The hunk operation to run.
---@param buffer integer The Vim buffer to inspect.
---@param details _my.git_diff.FileDetails The Git file details.
---@param callback fun(data: _my.git_hunks.ActionDetails?): nil Callback with the resolved action details.
local function _get_action_details(action, buffer, details, callback)
    local git_diff = require("modules.utilities.git_diff")

    if action == "stage" or action == "checkout" then
        git_diff.get_blob_text(details, ":" .. details.relative_path, function(base_text, show_error)
            if not base_text then
                _notify_error(
                    string.format("Cannot stage selected hunks for an untracked or non-text file: %s", show_error or "")
                )

                callback(nil)

                return
            end

            local target_text = _get_buffer_text(buffer)

            if base_text:find("\0", 1, true) or target_text:find("\0", 1, true) then
                _notify_error("Cannot use Git hunk selection on binary files.")

                callback(nil)

                return
            end

            callback({
                base_text = base_text,
                details = details,
                success_message = action == "stage" and "Staged selected Git hunk lines."
                    or "Checked out selected Git hunk lines.",
                target_text = target_text,
            })
        end)

        return
    end

    git_diff.get_blob_text(details, "HEAD:" .. details.relative_path, function(base_text, base_error)
        git_diff.get_blob_text(details, ":" .. details.relative_path, function(target_text, target_error)
            if not base_text or not target_text then
                _notify_error(
                    string.format(
                        "Cannot reset selected hunks for this file: %s%s",
                        base_error or "",
                        target_error or ""
                    )
                )

                callback(nil)

                return
            end

            if base_text:find("\0", 1, true) or target_text:find("\0", 1, true) then
                _notify_error("Cannot use Git hunk selection on binary files.")

                callback(nil)

                return
            end

            callback({
                base_text = base_text,
                details = details,
                success_message = "Reset selected Git hunk lines from the index.",
                target_text = target_text,
            })
        end)
    end)
end

---@class _my.git_hunks.ApplyOptions
---@field callback fun(success: boolean, message: string?): nil? Called once the action finishes.
---@field quiet boolean? If `true`, report nothing. The caller summarizes instead.

--- Run a hunk operation using already-resolved texts and range.
---
---@param action _my.git_hunks.Action The hunk operation to run.
---@param buffer integer The Vim buffer to inspect.
---@param data _my.git_hunks.ActionDetails The resolved action details.
---@param diff string A zero-context diff for the operation.
---@param start_line integer The first selected line.
---@param end_line integer The last selected line.
---@param options _my.git_hunks.ApplyOptions? Completion and reporting options.
local function _apply_selection_from_details(action, buffer, data, diff, start_line, end_line, options)
    local git_diff = require("modules.utilities.git_diff")

    options = options or {}
    local callback = options.callback or function() end

    --- Show `message` unless the caller reports failures itself.
    ---
    ---@param message string The failure message to show.
    local function _report_error(message)
        if not options.quiet then
            _notify_error(message)
        end
    end

    --- Show the action's success message unless the caller summarizes instead.
    local function _report_success()
        if not options.quiet then
            vim.notify(data.success_message, vim.log.levels.INFO)
        end
    end

    local partial_text, selected_changes =
        git_diff.build_selection_target(data.base_text, data.target_text, diff, start_line, end_line, action == "reset")

    if selected_changes == 0 then
        if not options.quiet then
            vim.notify("No Git hunk lines were selected.", vim.log.levels.INFO)
        end

        callback(false, "no Git hunk lines were selected")

        return
    end

    if action == "checkout" then
        local checkout_text =
            git_diff.build_selection_target(data.base_text, data.target_text, diff, start_line, end_line, true)

        _set_buffer_text(buffer, checkout_text)
        _report_success()
        _refresh_git_views(buffer)
        callback(true, nil)

        return
    end

    local patch_base_text = action == "reset" and data.target_text or data.base_text
    git_diff.build_selection_patch(
        patch_base_text,
        partial_text,
        data.details.relative_path,
        function(patch, patch_error)
            if not patch then
                _report_error(string.format("Cannot create selected Git hunk patch: %s", patch_error or ""))
                callback(false, patch_error)

                return
            end

            git_diff.apply_cached_patch(data.details, patch, function(success, apply_error)
                if not success then
                    _report_error(string.format("Cannot apply selected Git hunk patch: %s", apply_error or ""))
                    callback(false, apply_error)

                    return
                end

                _report_success()
                _refresh_git_views(buffer)
                callback(true, nil)
            end)
        end
    )
end

--- Get the Git index file mode for `details`.
---
---@param details _my.git_diff.FileDetails The Git file details.
---@param callback fun(mode: string): nil Callback with the index mode to use.
local function _get_index_mode(details, callback)
    local git_diff = require("modules.utilities.git_diff")

    git_diff.run_git(
        { "-C", details.repository, "ls-files", "-s", "--", details.relative_path },
        details.repository,
        nil,
        function(result)
            callback(result.stdout:match("^(%d+)%s") or "100644")
        end
    )
end

--- Stage exact text into the index for `details`.
---
---@param details _my.git_diff.FileDetails The Git file details.
---@param text string The text to stage.
---@param callback fun(success: boolean, message: string?): nil
---    Callback with whether the text was staged.
local function _stage_text(details, text, callback)
    local git_diff = require("modules.utilities.git_diff")

    git_diff.run_git(
        { "-C", details.repository, "hash-object", "-w", "--stdin" },
        details.repository,
        text,
        function(object)
            if object.code ~= 0 then
                callback(false, vim.trim(object.stderr))

                return
            end

            local object_id = vim.trim(object.stdout)

            _get_index_mode(details, function(mode)
                git_diff.run_git(
                    {
                        "-C",
                        details.repository,
                        "update-index",
                        "--add",
                        "--cacheinfo",
                        mode,
                        object_id,
                        details.relative_path,
                    },
                    details.repository,
                    nil,
                    function(result)
                        if result.code ~= 0 then
                            callback(false, vim.trim(result.stderr))

                            return
                        end

                        callback(true, nil)
                    end
                )
            end)
        end
    )
end

--- Run a whole-file Git hunk action for the current buffer.
---
---@param action "stage" | "reset" The whole-file operation to run.
function _P.apply_current_file(action)
    local git_diff = require("modules.utilities.git_diff")

    local buffer = vim.api.nvim_get_current_buf()
    git_diff.get_file_details(buffer, function(details, details_error)
        if not details then
            _notify_error(details_error or "Cannot find git details for current buffer.")

            return
        end

        git_diff.has_unmerged_entries(details, function(has_unmerged)
            if has_unmerged and action == "reset" then
                _notify_error("Cannot reset a file with unresolved merge entries.")

                return
            end

            --- Finish the whole-file action.
            ---
            ---@param success boolean If `true`, the action succeeded.
            ---@param message string? The error message, if any.
            local function _finish(success, message)
                if not success then
                    _notify_error(string.format("Cannot %s current Git file: %s", action, message or ""))

                    return
                end

                if action == "stage" then
                    vim.notify("Staged current Git file.", vim.log.levels.INFO)
                else
                    vim.notify("Reset current Git file from the index.", vim.log.levels.INFO)
                end

                _refresh_git_views(buffer)
            end

            if action == "stage" then
                _stage_text(details, _get_buffer_text(buffer), _finish)

                return
            end

            git_diff.run_git(
                { "-C", details.repository, "reset", "--", details.relative_path },
                details.repository,
                nil,
                function(result)
                    _finish(result.code == 0, vim.trim(result.stderr))
                end
            )
        end)
    end)
end

--- Run a visual Git hunk action for selected lines.
---
---@param action _my.git_hunks.Action The hunk operation to run.
---@param start_line integer The first selected line.
---@param end_line integer The last selected line.
function _P.apply_selection(action, start_line, end_line)
    local git_diff = require("modules.utilities.git_diff")

    if start_line > end_line then
        start_line, end_line = end_line, start_line
    end

    local buffer = vim.api.nvim_get_current_buf()
    git_diff.get_file_details(buffer, function(details, details_error)
        if not details then
            _notify_error(details_error or "Cannot find git details for current buffer.")

            return
        end

        git_diff.has_unmerged_entries(details, function(has_unmerged)
            if has_unmerged then
                _notify_error("Cannot use Git hunk selection on a file with unresolved merge entries.")

                return
            end

            _get_action_details(action, buffer, details, function(data)
                if not data then
                    return
                end

                git_diff.build_zero_context_diff(data.base_text, data.target_text, function(diff, diff_error)
                    if not diff then
                        _notify_error(string.format("Cannot calculate selected Git hunks: %s", diff_error or ""))

                        return
                    end

                    _apply_selection_from_details(action, buffer, data, diff, start_line, end_line)
                end)
            end)
        end)
    end)
end

--- Get the target line range that selects all changes in `hunk`.
---
---@param hunk _my.git_diff.SelectionHunk The hunk to select.
---@return integer # The first hunk line.
---@return integer # The last hunk line.
local function _get_hunk_line_range(hunk)
    if hunk.new_count == 0 then
        local first = math.max(hunk.new_start, 1)

        return first, math.max(first, hunk.new_start + 1)
    end

    local first = math.max(hunk.new_start, 1)
    local size = math.max(hunk.old_count, hunk.new_count)

    return first, first + size - 1
end

--- Calculate the distance from `line` to `hunk`.
---
---@param hunk _my.git_diff.SelectionHunk The hunk to compare.
---@param line integer The current cursor line.
---@return integer # The distance from the cursor to the hunk.
local function _get_hunk_distance(hunk, line)
    local first, last = _get_hunk_line_range(hunk)

    if first <= line and line <= last then
        return 0
    end

    if line < first then
        return first - line
    end

    return line - last
end

--- Find the closest hunk to `line`.
---
---@param hunks _my.git_diff.SelectionHunk[] The available hunks.
---@param line integer The current cursor line.
---@return _my.git_diff.SelectionHunk? # The closest hunk, if any.
local function _find_closest_hunk(hunks, line)
    ---@type _my.git_diff.SelectionHunk?
    local closest
    local closest_distance = math.huge

    for _, hunk in ipairs(hunks) do
        local distance = _get_hunk_distance(hunk, line)

        if distance < closest_distance then
            closest = hunk
            closest_distance = distance
        end
    end

    return closest
end

--- Find the hunk that covers `line`.
---
--- A quickfix row names one exact hunk, so this requires containment instead of
--- the nearest-hunk search that cursor-driven staging uses. A row whose hunk is
--- gone (already staged, or the file moved on since `:LoadGitDiff` ran) is
--- reported rather than silently staging a neighbouring hunk.
---
---@param hunks _my.git_diff.SelectionHunk[] The available hunks.
---@param line integer The quickfix entry line.
---@return _my.git_diff.SelectionHunk? # The covering hunk, if any.
local function _find_containing_hunk(hunks, line)
    for _, hunk in ipairs(hunks) do
        local first, last = _get_hunk_line_range(hunk)

        if first <= line and line <= last then
            return hunk
        end
    end

    return nil
end

--- Check whether the current buffer lists quickfix entries.
---
---@return boolean # If `true`, the current buffer is a quickfix or location list.
function _P.is_quickfix_buffer()
    return vim.bo.buftype == "quickfix"
end

--- Check whether `window` shows a location list rather than the quickfix list.
---
--- Location lists share the `quickfix` buftype but hold their own entries, so
--- the window decides which list to read and write.
---
---@param window integer The window to inspect.
---@return boolean # If `true`, `window` shows a location list.
local function _is_location_list(window)
    local info = vim.fn.getwininfo(window)[1]

    return info ~= nil and info.loclist == 1
end

--- Get the entries listed in `window`.
---
---@param window integer The window to read from.
---@param is_loclist boolean If `true`, read that window's location list.
---@return vim.quickfix.entry[] # The listed entries.
local function _get_quickfix_items(window, is_loclist)
    if is_loclist then
        return vim.fn.getloclist(window)
    end

    return vim.fn.getqflist()
end

---@class _my.git_hunks.QuickfixTarget
---@field buffer integer The buffer holding the hunk.
---@field lnum integer The hunk's line within that buffer.
---@field rows integer[] The list rows that named this hunk.

--- Collect the unique hunks named by a range of quickfix rows.
---
---@param window integer The window holding the list.
---@param is_loclist boolean If `true`, read that window's location list.
---@param start_row integer The first selected quickfix row.
---@param end_row integer The last selected quickfix row.
---@return _my.git_hunks.QuickfixTarget[] # The referenced hunks, highest line first per file.
local function _get_quickfix_targets(window, is_loclist, start_row, end_row)
    if start_row > end_row then
        start_row, end_row = end_row, start_row
    end

    local items = _get_quickfix_items(window, is_loclist)
    ---@type _my.git_hunks.QuickfixTarget[]
    local targets = {}
    ---@type table<string, _my.git_hunks.QuickfixTarget>
    local seen = {}

    for row = start_row, end_row do
        local item = items[row]

        if item and item.bufnr and item.bufnr ~= 0 and item.lnum and item.lnum > 0 then
            local key = string.format("%s:%s", item.bufnr, item.lnum)
            local target = seen[key]

            if not target then
                target = { buffer = item.bufnr, lnum = item.lnum, rows = {} }
                seen[key] = target
                table.insert(targets, target)
            end

            table.insert(target.rows, row)
        end
    end

    -- NOTE: Checking out a hunk rewrites the buffer, which shifts every line
    -- below it. Taking the highest line in each file first keeps the recorded
    -- lines of the hunks still queued for that file correct. Staging and
    -- resetting never touch the buffer, so the order is harmless for them.
    table.sort(targets, function(left, right)
        if left.buffer ~= right.buffer then
            return left.buffer < right.buffer
        end

        return left.lnum > right.lnum
    end)

    return targets
end

--- Drop entries naming `removed` hunks from the list shown in `window`.
---
--- Rows are matched by their position in the list, not by buffer and line.
--- Neovim tracks the entries of a loaded buffer with extmarks, so checking out
--- one hunk shifts the recorded lines of that file's remaining rows and they no
--- longer match the lines that `_get_quickfix_targets` captured.
---
--- CAVEAT: Only the checked-out rows are dropped. A file whose buffer is not
--- loaded gets no extmark tracking, so the rows still listing its other hunks
--- keep their original line numbers and will be stale until `:LoadGitDiff`
--- rebuilds the list.
---
---@param window integer The window holding the list.
---@param is_loclist boolean If `true`, rewrite that window's location list.
---@param removed _my.git_hunks.QuickfixTarget[] The hunks that no longer exist.
local function _remove_quickfix_entries(window, is_loclist, removed)
    if #removed == 0 or not vim.api.nvim_win_is_valid(window) then
        return
    end

    ---@type table<integer, boolean>
    local dropped = {}

    for _, target in ipairs(removed) do
        for _, row in ipairs(target.rows) do
            dropped[row] = true
        end
    end

    local items = _get_quickfix_items(window, is_loclist)
    ---@type vim.quickfix.entry[]
    local kept = {}

    for row, item in ipairs(items) do
        if not dropped[row] then
            table.insert(kept, item)
        end
    end

    if #kept == #items then
        return
    end

    -- NOTE: Replacing the items would otherwise discard the repository title
    -- that `:LoadGitDiff` set.
    local title = is_loclist and vim.fn.getloclist(window, { title = 0 }).title or vim.fn.getqflist({ title = 0 }).title

    if is_loclist then
        vim.fn.setloclist(window, {}, "r", { items = kept, title = title })

        return
    end

    vim.fn.setqflist({}, "r", { items = kept, title = title })
end

--- Run `action` on the single hunk that `target` names.
---
---@param action _my.git_hunks.Action The hunk operation to run.
---@param target _my.git_hunks.QuickfixTarget The quickfix row to act on.
---@param callback fun(success: boolean, message: string?): nil Callback once the hunk is handled.
local function _apply_quickfix_target(action, target, callback)
    local git_diff = require("modules.utilities.git_diff")
    local buffer = target.buffer

    if not vim.api.nvim_buf_is_valid(buffer) then
        callback(false, "a quickfix entry buffer no longer exists")

        return
    end

    -- NOTE: `:LoadGitDiff` names quickfix buffers without loading them, so the
    -- file contents have to be read in before they can be diffed against the
    -- index. Reading them would otherwise echo a "5L, 24B" message per file.
    require("modules.utilities.core_helpers").with_file_messages_suppressed(function()
        vim.fn.bufload(buffer)
    end)

    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer), ":~:.")

    git_diff.get_file_details(buffer, function(details, details_error)
        if not details then
            callback(false, details_error or string.format("no Git details for %s", name))

            return
        end

        git_diff.has_unmerged_entries(details, function(has_unmerged)
            if has_unmerged then
                callback(false, string.format("%s has unresolved merge entries", details.relative_path))

                return
            end

            _get_action_details(action, buffer, details, function(data)
                if not data then
                    callback(false, string.format("cannot read Git contents for %s", details.relative_path))

                    return
                end

                git_diff.build_zero_context_diff(data.base_text, data.target_text, function(diff, diff_error)
                    if not diff then
                        callback(false, diff_error or string.format("cannot diff %s", details.relative_path))

                        return
                    end

                    local hunk = _find_containing_hunk(git_diff.parse_selection_diff(diff), target.lnum)

                    if not hunk then
                        callback(
                            false,
                            string.format("%s:%s is no longer a Git hunk", details.relative_path, target.lnum)
                        )

                        return
                    end

                    local start_line, end_line = _get_hunk_line_range(hunk)
                    _apply_selection_from_details(action, buffer, data, diff, start_line, end_line, {
                        callback = callback,
                        quiet = true,
                    })
                end)
            end)
        end)
    end)
end

---@type table<_my.git_hunks.Action, string>
local _ACTION_LABELS = {
    checkout = "Checked out",
    reset = "Reset",
    stage = "Staged",
}

--- Run `action` on every hunk listed across a range of quickfix rows.
---
--- Hunks are handled strictly one at a time. Each one re-reads the index, so
--- applying a hunk cannot invalidate the hunks queued behind it, and several
--- hunks in the same file apply correctly. Running them concurrently would race
--- on the index instead.
---
---@param action _my.git_hunks.Action The hunk operation to run.
---@param start_row integer The first selected quickfix row.
---@param end_row integer The last selected quickfix row.
function _P.apply_quickfix_selection(action, start_row, end_row)
    local window = vim.api.nvim_get_current_win()
    local is_loclist = _is_location_list(window)
    local targets = _get_quickfix_targets(window, is_loclist, start_row, end_row)

    if #targets == 0 then
        vim.notify("No Git hunks were selected.", vim.log.levels.INFO)

        return
    end

    local index = 1
    ---@type _my.git_hunks.QuickfixTarget[]
    local applied = {}
    ---@type string[]
    local failures = {}

    --- Handle the next selected hunk, then report once all of them are done.
    local function _next()
        local target = targets[index]
        index = index + 1

        if not target then
            if #applied > 0 then
                -- NOTE: Only a checkout takes the hunk back out of the buffer.
                -- Staged and reset hunks are still present, so their rows stay.
                if action == "checkout" then
                    _remove_quickfix_entries(window, is_loclist, applied)
                end

                vim.notify(
                    string.format("%s %s of %s selected Git hunks.", _ACTION_LABELS[action], #applied, #targets),
                    vim.log.levels.INFO
                )
            end

            if #failures > 0 then
                _notify_error(
                    string.format("Skipped %s selected Git hunks: %s", #failures, table.concat(failures, ", "))
                )
            end

            return
        end

        _apply_quickfix_target(action, target, function(success, message)
            if success then
                table.insert(applied, target)
            else
                table.insert(failures, message or "unknown error")
            end

            _next()
        end)
    end

    _next()
end

--- Run a visual Git hunk action for the closest hunk.
---
---@param action _my.git_hunks.Action The hunk operation to run.
function _P.apply_closest_hunk(action)
    local git_diff = require("modules.utilities.git_diff")

    local buffer = vim.api.nvim_get_current_buf()
    git_diff.get_file_details(buffer, function(details, details_error)
        if not details then
            _notify_error(details_error or "Cannot find git details for current buffer.")

            return
        end

        git_diff.has_unmerged_entries(details, function(has_unmerged)
            if has_unmerged then
                _notify_error("Cannot use Git hunk selection on a file with unresolved merge entries.")

                return
            end

            _get_action_details(action, buffer, details, function(data)
                if not data then
                    return
                end

                git_diff.build_zero_context_diff(data.base_text, data.target_text, function(diff, diff_error)
                    if not diff then
                        _notify_error(string.format("Cannot calculate selected Git hunks: %s", diff_error or ""))

                        return
                    end

                    local hunk =
                        _find_closest_hunk(git_diff.parse_selection_diff(diff), vim.api.nvim_win_get_cursor(0)[1])

                    if not hunk then
                        vim.notify("No Git hunk lines were found.", vim.log.levels.INFO)

                        return
                    end

                    local start_line, end_line = _get_hunk_line_range(hunk)
                    _apply_selection_from_details(action, buffer, data, diff, start_line, end_line)
                end)
            end)
        end)
    end)
end

--- Run `action` over a command range.
---
--- In a quickfix buffer the range counts listed rows rather than file lines, so
--- each selected row acts on the hunk it points at. Without a range Vim supplies
--- the cursor row, which acts on just the hunk under the cursor.
---
---@param action _my.git_hunks.Action The hunk operation to run.
---@param options _my.git_hunks.RangeCommandOptions The command range details.
local function _apply_range_command(action, options)
    if _P.is_quickfix_buffer() then
        _P.apply_quickfix_selection(action, options.line1, options.line2)

        return
    end

    _P.apply_selection(action, options.line1, options.line2)
end

--- Run `action` on the hunk under the cursor.
---
--- File buffers act on the nearest hunk to the cursor line. Quickfix buffers act
--- on the hunk named by the cursor row instead.
---
---@param action _my.git_hunks.Action The hunk operation to run.
local function _apply_cursor_hunk(action)
    if _P.is_quickfix_buffer() then
        local row = vim.api.nvim_win_get_cursor(0)[1]
        _P.apply_quickfix_selection(action, row, row)

        return
    end

    _P.apply_closest_hunk(action)
end

--- Stage a ranged Git hunk selection.
---
---@param options _my.git_hunks.RangeCommandOptions The command range details.
local function _stage_selection_command(options)
    _apply_range_command("stage", options)
end

--- Reset a ranged Git hunk selection from the index.
---
---@param options _my.git_hunks.RangeCommandOptions The command range details.
local function _reset_selection_command(options)
    _apply_range_command("reset", options)
end

--- Check out a ranged Git hunk selection from the index.
---
---@param options _my.git_hunks.RangeCommandOptions The command range details.
local function _checkout_selection_command(options)
    _apply_range_command("checkout", options)
end

vim.api.nvim_create_user_command("GitStageSelection", _stage_selection_command, {
    range = true,
    desc = "Stage selected Git hunk lines.",
})

vim.api.nvim_create_user_command("GitResetSelection", _reset_selection_command, {
    range = true,
    desc = "Reset selected Git hunk lines from the index.",
})

vim.api.nvim_create_user_command("GitCheckoutSelection", _checkout_selection_command, {
    range = true,
    desc = "Check out selected Git hunk lines from the index.",
})

vim.keymap.set("x", "<leader>gah", ":GitStageSelection<CR>", { desc = "Stage selected Git hunk lines." })

vim.keymap.set("n", "<leader>gah", function()
    _apply_cursor_hunk("stage")
end, { desc = "Stage closest Git hunk." })

vim.keymap.set("x", "<leader>grh", ":GitResetSelection<CR>", {
    desc = "Reset selected Git hunk lines from the index.",
})

vim.keymap.set("n", "<leader>grh", function()
    _apply_cursor_hunk("reset")
end, { desc = "Reset closest Git hunk from the index." })

vim.keymap.set("x", "<leader>gch", ":GitCheckoutSelection<CR>", {
    desc = "Check out selected Git hunk lines from the index.",
})

vim.keymap.set("n", "<leader>gch", function()
    _apply_cursor_hunk("checkout")
end, { desc = "Check out closest Git hunk from the index." })

vim.keymap.set("n", "<leader>gac", function()
    _P.apply_current_file("stage")
end, { desc = "Stage current Git file." })

vim.keymap.set("n", "<leader>grc", function()
    _P.apply_current_file("reset")
end, { desc = "Reset current Git file from the index." })
