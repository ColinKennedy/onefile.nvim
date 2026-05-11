--- Show index-relative git signs for unsaved buffer edits.

local M = {}
local _P = {}

local _AUGROUP = vim.api.nvim_create_augroup("my.git_gutter", { clear = true })
local _SIGN_GROUP = "my.git_gutter"
local _SIGN_ADD = "MyGitGutterAdd"
local _SIGN_CHANGE = "MyGitGutterChange"
local _SIGN_DELETE = "MyGitGutterDelete"

--- Tracks the newest async update request for each buffer so stale callbacks cannot place outdated signs.
---
---@type table<integer, integer>
local _UPDATE_GENERATION_BY_BUFFER = {}

--- Define git gutter highlight groups and signs.
function _P.define_signs()
    vim.api.nvim_set_hl(0, "GitGutterAdd", { default = true, fg = "#50fa7b" })
    vim.api.nvim_set_hl(0, "GitGutterChange", { default = true, fg = "#56b6c2" })
    vim.api.nvim_set_hl(0, "GitGutterDelete", { default = true, fg = "#ff5555" })

    local add_text = "|"
    local change_text = "|"
    local delete_text = "_"

    if require("modules.utilities.core_helpers").IS_NERDFONT_ALLOWED then
        add_text = "┃"
        change_text = "┃"
        delete_text = "▁"
    end

    vim.fn.sign_define(_SIGN_ADD, { text = add_text, texthl = "GitGutterAdd" })
    vim.fn.sign_define(_SIGN_CHANGE, { text = change_text, texthl = "GitGutterChange" })
    vim.fn.sign_define(_SIGN_DELETE, { text = delete_text, texthl = "GitGutterDelete" })
end

--- Check if `buffer` can show git signs.
---
---@param buffer integer The buffer to inspect.
---@return boolean # If signs are allowed, return `true`.
---
local function _is_supported_buffer(buffer)
    return vim.api.nvim_buf_is_valid(buffer)
        and vim.api.nvim_buf_get_name(buffer) ~= ""
        and vim.bo[buffer].buftype == ""
        and vim.bo[buffer].modifiable
end

--- Place one sign in `buffer`.
---
---@param buffer integer The buffer that receives the sign.
---@param sign string The sign name to place.
---@param line integer The 1-or-more buffer line.
---
local function _place_sign(buffer, sign, line)
    local line_count = math.max(vim.api.nvim_buf_line_count(buffer), 1)
    local lnum = math.max(1, math.min(line, line_count))

    vim.fn.sign_place(0, _SIGN_GROUP, sign, buffer, { lnum = lnum, priority = 6 })
end

--- Update git gutter signs for `buffer`.
---
---@param buffer integer? The buffer to update. Defaults to current buffer.
function M.update(buffer)
    buffer = buffer or vim.api.nvim_get_current_buf()

    if buffer == 0 then
        buffer = vim.api.nvim_get_current_buf()
    end

    if not _is_supported_buffer(buffer) then
        return
    end

    _UPDATE_GENERATION_BY_BUFFER[buffer] = (_UPDATE_GENERATION_BY_BUFFER[buffer] or 0) + 1
    local generation = _UPDATE_GENERATION_BY_BUFFER[buffer]

    local git_diff = require("modules.utilities.git_diff")

    git_diff.get_file_details(buffer, function(details)
        if generation ~= _UPDATE_GENERATION_BY_BUFFER[buffer] then
            return
        end

        vim.fn.sign_unplace(_SIGN_GROUP, { buffer = buffer })

        if not details then
            return
        end

        git_diff.get_index_lines(details, function(old_lines)
            if generation ~= _UPDATE_GENERATION_BY_BUFFER[buffer] or not _is_supported_buffer(buffer) then
                return
            end

            local new_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
            local hunks = git_diff.compute_hunks(old_lines, new_lines)

            for _, hunk in ipairs(hunks) do
                if hunk.type == "delete" then
                    _place_sign(buffer, _SIGN_DELETE, hunk.line)
                else
                    local sign = hunk.type == "add" and _SIGN_ADD or _SIGN_CHANGE
                    local count = math.max(hunk.new_count, 1)

                    for offset = 0, count - 1 do
                        _place_sign(buffer, sign, hunk.new_start + offset)
                    end
                end
            end
        end)
    end)
end

--- Schedule a sign refresh for a buffer event.
---
---@param event table The Neovim autocommand event.
local function _schedule_update(event)
    local buffer = event.buf

    vim.schedule(function()
        M.update(buffer)
    end)
end

_P.define_signs()

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "TextChangedI" }, {
    callback = _schedule_update,
    group = _AUGROUP,
})

return M
