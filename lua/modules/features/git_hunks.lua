--- Stage and unstage visual selections from unsaved buffer edits.

local git_diff = require("modules.utilities.git_diff")
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
---@param buffer integer The Vim buffer to modify.
---@param text string The full text to place into the buffer.
local function _set_buffer_text(buffer, text)
    local has_eol = text:sub(-1) == "\n"
    local body = has_eol and text:sub(1, -2) or text
    local lines = {}

    if body ~= "" then
        lines = vim.split(body, "\n", { plain = true })
    end

    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
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
---@return _my.git_hunks.ActionDetails? # The resolved action details.
local function _get_action_details(action, buffer, details)
    local base_text
    local target_text
    local success_message

    if action == "stage" or action == "checkout" then
        local show_error
        base_text, show_error = git_diff.get_blob_text(details, ":" .. details.relative_path)

        if not base_text then
            _notify_error(
                string.format("Cannot stage selected hunks for an untracked or non-text file: %s", show_error or "")
            )

            return nil
        end

        target_text = _get_buffer_text(buffer)

        if action == "stage" then
            success_message = "Staged selected Git hunk lines."
        else
            success_message = "Checked out selected Git hunk lines."
        end
    else
        local base_error
        local target_error
        base_text, base_error = git_diff.get_blob_text(details, "HEAD:" .. details.relative_path)
        target_text, target_error = git_diff.get_blob_text(details, ":" .. details.relative_path)

        if not base_text or not target_text then
            _notify_error(
                string.format("Cannot reset selected hunks for this file: %s%s", base_error or "", target_error or "")
            )

            return nil
        end

        success_message = "Reset selected Git hunk lines from the index."
    end

    if base_text:find("\0", 1, true) or target_text:find("\0", 1, true) then
        _notify_error("Cannot use Git hunk selection on binary files.")

        return nil
    end

    return {
        base_text = base_text,
        details = details,
        success_message = success_message,
        target_text = target_text,
    }
end

--- Run a hunk operation using already-resolved texts and range.
---
---@param action _my.git_hunks.Action The hunk operation to run.
---@param buffer integer The Vim buffer to inspect.
---@param data _my.git_hunks.ActionDetails The resolved action details.
---@param diff string A zero-context diff for the operation.
---@param start_line integer The first selected line.
---@param end_line integer The last selected line.
local function _apply_selection_from_details(action, buffer, data, diff, start_line, end_line)
    local partial_text, selected_changes = git_diff.build_selection_target(
        data.base_text,
        data.target_text,
        diff,
        start_line,
        end_line,
        action == "reset"
    )

    if selected_changes == 0 then
        vim.notify("No Git hunk lines were selected.", vim.log.levels.INFO)

        return
    end

    if action == "checkout" then
        local checkout_text =
            git_diff.build_selection_target(data.base_text, data.target_text, diff, start_line, end_line, true)

        _set_buffer_text(buffer, checkout_text)
        vim.notify(data.success_message, vim.log.levels.INFO)
        _refresh_git_views(buffer)

        return
    end

    local patch_base_text = action == "reset" and data.target_text or data.base_text
    local patch, patch_error = git_diff.build_selection_patch(patch_base_text, partial_text, data.details.relative_path)

    if not patch then
        _notify_error(string.format("Cannot create selected Git hunk patch: %s", patch_error or ""))

        return
    end

    local success, apply_error = git_diff.apply_cached_patch(data.details, patch)

    if not success then
        _notify_error(string.format("Cannot apply selected Git hunk patch: %s", apply_error or ""))

        return
    end

    vim.notify(data.success_message, vim.log.levels.INFO)
    _refresh_git_views(buffer)
end

--- Get the Git index file mode for `details`.
---
---@param details _my.git_diff.FileDetails The Git file details.
---@return string # The index mode to use.
local function _get_index_mode(details)
    local result = git_diff.run_git(
        { "-C", details.repository, "ls-files", "-s", "--", details.relative_path },
        details.repository
    )
    local mode = result.stdout:match("^(%d+)%s")

    if mode then
        return mode
    end

    return "100644"
end

--- Stage exact text into the index for `details`.
---
---@param details _my.git_diff.FileDetails The Git file details.
---@param text string The text to stage.
---@return boolean # If the text was staged, return `true`.
---@return string? # An error message, if any.
local function _stage_text(details, text)
    local object =
        git_diff.run_git({ "-C", details.repository, "hash-object", "-w", "--stdin" }, details.repository, text)

    if object.code ~= 0 then
        return false, vim.trim(object.stderr)
    end

    local object_id = vim.trim(object.stdout)
    local result = git_diff.run_git(
        {
            "-C",
            details.repository,
            "update-index",
            "--add",
            "--cacheinfo",
            _get_index_mode(details),
            object_id,
            details.relative_path,
        },
        details.repository
    )

    if result.code ~= 0 then
        return false, vim.trim(result.stderr)
    end

    return true, nil
end

--- Run a whole-file Git hunk action for the current buffer.
---
---@param action "stage" | "reset" The whole-file operation to run.
function _P.apply_current_file(action)
    local buffer = vim.api.nvim_get_current_buf()
    local details, details_error = git_diff.get_file_details(buffer)

    if not details then
        _notify_error(details_error or "Cannot find git details for current buffer.")

        return
    end

    if git_diff.has_unmerged_entries(details) then
        _notify_error("Cannot use Git whole-file actions on a file with unresolved merge entries.")

        return
    end

    local success
    local message

    if action == "stage" then
        success, message = _stage_text(details, _get_buffer_text(buffer))
    else
        local result =
            git_diff.run_git({ "-C", details.repository, "reset", "--", details.relative_path }, details.repository)
        success = result.code == 0
        message = vim.trim(result.stderr)
    end

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

--- Run a visual Git hunk action for selected lines.
---
---@param action _my.git_hunks.Action The hunk operation to run.
---@param start_line integer The first selected line.
---@param end_line integer The last selected line.
function _P.apply_selection(action, start_line, end_line)
    if start_line > end_line then
        start_line, end_line = end_line, start_line
    end

    local buffer = vim.api.nvim_get_current_buf()
    local details, details_error = git_diff.get_file_details(buffer)

    if not details then
        _notify_error(details_error or "Cannot find git details for current buffer.")

        return
    end

    if git_diff.has_unmerged_entries(details) then
        _notify_error("Cannot use Git hunk selection on a file with unresolved merge entries.")

        return
    end

    local data = _get_action_details(action, buffer, details)
    if not data then
        return
    end

    local diff, diff_error = git_diff.build_zero_context_diff(data.base_text, data.target_text)

    if not diff then
        _notify_error(string.format("Cannot calculate selected Git hunks: %s", diff_error or ""))

        return
    end

    _apply_selection_from_details(action, buffer, data, diff, start_line, end_line)
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

--- Run a visual Git hunk action for the closest hunk.
---
---@param action _my.git_hunks.Action The hunk operation to run.
function _P.apply_closest_hunk(action)
    local buffer = vim.api.nvim_get_current_buf()
    local details, details_error = git_diff.get_file_details(buffer)

    if not details then
        _notify_error(details_error or "Cannot find git details for current buffer.")

        return
    end

    if git_diff.has_unmerged_entries(details) then
        _notify_error("Cannot use Git hunk selection on a file with unresolved merge entries.")

        return
    end

    local data = _get_action_details(action, buffer, details)
    if not data then
        return
    end

    local diff, diff_error = git_diff.build_zero_context_diff(data.base_text, data.target_text)

    if not diff then
        _notify_error(string.format("Cannot calculate selected Git hunks: %s", diff_error or ""))

        return
    end

    local hunk = _find_closest_hunk(git_diff.parse_selection_diff(diff), vim.api.nvim_win_get_cursor(0)[1])

    if not hunk then
        vim.notify("No Git hunk lines were found.", vim.log.levels.INFO)

        return
    end

    local start_line, end_line = _get_hunk_line_range(hunk)
    _apply_selection_from_details(action, buffer, data, diff, start_line, end_line)
end

--- Stage a ranged Git hunk selection.
---
---@param options _my.git_hunks.RangeCommandOptions The command range details.
local function _stage_selection_command(options)
    _P.apply_selection("stage", options.line1, options.line2)
end

--- Reset a ranged Git hunk selection from the index.
---
---@param options _my.git_hunks.RangeCommandOptions The command range details.
local function _reset_selection_command(options)
    _P.apply_selection("reset", options.line1, options.line2)
end

--- Check out a ranged Git hunk selection from the index.
---
---@param options _my.git_hunks.RangeCommandOptions The command range details.
local function _checkout_selection_command(options)
    _P.apply_selection("checkout", options.line1, options.line2)
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
    _P.apply_closest_hunk("stage")
end, { desc = "Stage closest Git hunk." })

vim.keymap.set("x", "<leader>grh", ":GitResetSelection<CR>", {
    desc = "Reset selected Git hunk lines from the index.",
})

vim.keymap.set("n", "<leader>grh", function()
    _P.apply_closest_hunk("reset")
end, { desc = "Reset closest Git hunk from the index." })

vim.keymap.set("x", "<leader>gch", ":GitCheckoutSelection<CR>", {
    desc = "Check out selected Git hunk lines from the index.",
})

vim.keymap.set("n", "<leader>gch", function()
    _P.apply_closest_hunk("checkout")
end, { desc = "Check out closest Git hunk from the index." })

vim.keymap.set("n", "<leader>gac", function()
    _P.apply_current_file("stage")
end, { desc = "Stage current Git file." })

vim.keymap.set("n", "<leader>grc", function()
    _P.apply_current_file("reset")
end, { desc = "Reset current Git file from the index." })
