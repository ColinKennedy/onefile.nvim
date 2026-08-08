--- A tiny Git-aware file tree browser.

local M = {}
local _P = {}

M._P = _P

local _FILETYPE = "filetree"
local _BUFFER_PREFIX = "filetree://"
local _AERIAL_FILETYPE = "aerial"
local _AERIAL_BUFFER_PREFIX = "aerial://"
local _SIDEBAR_WIDTH = 32
local _WATCH_DEBOUNCE_MS = 80
local _GROUP = vim.api.nvim_create_augroup("my.file_tree", { clear = true })
local _HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("my.file_tree")
local _STATE_BY_BUFFER = {}

---@alias _my.file_tree.Kind "directory"|"file"

---@class _my.file_tree.Entry
---@field path string Absolute path.
---@field name string Display basename.
---@field kind _my.file_tree.Kind Entry kind.
---@field depth integer Zero-based tree depth.

---@class _my.file_tree.State
---@field root string Absolute tree root.
---@field buffer integer Tree buffer.
---@field window integer Tree window.
---@field source_window integer Window to use when opening files/directories.
---@field show_all boolean Whether ignored/non-Git-visible files are shown.
---@field expanded table<string, boolean> Expanded directory paths.
---@field rows _my.file_tree.Entry[] Visible rows.
---@field watchers table<string, uv.uv_fs_event_t> Active directory watchers.
---@field refresh_timer uv.uv_timer_t? Debounced filesystem refresh timer.

---@class _my.file_tree.SessionEntry
---@field root string Absolute tree root.
---@field source_name string? Buffer name for the linked source window.
---@field expanded string[] Expanded directory paths.
---@field show_all boolean Whether ignored/non-Git-visible files are shown.
---@field source_window integer? Window to use when restoring from a stale session buffer.

---@return boolean
local function _is_nerdfont_allowed()
    return require("modules.utilities.fonts").is_nerdfont_allowed()
end

---@param path string
---@return boolean
local function _is_directory(path)
    local stat = vim.uv.fs_stat(path)

    return stat ~= nil and stat.type == "directory"
end

---@param path string
---@return string
local function _normalize(path)
    return vim.fs.normalize(path)
end

---@param path string
---@return string
function _P.get_icon(path)
    if _is_directory(path) then
        return _is_nerdfont_allowed() and "" or "D"
    end

    if not _is_nerdfont_allowed() then
        return "F"
    end

    local extension = vim.fn.fnamemodify(path, ":e")

    if extension == "py" then
        return ""
    elseif extension == "lua" then
        return ""
    elseif extension == "md" then
        return ""
    end

    return ""
end

--- Define file tree highlight groups.
function _P.set_highlights()
    vim.api.nvim_set_hl(0, "FileTreeDirectory", { link = "Directory", default = true })
    vim.api.nvim_set_hl(0, "FileTreeFile", { link = "String", default = true })
    vim.api.nvim_set_hl(0, "FileTreePython", { link = "Function", default = true })
end

---@param root string
---@param relative string
---@return string
local function _join_relative(root, relative)
    return _normalize(vim.fs.joinpath(root, relative))
end

---@param root string
---@return table<string, true>?
function _P.get_git_visible_paths(root)
    local result = vim.system({ "git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard" }, {
        text = true,
    }):wait()

    if result.code ~= 0 then
        return nil
    end

    ---@type table<string, true>
    local visible = {
        [_normalize(root)] = true,
    }

    for _, relative in ipairs(vim.split(result.stdout or "", "\n", { plain = true, trimempty = true })) do
        local path = _join_relative(root, relative)

        visible[path] = true

        local parent = _normalize(vim.fs.dirname(path))

        while parent ~= root and parent ~= "." and parent ~= "/" do
            visible[parent] = true
            parent = _normalize(vim.fs.dirname(parent))
        end
    end

    return visible
end

---@param path string
---@param visible table<string, true>?
---@param show_all boolean
---@return boolean
local function _should_include(path, visible, show_all)
    if vim.fs.basename(path) == ".git" then
        return false
    end

    return show_all or visible == nil or visible[path] == true
end

---@param left _my.file_tree.Entry
---@param right _my.file_tree.Entry
---@return boolean
local function _compare_entries(left, right)
    if left.kind ~= right.kind then
        return left.kind == "directory"
    end

    return left.name:lower() < right.name:lower()
end

---@param directory string
---@param depth integer
---@param show_all boolean
---@param visible table<string, true>?
---@return _my.file_tree.Entry[]
function _P.get_child_entries(directory, depth, show_all, visible)
    ---@type _my.file_tree.Entry[]
    local entries = {}

    if not _is_directory(directory) then
        return entries
    end

    local ok, iterator = pcall(vim.fs.dir, directory)

    if not ok or iterator == nil then
        return entries
    end

    for name, type_ in iterator do
        local path = _normalize(vim.fs.joinpath(directory, name))

        if _should_include(path, visible, show_all) then
            table.insert(entries, {
                depth = depth,
                kind = type_ == "directory" and "directory" or "file",
                name = name,
                path = path,
            })
        end
    end

    table.sort(entries, _compare_entries)

    return entries
end

---@param root string
---@param show_all boolean
---@param expanded table<string, boolean>
---@return _my.file_tree.Entry[]
function _P.build_rows(root, show_all, expanded)
    root = _normalize(root)

    local visible = show_all and nil or _P.get_git_visible_paths(root)
    ---@type _my.file_tree.Entry[]
    local rows = {}

    local function visit(directory, depth)
        for _, entry in ipairs(_P.get_child_entries(directory, depth, show_all, visible)) do
            table.insert(rows, entry)

            if entry.kind == "directory" and expanded[entry.path] then
                visit(entry.path, depth + 1)
            end
        end
    end

    visit(root, 0)

    return rows
end

---@param entry _my.file_tree.Entry
---@return string
function _P.render_entry(entry)
    local indent = string.rep("  ", entry.depth)
    local suffix = entry.kind == "directory" and "/" or ""

    return indent .. _P.get_icon(entry.path) .. " " .. entry.name .. suffix
end

---@param buffer integer
---@return boolean
local function _is_file_tree_buffer(buffer)
    return vim.bo[buffer].filetype == _FILETYPE or vim.startswith(vim.api.nvim_buf_get_name(buffer), _BUFFER_PREFIX)
end

---@param buffer integer
---@return boolean
local function _is_sidebar_buffer(buffer)
    local name = vim.api.nvim_buf_get_name(buffer)

    return _is_file_tree_buffer(buffer)
        or vim.bo[buffer].filetype == _AERIAL_FILETYPE
        or vim.startswith(name, _AERIAL_BUFFER_PREFIX)
end

---@param window integer
---@return boolean
local function _is_file_tree_window(window)
    return vim.api.nvim_win_is_valid(window) and _is_file_tree_buffer(vim.api.nvim_win_get_buf(window))
end

---@type fun(state: _my.file_tree.State)
local _render

---@type fun(state: _my.file_tree.State)
local _sync_watchers

---@param handle uv.uv_handle_t?
local function _close_handle(handle)
    if handle == nil or handle:is_closing() then
        return
    end

    handle:close()
end

---@param state _my.file_tree.State
local function _stop_refresh_timer(state)
    if state.refresh_timer == nil then
        return
    end

    state.refresh_timer:stop()
    _close_handle(state.refresh_timer)
    state.refresh_timer = nil
end

---@param state _my.file_tree.State
local function _stop_watchers(state)
    _stop_refresh_timer(state)

    for watcher_path, watcher in pairs(state.watchers) do
        watcher:stop()
        _close_handle(watcher)
        state.watchers[watcher_path] = nil
    end
end

---@param state _my.file_tree.State
local function _schedule_refresh(state)
    if not vim.api.nvim_buf_is_valid(state.buffer) then
        _stop_watchers(state)
        _STATE_BY_BUFFER[state.buffer] = nil

        return
    end

    if state.refresh_timer == nil then
        state.refresh_timer = vim.uv.new_timer()
    end

    state.refresh_timer:stop()
    state.refresh_timer:start(_WATCH_DEBOUNCE_MS, 0, function()
        vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(state.buffer) then
                _stop_watchers(state)
                _STATE_BY_BUFFER[state.buffer] = nil

                return
            end

            _render(state)
        end)
    end)
end

---@param state _my.file_tree.State
---@param watched_path string
local function _watch_directory(state, watched_path)
    if state.watchers[watched_path] ~= nil or not _is_directory(watched_path) then
        return
    end

    local watcher = vim.uv.new_fs_event()

    if watcher == nil then
        return
    end

    local ok = watcher:start(watched_path, {}, function(error_)
        if error_ ~= nil then
            return
        end

        vim.schedule(function()
            _schedule_refresh(state)
        end)
    end)

    if not ok then
        _close_handle(watcher)

        return
    end

    state.watchers[watched_path] = watcher
end

function _render(state)
    state.rows = _P.build_rows(state.root, state.show_all, state.expanded)

    ---@type string[]
    local lines = {}

    for _, entry in ipairs(state.rows) do
        table.insert(lines, _P.render_entry(entry))
    end

    if vim.tbl_isempty(lines) then
        table.insert(lines, "(empty)")
    end

    vim.bo[state.buffer].modifiable = true
    vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(state.buffer, _HIGHLIGHT_NAMESPACE, 0, -1)

    for index, entry in ipairs(state.rows) do
        local group = entry.kind == "directory" and "FileTreeDirectory" or "FileTreeFile"

        if vim.fn.fnamemodify(entry.path, ":e") == "py" then
            group = "FileTreePython"
        end

        vim.api.nvim_buf_set_extmark(state.buffer, _HIGHLIGHT_NAMESPACE, index - 1, 0, {
            end_col = #lines[index],
            hl_group = group,
        })
    end

    vim.bo[state.buffer].modifiable = false

    _sync_watchers(state)
end

function _sync_watchers(state)
    ---@type table<string, boolean>
    local wanted = {
        [state.root] = true,
    }

    for _, entry in ipairs(state.rows) do
        if entry.kind == "directory" then
            wanted[entry.path] = true
        end
    end

    for watched_path, watcher in pairs(state.watchers) do
        if not wanted[watched_path] or not _is_directory(watched_path) then
            watcher:stop()
            _close_handle(watcher)
            state.watchers[watched_path] = nil
        end
    end

    for watched_path in pairs(wanted) do
        _watch_directory(state, watched_path)
    end
end

---@param buffer integer?
---@return _my.file_tree.State?
local function _get_state(buffer)
    buffer = buffer or vim.api.nvim_get_current_buf()

    return _STATE_BY_BUFFER[buffer]
end

---@param state _my.file_tree.State
---@return _my.file_tree.Entry?
local function _get_current_entry(state)
    local line = vim.api.nvim_win_get_cursor(state.window)[1]

    return state.rows[line]
end

---@param window integer
---@return boolean
local function _can_focus_window(window)
    return window ~= 0 and vim.api.nvim_win_is_valid(window)
end

---@param path string
---@param root string
---@return boolean
local function _is_at_or_under(path, root)
    path = _normalize(path)
    root = _normalize(root)

    return path == root or vim.startswith(path, root .. "/")
end

---@param window integer
---@return boolean
local function _is_regular_source_window(window)
    return _can_focus_window(window)
        and vim.api.nvim_win_get_config(window).relative == ""
        and not _is_sidebar_buffer(vim.api.nvim_win_get_buf(window))
end

---@param state _my.file_tree.State
local function _focus_source_window(state)
    local alternate_window = vim.fn.win_getid(vim.fn.winnr("#"))

    if _can_focus_window(alternate_window) and not _is_file_tree_window(alternate_window) then
        state.source_window = alternate_window
        vim.api.nvim_set_current_win(alternate_window)

        return
    end

    if _can_focus_window(state.source_window) then
        vim.api.nvim_set_current_win(state.source_window)
    end
end

---@param state _my.file_tree.State
---@param path string
local function _edit_in_source_window(state, path)
    _focus_source_window(state)
    vim.cmd.edit(vim.fn.fnameescape(path))
end

--- Expand the directory under the cursor.
function M._expand()
    local state = _get_state()

    if not state then
        return
    end

    local entry = _get_current_entry(state)

    if entry and entry.kind == "directory" then
        state.expanded[entry.path] = true
        _render(state)
    end
end

--- Collapse the directory under the cursor.
function _P.collapse()
    local state = _get_state()

    if not state then
        return
    end

    local entry = _get_current_entry(state)

    if entry and entry.kind == "directory" then
        state.expanded[entry.path] = nil
        _render(state)
    end
end

---@param state _my.file_tree.State
---@param path string
---@param expanded boolean
local function _set_directory_expanded_recursively(state, path, expanded)
    local visible = state.show_all and nil or _P.get_git_visible_paths(state.root)

    local function visit(directory)
        if expanded then
            state.expanded[directory] = true
        else
            state.expanded[directory] = nil
        end

        for _, entry in ipairs(_P.get_child_entries(directory, 0, state.show_all, visible)) do
            if entry.kind == "directory" then
                visit(entry.path)
            end
        end
    end

    visit(path)
end

--- Expand the directory under the cursor and all of its descendants.
function M._expand_all()
    local state = _get_state()

    if not state then
        return
    end

    local entry = _get_current_entry(state)

    if entry and entry.kind == "directory" then
        _set_directory_expanded_recursively(state, entry.path, true)
        _render(state)
    end
end

--- Collapse the directory under the cursor and all of its descendants.
function M._collapse_all()
    local state = _get_state()

    if not state then
        return
    end

    local entry = _get_current_entry(state)

    if entry and entry.kind == "directory" then
        _set_directory_expanded_recursively(state, entry.path, false)
        _render(state)
    end
end

--- Open the file or directory under the cursor in the source window.
function M._open_entry()
    local state = _get_state()

    if not state then
        return
    end

    local entry = _get_current_entry(state)

    if entry then
        _edit_in_source_window(state, entry.path)
    end
end

--- Toggle ignored/non-Git-visible files in the current tree.
function M._toggle_show_all()
    local state = _get_state()

    if not state then
        return
    end

    state.show_all = not state.show_all
    _render(state)
end

---@param buffer integer
local function _configure_buffer(buffer)
    vim.bo[buffer].buftype = "nofile"
    vim.bo[buffer].bufhidden = "wipe"
    vim.bo[buffer].buflisted = false
    vim.bo[buffer].filetype = _FILETYPE
    vim.bo[buffer].modifiable = false
    vim.bo[buffer].swapfile = false
end

---@param buffer integer
local function _set_keymaps(buffer)
    local options = { buffer = buffer, nowait = true, silent = true }

    vim.keymap.set(
        "n",
        "h",
        _P.collapse,
        vim.tbl_extend("force", options, {
            desc = "Collapse directory.",
        })
    )
    vim.keymap.set(
        "n",
        "l",
        M._expand,
        vim.tbl_extend("force", options, {
            desc = "Expand directory.",
        })
    )
    vim.keymap.set(
        "n",
        "H",
        M._collapse_all,
        vim.tbl_extend("force", options, { desc = "Collapse directory recursively." })
    )
    vim.keymap.set(
        "n",
        "L",
        M._expand_all,
        vim.tbl_extend("force", options, { desc = "Expand directory recursively." })
    )
    vim.keymap.set(
        "n",
        "<CR>",
        M._open_entry,
        vim.tbl_extend("force", options, {
            desc = "Open file tree entry.",
        })
    )
    vim.keymap.set(
        "n",
        "<leader>sa",
        M._toggle_show_all,
        vim.tbl_extend("force", options, {
            desc = "Toggle showing all file tree entries.",
        })
    )
    vim.keymap.set("n", "q", _P.close, vim.tbl_extend("force", options, { desc = "Close file tree." }))
end

---@param state _my.file_tree.State
local function _open_window(state)
    vim.cmd("topleft " .. tostring(_SIDEBAR_WIDTH) .. "vsplit")
    state.window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.window, state.buffer)
    vim.api.nvim_win_set_width(state.window, _SIDEBAR_WIDTH)
    vim.wo[state.window].winfixbuf = true
end

---@param root string?
function M._open(root)
    root = _normalize(root or vim.fn.getcwd())

    local source_window = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_create_buf(false, true)
    local state = {
        buffer = buffer,
        expanded = { [root] = true },
        root = root,
        rows = {},
        show_all = false,
        source_window = source_window,
        watchers = {},
        window = 0,
    }

    _STATE_BY_BUFFER[buffer] = state
    _P.set_highlights()
    _configure_buffer(buffer)
    vim.api.nvim_buf_set_name(buffer, _BUFFER_PREFIX .. root)
    _open_window(state)
    _set_keymaps(buffer)
    _render(state)
end

--- Close the current file tree window.
function _P.close()
    local state = _get_state()

    if state and _can_focus_window(state.window) then
        _stop_watchers(state)
        vim.api.nvim_win_close(state.window, true)
    end
end

---@param source_name string
---@return integer?
local function _find_visible_source_window(source_name)
    local target = vim.fn.fnamemodify(source_name, ":p")

    for _, window in ipairs(vim.api.nvim_list_wins()) do
        if _is_regular_source_window(window) then
            local candidate = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(window)), ":p")

            if candidate == target then
                return window
            end
        end
    end

    return nil
end

---@return integer?
local function _find_any_visible_source_window()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        if _is_regular_source_window(window) then
            return window
        end
    end

    return nil
end

--- Close stale file tree windows restored by `:mksession`.
local function _close_visible_file_tree_windows()
    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)

        if _is_file_tree_buffer(buffer) or vim.startswith(vim.api.nvim_buf_get_name(buffer), _BUFFER_PREFIX) then
            local state = _STATE_BY_BUFFER[buffer]

            if state ~= nil then
                _stop_watchers(state)
            end

            pcall(vim.api.nvim_win_close, window, true)
            pcall(vim.api.nvim_buf_delete, buffer, { force = true })
            _STATE_BY_BUFFER[buffer] = nil
        end
    end
end

---@param session_root string? Only include trees under this session root.
---@return _my.file_tree.SessionEntry[]
function M._get_session_entries(session_root)
    ---@type _my.file_tree.SessionEntry[]
    local entries = {}

    for buffer, state in pairs(_STATE_BY_BUFFER) do
        local include_state = session_root == nil or _is_at_or_under(state.root, session_root)

        if include_state and vim.api.nvim_buf_is_valid(buffer) and _can_focus_window(state.window) then
            ---@type string[]
            local expanded = vim.tbl_keys(state.expanded)

            table.sort(expanded)
            table.insert(entries, {
                expanded = expanded,
                root = state.root,
                show_all = state.show_all,
                source_name = _is_regular_source_window(state.source_window) and vim.api.nvim_buf_get_name(
                    vim.api.nvim_win_get_buf(state.source_window)
                ) or nil,
            })
        end
    end

    table.sort(entries, function(left, right)
        return left.root < right.root
    end)

    return entries
end

---@return _my.file_tree.SessionEntry[]
function M._get_stale_session_entries()
    ---@type _my.file_tree.SessionEntry[]
    local entries = {}
    ---@type table<string, boolean>
    local seen = {}

    for _, window in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(window)
        local name = vim.api.nvim_buf_get_name(buffer)

        if vim.bo[buffer].filetype ~= _FILETYPE and vim.startswith(name, _BUFFER_PREFIX) then
            local root = _normalize(name:sub(#_BUFFER_PREFIX + 1))

            if root ~= "" and not seen[root] then
                table.insert(entries, {
                    expanded = { root },
                    root = root,
                    show_all = false,
                    source_window = window,
                })
                seen[root] = true
            end
        end
    end

    table.sort(entries, function(left, right)
        return left.root < right.root
    end)

    return entries
end

---@param entries _my.file_tree.SessionEntry[]
function M.restore_session(entries)
    local previous_window = vim.api.nvim_get_current_win()

    _close_visible_file_tree_windows()

    for _, entry in ipairs(entries) do
        if type(entry.root) == "string" and _is_directory(entry.root) then
            local source_window = nil

            if type(entry.source_name) == "string" then
                source_window = _find_visible_source_window(entry.source_name)
            end

            if source_window == nil and type(entry.source_window) == "number" then
                source_window = entry.source_window
            end

            if source_window == nil and _is_regular_source_window(previous_window) then
                source_window = previous_window
            end

            if source_window == nil then
                source_window = _find_any_visible_source_window()
            end

            if source_window ~= nil and _can_focus_window(source_window) then
                vim.api.nvim_set_current_win(source_window)
            end

            M._open(entry.root)

            local state = _get_state()

            if state ~= nil then
                state.source_window = source_window or state.source_window
                state.show_all = entry.show_all == true
                state.expanded = {}

                if type(entry.expanded) == "table" then
                    for _, expanded_path in ipairs(entry.expanded) do
                        if type(expanded_path) == "string" then
                            state.expanded[_normalize(expanded_path)] = true
                        end
                    end
                end

                state.expanded[state.root] = true
                _render(state)
            end
        end
    end

    if _can_focus_window(previous_window) then
        vim.api.nvim_set_current_win(previous_window)
    end
end

---@param session_root string? Only include trees under this session root.
---@return string
function M._serialize_session_restore(session_root)
    local entries = M._get_session_entries(session_root)

    if #entries == 0 then
        return ""
    end

    return 'require("modules.plugins.file_tree").restore_session(' .. vim.inspect(entries) .. ")"
end

--- Reopen file trees from stale `filetree://` windows created by `:mksession`.
function M._restore_stale_session_windows()
    local entries = M._get_stale_session_entries()

    if #entries == 0 then
        return
    end

    M.restore_session(entries)
end

--- Toggle a file tree for the current working directory.
function M._toggle()
    for buffer, state in pairs(_STATE_BY_BUFFER) do
        if vim.api.nvim_buf_is_valid(buffer) and _can_focus_window(state.window) then
            local current_window = vim.api.nvim_get_current_win()

            if not _is_file_tree_window(current_window) then
                state.source_window = current_window
            end

            vim.api.nvim_set_current_win(state.window)

            return
        end
    end

    M._open(vim.fn.getcwd())
end

vim.api.nvim_create_autocmd("BufWipeout", {
    group = _GROUP,
    callback = function(event)
        local state = _STATE_BY_BUFFER[event.buf]

        if state ~= nil then
            _stop_watchers(state)
        end

        _STATE_BY_BUFFER[event.buf] = nil
    end,
})

local core_editor_setup = require("modules.features.core_editor_setup")

core_editor_setup._SESSION_MANAGER:register_session_write_pre_callback(".file_tree.lua", function()
    local root = require("modules.utilities.core_helpers").get_nearest_project_root(vim.fn.getcwd())

    if root == nil then
        return ""
    end

    return M._serialize_session_restore(root)
end)

vim.api.nvim_create_autocmd("SessionLoadPost", {
    group = _GROUP,
    desc = "Restore file trees from session-created buffers.",
    callback = function()
        vim.schedule(M._restore_stale_session_windows)
    end,
})

vim.api.nvim_create_autocmd("VimEnter", {
    group = _GROUP,
    desc = "Restore file trees after startup session loading.",
    callback = function()
        if vim.v.this_session ~= "" then
            vim.schedule(M._restore_stale_session_windows)
        end
    end,
})

vim.api.nvim_create_user_command("FileTreeToggle", M._toggle, {
    desc = "Toggle the minimal file tree browser.",
})

vim.keymap.set("n", "<Space>F", M._toggle, { desc = "Toggle/Show the [f]ile tree." })

return M
