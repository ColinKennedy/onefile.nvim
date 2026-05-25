--- Branch-aware native bookmark management inspired by grapple.nvim.

local M = {}
local _P = {}

M.BOOKMARK_MINIMUM = 1
M.BOOKMARK_MAXIMUM = 9
M.MARKS_FILE_NAME = ".nvim.marks.lua"
M.NO_GIT_BRANCH_NAME = "cwd"

---@class _my.native_grapple.Context
---@field cwd string The directory that Neovim's current working directory resolved to.
---@field root string The storage root for marks.
---@field branch string The Git branch, or the non-Git fallback namespace.
---@field git_dir string? The absolute Git directory, if `root` is a Git repository.
---@field head_path string? The Git HEAD file watched for branch changes.

---@class _my.native_grapple.State
---@field cwd string?
---@field root string?
---@field branch string?
---@field git_dir string?
---@field head_path string?

---@class _my.native_grapple.Bookmark
---@field buffer integer The buffer that owns the mark.
---@field path string The marked file path.
---@field line integer? The marked line, when known.
---@field column integer? The marked column, when known.

---@type _my.native_grapple.State
local _STATE = {
    branch = nil,
    cwd = nil,
    git_dir = nil,
    head_path = nil,
    root = nil,
}

---@type table<string, uv.uv_fs_event_t>
local _HEAD_WATCHERS_BY_ROOT = {}

local _BRANCH_RELOAD_TIMER = assert(vim.uv.new_timer())
local _BRANCH_RELOAD_DEBOUNCE_MS = 80

--- Recompute statuslines after native grapple mark text changes.
function _P.redraw_statusline()
    vim.cmd.redrawstatus()
end

--- Normalize a filesystem path for stable comparisons.
---
---@param path string A filesystem path.
---@return string # The normalized path.
function _P.normalize_path(path)
    return vim.fs.normalize(path)
end

--- Convert a possible file path into a directory that Git can inspect.
---
---@param reference_path string? A file or directory path.
---@return string # The directory to use as the current context.
function _P.get_reference_directory(reference_path)
    if reference_path and reference_path ~= "" then
        if vim.fn.isdirectory(reference_path) == 1 then
            return _P.normalize_path(reference_path)
        end

        return _P.normalize_path(vim.fs.dirname(reference_path))
    end

    return _P.normalize_path(vim.fn.getcwd())
end

--- Resolve the current native grapple storage context from a directory.
---
--- Git repositories use their top-level directory plus the current branch.
--- Directories outside Git use the current working directory plus a fixed
--- fallback namespace so marks still work without a session or repository.
---
---@param reference_path string? A file or directory path to resolve from.
---@return _my.native_grapple.Context # The resolved storage context.
function _P.resolve_context(reference_path)
    local cwd = _P.get_reference_directory(reference_path)
    local core_helpers = require("modules.utilities.core_helpers")
    local command = {
        core_helpers._GIT_EXECUTABLE,
        "-C",
        cwd,
        "rev-parse",
        "--show-toplevel",
        "--absolute-git-dir",
        "--abbrev-ref",
        "HEAD",
    }
    local result = vim.system(command, { text = true }):wait()

    if result.code ~= 0 then
        return {
            branch = M.NO_GIT_BRANCH_NAME,
            cwd = cwd,
            root = cwd,
        }
    end

    local lines = vim.split(result.stdout or "", "\n", { plain = true, trimempty = true })
    local root = lines[1]
    local git_dir = lines[2]
    local branch = lines[3]

    if not root or root == "" then
        root = cwd
    end

    if not branch or branch == "" or branch == "HEAD" then
        branch = M.NO_GIT_BRANCH_NAME
    end

    ---@type _my.native_grapple.Context
    return {
        branch = branch,
        cwd = cwd,
        git_dir = git_dir,
        head_path = git_dir and vim.fs.joinpath(git_dir, "HEAD") or nil,
        root = _P.normalize_path(root),
    }
end

--- Get the storage path for a root and branch namespace.
---
---@param root string The root that owns the marks.
---@param branch string The branch or fallback namespace.
---@return string # The mark file path.
function _P.get_marks_path(root, branch)
    local core_helpers = require("modules.utilities.core_helpers")

    return vim.fs.joinpath(root, core_helpers._SESSIONS_DIRECTORY_NAME, branch, M.MARKS_FILE_NAME)
end

--- Close one watched Git HEAD file.
---
---@param root string The root whose watcher should close.
function _P.close_head_watcher(root)
    local watcher = _HEAD_WATCHERS_BY_ROOT[root]

    if not watcher then
        return
    end

    if not watcher:is_closing() then
        watcher:stop()
        watcher:close()
    end

    _HEAD_WATCHERS_BY_ROOT[root] = nil
end

--- Debounce a branch reload caused by a watched Git HEAD update.
---
---@param cwd string The working directory whose marks should refresh.
function _P.schedule_branch_reload(cwd)
    if _BRANCH_RELOAD_TIMER:is_active() then
        _BRANCH_RELOAD_TIMER:stop()
    end

    _BRANCH_RELOAD_TIMER:start(_BRANCH_RELOAD_DEBOUNCE_MS, 0, function()
        vim.schedule(function()
            M.sync_branch(cwd, { force = true })
            vim.cmd.redrawstatus()
        end)
    end)
end

--- Watch a Git HEAD file for branch changes without polling on hot paths.
---
---@param context _my.native_grapple.Context The context whose HEAD should be watched.
function _P.watch_head(context)
    if not context.head_path or vim.fn.filereadable(context.head_path) ~= 1 then
        return
    end

    if _HEAD_WATCHERS_BY_ROOT[context.root] then
        return
    end

    local watcher = vim.uv.new_fs_event()

    if not watcher then
        return
    end

    local ok = watcher:start(context.head_path, {}, function()
        _P.schedule_branch_reload(context.cwd)
    end)

    if ok then
        _HEAD_WATCHERS_BY_ROOT[context.root] = watcher
    else
        watcher:close()
    end
end

---@param index integer A 1-to-9 value.
---@return string # The global character mark. e.g. A, B, C, etc.
function M.get_mark_from_index(index)
    return string.char(64 + index)
end

---@param mark string The Vim mark to query.
---@return boolean # If the mark exists, return true.
function _P.is_mark_defined(mark)
    return vim.api.nvim_get_mark(mark, {})[1] ~= 0
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

--- Delete every native grapple bookmark mark.
function M.delete_all_bookmarks()
    for index = M.BOOKMARK_MINIMUM, M.BOOKMARK_MAXIMUM do
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
    _P.redraw_statusline()
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

--- Mark the current buffer as the next available bookmark.
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

    ---@type _my.native_grapple.Bookmark[]
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

---@param bookmark _my.native_grapple.Bookmark The bookmark to open.
function M.open_bookmark(bookmark)
    if bookmark.buffer ~= 0 and vim.api.nvim_buf_is_valid(bookmark.buffer) then
        vim.cmd.buffer(bookmark.buffer)
    else
        vim.cmd.edit(vim.fn.fnameescape(bookmark.path))
        bookmark.buffer = vim.api.nvim_get_current_buf()
    end

    if bookmark.line then
        local line_count = vim.api.nvim_buf_line_count(bookmark.buffer)
        local line = bookmark.line
        local column = bookmark.column or 0

        if line > line_count then
            line = 1
            column = 0
        end

        vim.api.nvim_win_set_cursor(0, { line, column })
    end
end

---@param mark string The Vim mark to jump to or apply.
function M.mark_current_buffer_as_bookmark(mark)
    M.sync_branch()

    if not _P.is_mark_defined(mark) then
        vim.cmd.mark(mark)
        M.write_current_branch_marks()
        _P.redraw_statusline()

        return
    end

    local position = vim.api.nvim_get_mark(mark, {})
    M.open_bookmark({ buffer = position[3], path = position[4], line = position[1], column = position[2] })
end

--- Load current bookmarks into the quickfix list.
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

--- Toggle the current buffer into or out of native grapple marks.
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
    _P.redraw_statusline()
end

---@param root string?
---@return string[] # The Lua code that restores the current marks.
function M.serialize_mark_code(root)
    local output = {
        "local function set_mark(path, mark, line, column)",
        "    local buffer = vim.fn.bufnr(path, true)",
        '    vim.fn.setpos("\'" .. mark, { buffer, line, column + 1, 0 })',
        "end",
    }

    for index, _, buffer_path in M.iter_bookmarks() do
        local mark = M.get_mark_from_index(index)
        local position = vim.api.nvim_get_mark(mark, {})
        local path = buffer_path

        if root then
            local success, relative = pcall(vim.fs.relpath, root, path)

            if success and relative then
                path = relative
            end
        end

        table.insert(output, string.format("set_mark(%q, %q, %d, %d)", path, mark, position[1], position[2]))
    end

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

--- Write marks for the currently loaded root and branch.
function M.write_current_branch_marks()
    M.write_branch_marks(_STATE.root, _STATE.branch)
end

--- Set a Vim mark, falling back to the file top when a saved line is stale.
---
---@param setter fun(buffer: integer, mark: string, line: integer, column: integer, opts: table): nil
---    The real mark setter.
---@param buffer integer The buffer to mark.
---@param mark string The Vim mark to set.
---@param line integer The saved line number.
---@param column integer The saved column number.
---@param opts table Extra mark options.
function _P.set_mark_or_top(setter, buffer, mark, line, column, opts)
    local ok, message = pcall(setter, buffer, mark, line, column, opts)

    if ok then
        return
    end

    if tostring(message):find("Invalid 'line'", 1, true) then
        setter(buffer, mark, 1, 0, opts)

        return
    end

    error(message, 0)
end

--- Source a saved native grapple marks file with guarded mark setting.
---
---@param path string The Lua file to source.
---@param root string The root used to resolve relative saved paths.
function _P.source_marks_file(path, root)
    local original_set_mark = vim.api.nvim_buf_set_mark
    local original_bufnr = vim.fn.bufnr
    local original_bufload = vim.fn.bufload

    rawset(vim.fn, "bufnr", function(name, create)
        if type(name) == "string" and not name:match("^%a:[/\\]") and not name:match("^/") then
            name = vim.fs.joinpath(root, name)
        end

        return original_bufnr(name, create)
    end)

    rawset(vim.fn, "bufload", function()
        return
    end)

    rawset(vim.api, "nvim_buf_set_mark", function(buffer, mark, line, column, opts)
        if not vim.api.nvim_buf_is_loaded(buffer) then
            vim.fn.setpos("'" .. mark, { buffer, line, column + 1, 0 })

            return
        end

        _P.set_mark_or_top(original_set_mark, buffer, mark, line, column, opts)
    end)

    local ok, message = pcall(dofile, path)

    rawset(vim.fn, "bufnr", original_bufnr)
    rawset(vim.fn, "bufload", original_bufload)
    rawset(vim.api, "nvim_buf_set_mark", original_set_mark)

    if not ok then
        error(message, 0)
    end
end

---@param root string The storage root that relative saved paths should resolve from.
---@param branch string The Git branch, or the non-Git fallback namespace.
---@return boolean # If a marks file was loaded, return true.
function M.load_branch_marks(root, branch)
    local path = _P.get_marks_path(root, branch)

    M.delete_all_bookmarks()

    if vim.fn.filereadable(path) ~= 1 then
        return false
    end

    local previous_directory = vim.fn.getcwd()
    local previous_shortmess = vim.o.shortmess

    vim.opt.shortmess:append("F")
    vim.cmd("noautocmd silent cd " .. vim.fn.fnameescape(root))

    local ok, message = pcall(_P.source_marks_file, path, root)

    vim.cmd("noautocmd silent cd " .. vim.fn.fnameescape(previous_directory))
    vim.o.shortmess = previous_shortmess

    if not ok then
        vim.notify(
            string.format('Could not load native grapple marks from "%s": %s', path, message),
            vim.log.levels.ERROR
        )

        return false
    end

    return true
end

--- Update loaded marks for the current cwd/root/branch when needed.
---
---@param reference_path string? Explicit path to use when resolving context.
---@param options {force: boolean}? Sync options.
function M.sync_branch(reference_path, options)
    options = options or {}

    local cwd = _P.get_reference_directory(reference_path)

    if not options.force and _STATE.cwd == cwd and _STATE.root and _STATE.branch then
        return
    end

    local context = _P.resolve_context(reference_path or cwd)

    if not options.force and _STATE.root == context.root and _STATE.branch == context.branch then
        _STATE.cwd = context.cwd
        _P.watch_head(context)

        return
    end

    M.write_current_branch_marks()
    M.delete_all_bookmarks()

    _STATE.cwd = context.cwd
    _STATE.root = context.root
    _STATE.branch = context.branch
    _STATE.git_dir = context.git_dir
    _STATE.head_path = context.head_path

    M.load_branch_marks(context.root, context.branch)
    _P.watch_head(context)
end

---@return string? # The current storage root.
function M.get_current_root()
    return _STATE.root
end

---@return string? # The current branch or non-Git namespace.
function M.get_current_branch()
    return _STATE.branch
end

--- Reset native grapple state for focused tests.
function M._reset_state_for_tests()
    _STATE.branch = nil
    _STATE.cwd = nil
    _STATE.git_dir = nil
    _STATE.head_path = nil
    _STATE.root = nil
end

--- Close watchers and reset state for tests or shutdown.
function M.teardown()
    if _BRANCH_RELOAD_TIMER:is_active() then
        _BRANCH_RELOAD_TIMER:stop()
    end

    for root, _ in pairs(_HEAD_WATCHERS_BY_ROOT) do
        _P.close_head_watcher(root)
    end

    M._reset_state_for_tests()
end

M._P = _P
M._STATE = _STATE
M._HEAD_WATCHERS_BY_ROOT = _HEAD_WATCHERS_BY_ROOT

return M
