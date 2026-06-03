--- A tiny Git-aware file tree browser.

local M = {}
local _P = {}

M._P = _P

local _FILETYPE = "filetree"
local _BUFFER_PREFIX = "filetree://"
local _SIDEBAR_WIDTH = 32
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

    for name, type_ in vim.fs.dir(directory) do
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
    return vim.bo[buffer].filetype == _FILETYPE
end

---@param window integer
---@return boolean
local function _is_file_tree_window(window)
    return vim.api.nvim_win_is_valid(window) and _is_file_tree_buffer(vim.api.nvim_win_get_buf(window))
end

---@param state _my.file_tree.State
local function _render(state)
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
function M.expand()
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
function M.collapse()
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
function M.expand_all()
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
function M.collapse_all()
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
function M.open_entry()
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
function M.toggle_show_all()
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

    vim.keymap.set("n", "h", M.collapse, vim.tbl_extend("force", options, {
        desc = "Collapse directory.",
    }))
    vim.keymap.set("n", "l", M.expand, vim.tbl_extend("force", options, {
        desc = "Expand directory.",
    }))
    vim.keymap.set(
        "n",
        "H",
        M.collapse_all,
        vim.tbl_extend("force", options, { desc = "Collapse directory recursively." })
    )
    vim.keymap.set(
        "n",
        "L",
        M.expand_all,
        vim.tbl_extend("force", options, { desc = "Expand directory recursively." })
    )
    vim.keymap.set("n", "<CR>", M.open_entry, vim.tbl_extend("force", options, {
        desc = "Open file tree entry.",
    }))
    vim.keymap.set("n", "<leader>sa", M.toggle_show_all, vim.tbl_extend("force", options, {
        desc = "Toggle showing all file tree entries.",
    }))
    vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", options, { desc = "Close file tree." }))
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
function M.open(root)
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
function M.close()
    local state = _get_state()

    if state and _can_focus_window(state.window) then
        vim.api.nvim_win_close(state.window, true)
    end
end

--- Toggle a file tree for the current working directory.
function M.toggle()
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

    M.open(vim.fn.getcwd())
end

vim.api.nvim_create_autocmd("BufWipeout", {
    group = vim.api.nvim_create_augroup("my.file_tree", { clear = true }),
    callback = function(event)
        _STATE_BY_BUFFER[event.buf] = nil
    end,
})

vim.api.nvim_create_user_command("FileTreeToggle", M.toggle, {
    desc = "Toggle the minimal file tree browser.",
})

vim.keymap.set("n", "<Space>F", M.toggle, { desc = "Toggle/Show the [f]ile tree." })

return M
