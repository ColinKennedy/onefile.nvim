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

---@class _my.git_hunks.RangeCommandOptions
---@field line1 integer The first command range line.
---@field line2 integer The last command range line.

--- Run a visual Git hunk action for selected lines.
---
---@param action "stage" | "reset" | "checkout" The hunk operation to run.
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

            return
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

            return
        end

        success_message = "Reset selected Git hunk lines from the index."
    end

    if base_text:find("\0", 1, true) or target_text:find("\0", 1, true) then
        _notify_error("Cannot use Git hunk selection on binary files.")

        return
    end

    local diff, diff_error = git_diff.build_zero_context_diff(base_text, target_text)

    if not diff then
        _notify_error(string.format("Cannot calculate selected Git hunks: %s", diff_error or ""))

        return
    end

    local partial_text, selected_changes =
        git_diff.build_selection_target(base_text, target_text, diff, start_line, end_line, action == "reset")

    if selected_changes == 0 then
        vim.notify("No Git hunk lines were selected.", vim.log.levels.INFO)

        return
    end

    if action == "checkout" then
        local checkout_text =
            git_diff.build_selection_target(base_text, target_text, diff, start_line, end_line, true)

        _set_buffer_text(buffer, checkout_text)
        vim.notify(success_message, vim.log.levels.INFO)
        require("modules.features.git_gutter").update(buffer)

        return
    end

    local patch_base_text = action == "reset" and target_text or base_text
    local patch, patch_error = git_diff.build_selection_patch(patch_base_text, partial_text, details.relative_path)

    if not patch then
        _notify_error(string.format("Cannot create selected Git hunk patch: %s", patch_error or ""))

        return
    end

    local success, apply_error = git_diff.apply_cached_patch(details, patch)

    if not success then
        _notify_error(string.format("Cannot apply selected Git hunk patch: %s", apply_error or ""))

        return
    end

    vim.notify(success_message, vim.log.levels.INFO)
    require("modules.features.git_gutter").update(buffer)
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

vim.keymap.set("x", "<leader>grh", ":GitResetSelection<CR>", {
    desc = "Reset selected Git hunk lines from the index.",
})

vim.keymap.set("x", "<leader>gch", ":GitCheckoutSelection<CR>", {
    desc = "Check out selected Git hunk lines from the index.",
})
