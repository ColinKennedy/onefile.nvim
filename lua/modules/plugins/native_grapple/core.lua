--- Branch-aware native bookmark management inspired by grapple.nvim.

local M = {}
local _P = {}

M.BOOKMARK_MINIMUM = 1
M.BOOKMARK_MAXIMUM = 9
M.MARKS_FILE_NAME = ".nvim.marks.lua"

local _STATE = {
    branch = nil, ---@type string?
    root = nil, ---@type string?
}

---@param index integer A 1-to-9 value.
---@return string # The global character mark. e.g. A, B, C, etc.
function M.get_mark_from_index(index)
    return string.char(64 + index)
end

---@param mark string The Vim mark to query.
---@return boolean
function _P.is_mark_defined(mark)
    return vim.api.nvim_get_mark(mark, {})[1] ~= 0
end

---@param reference_path string? Explicit path to resolve before falling back to the current buffer.
---@return string
function _P.get_reference_path(reference_path)
    if reference_path and reference_path ~= "" then
        return reference_path
    end

    local buffer_path = vim.api.nvim_buf_get_name(0)

    if buffer_path ~= "" then
        return buffer_path
    end

    return vim.fn.getcwd()
end

---@param reference_path string?
---@return string?
function _P.get_repository_root(reference_path)
    return require("modules.utilities.core_helpers").get_nearest_project_root(_P.get_reference_path(reference_path))
end

---@param root string
---@return string?
function _P.get_git_branch(root)
    local core_helpers = require("modules.utilities.core_helpers")
    local command = { core_helpers._GIT_EXECUTABLE, "-C", root, "branch", "--show-current" }
    local output = vim.fn.systemlist(command)

    if vim.v.shell_error ~= 0 then
        return nil
    end

    local branch = vim.trim(output[1] or "")

    if branch == "" then
        return nil
    end

    return branch
end

---@param root string
---@param branch string
---@return string
function _P.get_marks_path(root, branch)
    local core_helpers = require("modules.utilities.core_helpers")

    return vim.fs.joinpath(root, core_helpers._SESSIONS_DIRECTORY_NAME, branch, M.MARKS_FILE_NAME)
end

--- Iterate over every native grapple bookmark.
---
---@return fun(): integer?, integer?, string?
---    The logical bookmark index.
---    The Vim buffer number of the bookmarked file.
---    The full path to the Vim buffer.
function M.iter_bookmarks()
    local index = M.BOOKMARK_MINIMUM - 1

    return function()
        while true do
            index = index + 1

            if index > M.BOOKMARK_MAXIMUM then
                return nil
            end

            local mark = M.get_mark_from_index(index)
            local position = vim.api.nvim_get_mark(mark, {})

            if position[1] ~= 0 then
                return index, position[3], position[4]
            end
        end
    end
end

function M.delete_all_bookmarks()
    for index, _, _ in M.iter_bookmarks() do
        _P.delete_bookmark(index)
    end
end

---@param index integer 1-to-9 bookmark logical index.
function _P.delete_bookmark(index)
    vim.cmd.delmarks(M.get_mark_from_index(index))
end

---@param index integer 1-to-9 bookmark logical index.
function M.delete_bookmark(index)
    M.sync_branch()
    _P.delete_bookmark(index)
    M.write_current_branch_marks()
end

---@param mark string A Vim mark to set. e.g. `"A"`.
---@param buffer integer | string A buffer number or path.
---@param line integer?
---@param column integer?
function M.reset_bookmark(mark, buffer, line, column)
    local buffer_number

    if type(buffer) == "number" then
        buffer_number = buffer
    elseif type(buffer) == "string" then
        buffer_number = vim.fn.bufnr(buffer, true)
    else
        error(string.format('Expected buffer number or path but got "%s".', type(buffer)), 0)
    end

    vim.fn.bufload(buffer_number)
    vim.api.nvim_buf_set_mark(buffer_number, mark, line or 1, column or 0, {})
end

---@param mark string The Vim mark to jump to or apply.
function M.mark_current_buffer_as_bookmark(mark)
    M.sync_branch()

    if not _P.is_mark_defined(mark) then
        vim.cmd.mark(mark)
        M.write_current_branch_marks()

        return
    end

    vim.cmd("normal! `" .. mark)
    pcall(function()
        vim.cmd('normal! `"')
    end)
end

function M.mark_current_buffer_as_next_bookmark()
    local maximum

    for index = M.BOOKMARK_MINIMUM, M.BOOKMARK_MAXIMUM do
        if _P.is_mark_defined(M.get_mark_from_index(index)) then
            maximum = index
        end
    end

    local next_index = 1

    if maximum then
        next_index = (maximum % M.BOOKMARK_MAXIMUM) + 1
    end

    M.mark_current_buffer_as_bookmark(M.get_mark_from_index(next_index))
end

---@param offset integer The number of bookmarks to jump.
function M.go_to_relative_bookmark(offset)
    M.sync_branch()

    ---@type {index: integer, buffer: integer, path: string}[]
    local bookmarks = {}

    for _, buffer_number, buffer_path in M.iter_bookmarks() do
        table.insert(bookmarks, { buffer = buffer_number, path = buffer_path })
    end

    if vim.tbl_isempty(bookmarks) then
        vim.notify("No native grapple bookmarks found.", vim.log.levels.INFO)

        return
    end

    local current_buffer = vim.api.nvim_get_current_buf()

    for index, bookmark in ipairs(bookmarks) do
        if bookmark.buffer == current_buffer then
            local new_index = ((index - 1 + offset) % #bookmarks) + 1
            M.open_bookmark(bookmarks[new_index])

            return
        end
    end

    local fallback_index = (offset % #bookmarks) + 1
    M.open_bookmark(bookmarks[fallback_index])
end

---@param bookmark {buffer: integer, path: string}
function M.open_bookmark(bookmark)
    if bookmark.buffer ~= 0 and vim.api.nvim_buf_is_valid(bookmark.buffer) then
        vim.cmd.buffer(bookmark.buffer)

        return
    end

    vim.cmd.edit(vim.fn.fnameescape(bookmark.path))
end

function M.show_bookmarks()
    M.sync_branch()

    ---@type vim.quickfix.entry[]
    local quickfix_entries = {}

    for index, buffer_number, buffer_path in M.iter_bookmarks() do
        local mark = M.get_mark_from_index(index)
        local position = vim.api.nvim_get_mark(mark, {})

        table.insert(quickfix_entries, {
            bufnr = buffer_number,
            filename = buffer_path,
            lnum = position[1],
            col = position[2],
            text = tostring(index),
        })
    end

    vim.fn.setqflist(quickfix_entries)

    if vim.tbl_isempty(quickfix_entries) then
        vim.cmd.cclose()
    else
        vim.cmd.copen()
    end
end

function M.toggle_current_buffer()
    M.sync_branch()

    ---@type {index: integer?, path: string?}[]
    local bookmarks = {}
    local current_buffer = vim.api.nvim_get_current_buf()
    local found_current_buffer = false

    for _, buffer_number, buffer_path in M.iter_bookmarks() do
        if buffer_number == current_buffer then
            found_current_buffer = true
        else
            table.insert(bookmarks, buffer_number == 0 and { path = buffer_path } or { index = buffer_number })
        end
    end

    if not found_current_buffer then
        table.insert(bookmarks, { index = current_buffer })
    end

    M.delete_all_bookmarks()

    for new_index, bookmark in ipairs(bookmarks) do
        local value = bookmark.index or bookmark.path

        if value then
            M.reset_bookmark(M.get_mark_from_index(new_index), value)
        end
    end

    M.write_current_branch_marks()
end

---@param root string?
---@return string[]
function M.serialize_mark_code(root)
    local output = {
        "local original_buffer = vim.api.nvim_get_current_buf()",
        "local function set_mark(path, mark, line, column)",
        "    local buffer = vim.fn.bufnr(path, true)",
        "    vim.fn.bufload(buffer)",
        "    vim.api.nvim_buf_set_mark(buffer, mark, line, column, {})",
        "end",
    }

    for index, _, buffer_path in M.iter_bookmarks() do
        local mark = M.get_mark_from_index(index)
        local position = vim.api.nvim_get_mark(mark, {})
        local path = buffer_path

        if root then
            local success, relative = pcall(vim.fs.relpath, root, path)

            if success and relative then
                path = vim.fs.joinpath(root, relative)
            end
        end

        table.insert(output, string.format("set_mark(%q, %q, %d, %d)", path, mark, position[1], position[2]))
    end

    table.insert(output, "pcall(vim.cmd.buffer, original_buffer)")

    return output
end

---@param root string?
---@param branch string?
function M.write_branch_marks(root, branch)
    if not root or not branch then
        return
    end

    local path = _P.get_marks_path(root, branch)
    vim.fn.mkdir(vim.fs.dirname(path), "p")

    local handle = assert(io.open(path, "w"))

    handle:write(table.concat(M.serialize_mark_code(root), "\n"))
    handle:write("\n")
    handle:close()
end

function M.write_current_branch_marks()
    M.write_branch_marks(_STATE.root, _STATE.branch)
end

---@param root string
---@param branch string
function M.load_branch_marks(root, branch)
    local path = _P.get_marks_path(root, branch)

    if vim.fn.filereadable(path) ~= 1 then
        return
    end

    local ok, message = pcall(dofile, path)

    if not ok then
        vim.notify(
            string.format('Could not load native grapple marks from "%s": %s', path, message),
            vim.log.levels.ERROR
        )
    end
end

---@param reference_path string? Explicit path to use when deciding which project root to load.
function M.sync_branch(reference_path)
    local root = _P.get_repository_root(reference_path)

    if not root then
        M.write_current_branch_marks()
        M.delete_all_bookmarks()
        _STATE.root = nil
        _STATE.branch = nil

        return
    end

    local branch = _P.get_git_branch(root)

    if not branch then
        M.write_current_branch_marks()
        M.delete_all_bookmarks()
        _STATE.root = nil
        _STATE.branch = nil

        return
    end

    if not _STATE.root and not _STATE.branch then
        _STATE.root = root
        _STATE.branch = branch
        M.delete_all_bookmarks()
        M.load_branch_marks(root, branch)

        return
    end

    if _STATE.root == root and _STATE.branch == branch then
        return
    end

    M.write_current_branch_marks()
    M.delete_all_bookmarks()
    _STATE.root = root
    _STATE.branch = branch
    M.load_branch_marks(root, branch)
end

return M
