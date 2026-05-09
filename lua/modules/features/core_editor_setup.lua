--- Configure core editor helpers for file selection, completions, snippets, git status, etc.

local M = {}
local _P = {}
local core_helpers = require("modules.utilities.core_helpers")


--- Find, select, and replace the current window with a new file.
---
--- Important:
---     This function requires [ripgrep](https://github.com/BurntSushi/ripgrep).
---
---@param root string?
---    A starting directory to searcn within, if any. If no directory is given,
---    Vim's current directory (`vim.fn.getcwd()`) is used instead.
---
function M.select_file_in_directory(root)
    if root then
        if vim.fn.isdirectory(root) ~= 1 then
            vim.notify(string.format('Value "%s" is not a directory.', root), vim.log.levels.ERROR)

            return
        end
    end

    root = root or vim.fn.getcwd()
    local command = { core_helpers._RIPGREP_EXECUTABLE, "--files", root }

    if not core_helpers.exists_command(command[1]) then
        vim.notify("Cannot do search. No `rg` command was found.", vim.log.levels.ERROR)

        return
    end

    local window = vim.api.nvim_get_current_win()

    local options = core_helpers.get_deferred_shell_command_results(command, function(obj)
        if obj.stdout == "" then
            -- NOTE: This happens when No files were found.
            vim.notify(string.format('Rg command found no files at "%s" directory.', root), vim.log.levels.ERROR)

            return
        end

        vim.notify(
            string.format('Rg command failed. See "%s" for details.', vim.inspect(obj)),
            vim.log.levels.ERROR
        )
    end)

    M.select_from_options(options, {
        confirm = function(entry)
            vim.api.nvim_set_current_win(window)
            vim.cmd.edit(entry.value)
        end,
        deserialize = function(choice)
            ---@cast choice string

            local display = choice
            root = root or vim.fn.getcwd()
            local relative = vim.fs.relpath(root, display)

            if relative then
                display = relative
            end

            return { display = display, value = choice }
        end,
    })
end

--- Find the top of the project, if any, and then search for files.
function M.select_file_from_project_root()
    local buffer = vim.api.nvim_get_current_buf()
    local root = core_helpers.get_nearest_project_root(buffer)

    if not root then
        vim.notify(string.format('Buffer "%s" has no root.', buffer), vim.log.levels.ERROR)

        return
    end

    M.select_file_in_directory(root)
end

--- Run `callback` on a single selection of `options`.
---
--- This function creates a "telescope.nvim-lite" floating window picker.
---
---@param values string[]
---    The possible values to select from.
---@param options _my.selection_gui.GuiOptions
---    A function run to run on-selection. e.g. "open the file in a buffer".
---
function M.select_from_options(values, options)
    --- Pass `value` through and just return it.
    ---
    ---@generic T : any
    ---@param value T Some value to return.
    ---@return T # The returned value.
    ---
    local function _passthrough(value)
        return value
    end

    ---@generic T: any
    --- A dynamic `ipairs`.
    ---
    --- It can iterate over a table that is growing asynchronously at the same
    --- time as it is iterating.
    ---
    ---@param table_ T[] Some values to iterate over.
    ---@return fun(): [integer, T]? # A function that iterates over `table_` (basically `ipairs`).
    ---
    local function _dynamic_ipairs(table_)
        local index = 0

        return function()
            index = index + 1
            local value = table_[index]

            if value == nil then
                return nil
            end

            return index, value
        end
    end

    ---@type _my.selector_gui.State
    local state = { input = "", all = values, filtered = {}, selected = 1 }

    local columns = vim.o.columns
    local lines = vim.o.lines

    local margin = 0.05 -- NOTE: Apply a 5% margin to the floating window
    local margin_x = math.floor(columns * margin)
    local margin_y = math.floor(lines * margin)

    -- List window dimensions
    local list_width = columns - (margin_x * 2) - 2
    local list_height = lines - (margin_y * 2) - 5
    local list_row = margin_y + 1
    local list_column = margin_x + 1

    -- Prompt window dimensions
    local prompt_width = list_width
    local prompt_height = 1
    local prompt_row = list_row - 2
    local prompt_column = list_column

    -- Create list buffer and window
    local list_buffer = vim.api.nvim_create_buf(false, true)
    local list_window = vim.api.nvim_open_win(list_buffer, true, {
        relative = "editor",
        width = list_width,
        height = list_height,
        row = list_row,
        col = list_column,
        style = "minimal",
        border = "single",
    })

    -- Create prompt buffer and window
    local prompt_buffer = vim.api.nvim_create_buf(false, true)
    local prompt_window = vim.api.nvim_open_win(prompt_buffer, false, {
        relative = "editor",
        width = prompt_width,
        height = prompt_height,
        row = prompt_row,
        col = prompt_column,
        style = "minimal",
        border = "single",
    })
    vim.api.nvim_buf_set_lines(prompt_buffer, 0, -1, false, { "" })

    -- Start in insert mode in prompt
    vim.api.nvim_set_current_win(prompt_window)
    vim.cmd("startinsert")

    if options.input and options.input ~= "" then
        vim.api.nvim_feedkeys(options.input, "i", false)
    end

    --- Redraw the current, filtered list.
    local function _redraw()
        -- TODO: Don't redraw the whole buffer. This is slow.
        vim.api.nvim_buf_set_lines(list_buffer, 0, -1, false, {})

        for index, item in ipairs(state.filtered) do
            local prefix = (index == state.selected) and "> " or "  "
            vim.api.nvim_buf_set_lines(list_buffer, index, index, false, { prefix .. item.display })
        end
    end

    --- Populate filtered items.
    local function _update_filter()
        local line = vim.api.nvim_buf_get_lines(prompt_buffer, 0, 1, false)[1]
        state.input = line or ""
        state.filtered = {}

        ---@type _my.selector_gui.entry.Selection[]
        local matches = {}

        local deserializer = options.deserialize or _passthrough

        for _, item in _dynamic_ipairs(state.all) do
            local entry = deserializer(item)
            local score = core_helpers.get_fuzzy_match_score(state.input, entry.display or entry.value)

            if score then
                table.insert(matches, { display = entry.display, score = score, value = entry.value })
            end
        end

        table.sort(matches, function(left, right)
            return left.score > right.score
        end)

        for _, entry in ipairs(matches) do
            table.insert(state.filtered, entry)
        end

        state.selected = math.min(state.selected, #state.filtered)

        -- NOTE: We always select one entry, here.
        if state.selected < 1 then
            state.selected = 1
        end

        _redraw()
    end

    --- Close all search-related floating windows.
    local function _close_all()
        vim.api.nvim_win_close(list_window, true)
        vim.api.nvim_win_close(prompt_window, true)
    end

    --- Get the selected item, close all the windows, and do something with the selection.
    ---
    --- The "do something" part is defined by `options`. We don't control any
    --- part of what happens next.
    ---
    local function _confirm_selection()
        _close_all()

        local entry = state.filtered[state.selected]
        options.confirm(entry)
    end

    --- Don't select anything from the search and just close all of the windows.
    local function _cancel()
        _close_all()

        local entry = state.filtered[state.selected]

        if options.cancel then
            options.cancel(entry)
        else
            vim.notify("Selection Cancelled", vim.log.levels.INFO)
        end
    end

    --- Set up keymaps for list window navigation
    local function _setup_keys()
        local opts = { noremap = true, silent = true, buffer = prompt_buffer }
        local confirm_options = vim.tbl_deep_extend("force", opts, { desc = "Confirm your current selection." })
        vim.keymap.set("n", "<CR>", vim.schedule_wrap(_confirm_selection), confirm_options)
        vim.keymap.set("i", "<CR>", function()
            -- Exit to NORMAL mode first before confirming the slection
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
            vim.schedule(_confirm_selection)
        end, confirm_options)

        local cancel_options = vim.tbl_deep_extend("force", opts, { desc = "Cancel and quit." })
        vim.keymap.set("n", "q", _cancel, cancel_options)
        vim.keymap.set("n", "<C-c>", _cancel, cancel_options)
        vim.keymap.set("n", "<Esc>", _cancel, cancel_options)

        local select_down = function()
            state.selected = math.min(state.selected + 1, #state.filtered)
            _redraw()
        end

        local select_up = function()
            state.selected = math.max(state.selected - 1, 1)
            _redraw()
        end

        local down_options =
            vim.tbl_deep_extend("force", opts, { desc = "Select the item below the current selection." })
        local up_options =
            vim.tbl_deep_extend("force", opts, { desc = "Select the item above the current selection." })
        vim.keymap.set("n", "j", select_down, down_options)
        vim.keymap.set("i", "<C-n>", select_down, down_options)

        vim.keymap.set("n", "k", select_up, up_options)
        vim.keymap.set("i", "<C-p>", select_up, up_options)
    end

    _setup_keys()
    _redraw()

    -- This creates a "live-update" of options while the user is typing
    -- TODO: Consider a debounce here, maybe
    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI", "TextChanged", "TextChangedI" }, {
        buffer = prompt_buffer,
        callback = vim.schedule_wrap(_update_filter),
    })
end

--- Write Lua source code that shows how to save/restore bookmarks.
---
---@param directory string? The folder on-disk where all mark files will be relative to.
---@return string[] # All of the Lua source-code.
---
function M.serialize_mark_code(directory)
    if directory then
        directory = vim.fn.expand(directory)
    end

    ---@type string[]
    local output = {}
    local marks = core_helpers.get_marks_mapping()

    for index, _, _ in core_helpers.iter_bookmarks() do
        local mark_character = core_helpers.get_vim_mark_from_bookmark_index(index)

        local mark = marks["'" .. mark_character]

        if mark and mark.file ~= "" then
            local path = vim.fn.expand(mark.file)

            if directory then
                local success, relative = pcall(function()
                    return vim.fs.relpath(directory, path)
                end)

                if success and relative then
                    path = relative
                end
            end

            local _, line, column, _ = unpack(mark.pos)

            table.insert(
                output,
                table.concat({
                    string.format('buffer = vim.fn.bufnr("%s", true)', path),
                    "vim.fn.bufload(buffer)",
                    string.format('vim.api.nvim_buf_set_mark(buffer, "%s", %d, %d, {})', mark_character, line, column),
                    "",
                    "",
                }, "\n")
            )
        end
    end

    if vim.tbl_isempty(output) then
        table.insert(output, 0, "local buffer")
        table.insert(output, 0, "local original_buffer = vim.api.nvim_get_current_buf()")
        table.insert(output, "vim.cmd.buffer(original_buffer)")
    end

    return output
end

--- Add LSP keymaps and auto-completion.
---
--- Run this function on-LSP-initialization. See `:help LspAttach`.
---
---@param args _my.lsp_attach.Result Data from Neovim LspAttach.
---
function M.setup_lsp_details(args)
    local buffer = vim.api.nvim_get_current_buf()

    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, {
        buffer = buffer,
        desc = "[g]o to all [D]eclarations of the current function, class, whatever.",
    })

    vim.keymap.set("n", "gd", vim.lsp.buf.definition, {
        buffer = buffer,
        desc = "[g]o to [d]efinition of the function / class.",
    })

    vim.keymap.set("n", "gi", vim.lsp.buf.implementation, {
        buffer = buffer,
        desc = "Find and [g]o to the [i]mplementation of some header / declaration.",
    })

    vim.keymap.set("i", "<C-k>", function()
        -- Reference: https://github.com/neovim/neovim/issues/37191
        vim.lsp.buf.hover({ zindex = 300 })
    end, { desc = "Show documentation for the current WORD under the cursor." })

    local identifier = args.data.client_id
    local client = assert(
        vim.lsp.get_client_by_id(identifier),
        string.format('Identifier "%s" has no LSP client.', identifier)
    )

    if client:supports_method("textDocument/completion") then
        -- NOTE: Automatic LSP auto-complete + we can still use <C-x><C-o>
        -- to trigger manually (because we have `:set omnifunc=v:lua.vim.lsp.omnifunc`)
        --
        vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
        vim.opt_local.completeopt = { "fuzzy", "menuone", "noinsert", "noselect" }
        -- NOTE: This line adds omnifunc (LSP) as a completion source.
        vim.opt_local.complete:append("o")
    end

    vim.o.pumheight = 5 -- NOTE: Only the top 5 suggestions are shown
    vim.o.winborder = "rounded"
end

--- Assign a range selection in Vim (a 2-cursor bounding box).
---
---@param start_line integer A 1-or-more value, the first source code line.
---@param start_column integer A 1-or-more value. The position in the start line.
---@param end_line integer A 1-or-more value, the last source code line.
---@param end_column integer A 1-or-more value. The position in the end line.
---
function M.set_text_object_marks(start_line, start_column, end_line, end_column)
    vim.api.nvim_buf_set_mark(0, "<", start_line, start_column, {})
    vim.api.nvim_buf_set_mark(0, ">", end_line, end_column, {})

    local mode = vim.api.nvim_get_mode().mode

    if mode == "V" then
        vim.cmd("normal! gV")
    else
        vim.cmd("normal! gv")
    end
end

--- Load current bookmarks into the quickfix list.
function M.show_bookmarks()
    ---@type vim.quickfix.entry[]
    local quickfix_entries = {}

    for index = core_helpers._BOOKMARK_MINIMUM, core_helpers._BOOKMARK_MAXIMUM do
        local mark = core_helpers.get_vim_mark_from_bookmark_index(index)
        local position = vim.api.nvim_get_mark(mark, {})

        if position[1] ~= 0 then
            table.insert(quickfix_entries, {
                bufnr = position[3],
                filename = position[4],
                lnum = position[1],
                col = position[2],
                text = index,
            })
        end
    end

    -- Set the quickfix list
    vim.fn.setqflist(quickfix_entries)

    -- Open the quickfix window if there are bookmarks
    if #quickfix_entries > 0 then
        vim.cmd("copen")
    else
        vim.cmd("cclose")
    end
end

--- Show all git stashes in the repository in a floating window, if any.
function M.show_git_stashes()
    local command = { core_helpers._GIT_EXECUTABLE, "stash", "list" }

    if not core_helpers.exists_command(command[1]) then
        vim.notify("Cannot create state. No `git` command was found.", vim.log.levels.ERROR)

        return
    end

    local options = core_helpers.get_deferred_shell_command_results(command)

    M.select_from_options(options, {
        deserialize = function(value)
            local separator = ":"
            local parts = vim.fn.split(value, separator)

            if #parts < 3 then
                error(
                    string.format(
                        'Got unexpected "%s" parts from "%s" value. ' .. "Expected a stash index and stash name.",
                        vim.inspect(parts),
                        value
                    )
                )
            end

            ---@type string[]
            local name_parts = {}

            for index = 3, #parts do
                table.insert(name_parts, parts[index])
            end

            local name = vim.fn.join(name_parts, separator)
            local index = parts[1]

            return { display = name, value = { index = index, name = name } }
        end,
        confirm = function(entry)
            local stash = entry.value.index
            local process = vim.system({ core_helpers._GIT_EXECUTABLE, "stash", "apply", stash }):wait()

            if process.code == 0 then
                return
            end

            -- NOTE: For some reason the error is in stdout
            local error_message = process.stdout

            vim.notify(
                string.format("Git stash apply failed. See below:\n\n%s", error_message),
                vim.log.levels.ERROR
            )
        end,
    })
end

--- Load snippets and show them, if possible.
function M.show_snippet_completion()
    --- Remove the original trigger text (so we can replace it with the completed text).
    ---
    --- Important:
    ---     This function assumes that
    ---     1. We just triggered snippet completion.
    ---     2. The cursor is located at the *end* of the trigger text.
    ---
    ---@param window integer The Vim window to affect.
    ---@param start_column integer A 1-or-more Lua value.
    ---
    local function _delete_trigger_text(window, start_column)
        local row, column = unpack(vim.api.nvim_win_get_cursor(window))
        local line = vim.api.nvim_get_current_line()

        line = line:sub(1, start_column) .. line:sub(column + 1)
        vim.api.nvim_set_current_line(line)
        vim.api.nvim_win_set_cursor(0, { row, start_column })
    end

    --- Expand the snippet found in `data`.
    ---
    ---@param data _my.completion.Data
    ---
    local function _expand_snippet(data)
        local snippet = core_helpers._TRIGGER_TO_SNIPPET_CACHE[data.completed.word]

        if not snippet then
            return
        end

        vim.snippet.expand(snippet.body)
    end

    --- Delete the initial trigger text and expand the snippet
    ---
    ---@param start_column integer A 1-or-more Lua value where `callback` runs from.
    ---@param callback fun(data: _my.completion.Data): nil Run this on-completion.
    ---
    local function _handle_complete_done(start_column, callback)
        local completed = vim.v.completed_item

        if not completed or completed.word == "" then
            return
        end

        local window = 0 -- NOTE: The current window
        _delete_trigger_text(window, start_column)

        callback({ completed = completed })
    end

    local start_column, base = core_helpers.get_completion_location()
    local candidates =
        core_helpers.compute_snippet_completion_options({ file_type = vim.o.filetype, start_column = start_column - 1 })
    local matches = core_helpers.filter_by_text(candidates, base)
    table.sort(matches, function(left, right)
        return left.word < right.word
    end)

    vim.fn.complete(start_column, matches)

    vim.api.nvim_create_autocmd("CompleteDone", {
        group = core_helpers._SNIPPET_AUGROUP,
        callback = function()
            _handle_complete_done(start_column - 1, _expand_snippet)
        end,
        once = true,
    })
end

-- TODO: I'm shocked that Neovim doesn't have a function for this already
--- Parse a string like `foo "bar fizz" buzz"` into `{"foo", "bar fizz", "buzz"}`.
---
--- Reference: https://stackoverflow.com/a/28664691/3626104
---
---@param text string Some raw command string.
---@return string[] # The parsed text.
---
function M.split_quoted_string(text)
    local spat, epat = [=[^(['"])]=], [=[(['"])$]=]
    local buf
    local quoted

    ---@type string[]
    local output = {}

    for str in text:gmatch("%S+") do
        local squoted = str:match(spat)
        local equoted = str:match(epat)
        local escaped = str:match([=[(\*)['"]$]=])

        if squoted and not quoted and not equoted then
            buf, quoted = str, squoted
        elseif buf and equoted == quoted and #escaped % 2 == 0 then
            str, buf, quoted = buf .. " " .. str, nil, nil
        elseif buf then
            buf = buf .. " " .. str
        end

        if not buf then
            table.insert(output, (str:gsub(spat, ""):gsub(epat, "")))
        end
    end

    if buf then
        table.insert(output, buf)
    end

    return output
end

--- Strip the leading whitespace of `text`.
---
---@param text string Some text to strip. e.g. `"    foo"`.
---@return string # The stripped text. e.g. `"foo"`.
---
function M.strip_left(text)
    return (text:gsub("^%s*", ""))
end

local SessionManager = {}
SessionManager.__index = SessionManager

--- Create a new instance of `SessionManager`.
function SessionManager.new()
    local self = setmetatable({}, SessionManager)

    self._callbacks = {} ---@type table<string, fun(): string>

    vim.api.nvim_create_autocmd("SessionWritePost", {
        callback = function()
            self:write_current_session()
        end,
    })

    return self
end

--- Write `contents` to `path` easily.
---
---@param path string Some file location on-disk to write to.
---@param contents string The blob of text to write.
---
local function write_file(path, contents)
    local handler = assert(io.open(path, "w"))
    handler:write(contents)
    handler:close()
end

--- Find the "branch-aware" internal session path associated with `name`.
---
---@param name string Some unique file name to search within for a path.
---@param root string Use this path to find the git repository.
---@return string # The found path. Usually it's `{VCS}/.sessions/{git branch name}/{name}`.
---
function _P.get_branch_path(name, root)
    local branch = M.get_git_branch_safe(root)

    if not branch then
        error(string.format('Cannot save "%s" project. No branch was found.', root))
    end

    return vim.fs.joinpath(root, core_helpers._SESSIONS_DIRECTORY_NAME, branch, name)
end

--- Find the currently-active VCS branch name from `root`
---
---@param root string Use this path to find the git repository.
---@return string # The found git branch name.
---
function SessionManager:_get_active_branch_name(root)
    local path = _P.get_branch_path("placeholder", root)

    return vim.fs.basename(vim.fs.dirname(path))
end

--- Recommend a git branch name to write to some Vimscript.
---
---@param root string Use this path to find the git repository.
---@return string # The Vimscript header to write out to-disk, later.
---
function SessionManager:_get_header_vcs_text(root)
    local branch = self:_get_active_branch_name(root)

    return string.format("\" SESSION MANAGER v1.0.0: '%s'", vim.pesc(branch))
end

--- Read `path` for a SessionManager-backed branch name.
---
--- This function assumes there is a header comment at the top file that
--- indicates the branch.
---
---@param path string The Vimscript path on-disk to read.
---@return string # The found (git) branch name.
---
function SessionManager:_get_stored_branch_name(path)
    local function _get_branch_name(path_)
        for line in io.lines(path_) do
            if not line:match("^%s*$") then
                local stripped = M.strip_left(line)

                if not vim.startswith(stripped, core_helpers._VIMSCRIPT_COMMENT_MARKER) then
                    return nil
                end

                local match = stripped:match("^%s*\" SESSION MANAGER v%d+[%.%d+]*: '([^']+)'")

                if match then
                    return match
                end
            end
        end

        return nil
    end

    local branch = _get_branch_name(path)

    if branch then
        return branch
    end

    error(string.format('We couldn\'t find a branch for "%s" path.', path))
end

--- Get the top-level Sessionx.vim file from some `directory`.
---
---@param directory string | integer The child directory to search for a VCS root.
---@return string # The recommended path (which may or may not exist on-disk).
---
function SessionManager:_get_vcs_root_sessionx_file(directory)
    local root = core_helpers.get_nearest_project_root(directory)

    if not root then
        error(string.format('Directory "%s" has no VCS root. Cannot sync a session.', directory))
    end

    return vim.fs.joinpath(root, core_helpers._SESSIONX_NAME)
end

--- Generate a session-related `name` file later, using the output of `callback`.
---
---@param name string Some unique file name to register.
---@param callback fun(): string We call this function to fill `name` with data, later.
---
function SessionManager:register_session_write_pre_callback(name, callback)
    assert(not name:find("[/\\]"), "name must not contain a path")

    local keys = vim.tbl_keys(self._callbacks)

    if vim.tbl_contains(keys, name) then
        error(string.format('Name "%s" is already in "%s".', name, vim.inspect(keys)))
    end

    self._callbacks[name] = callback
end

--- Check if our Sessionx.vim is out of date and, if so, replace it.
---
--- If someone externally altered the git branch or something, the current
--- Sessionx.vim file on-disk could be out-of-date. This method treats the git
--- branch as the ground truth and replaces the Sessionx.vim file to match it.
---
function SessionManager:sync_current_session()
    local directory = vim.fn.getcwd()
    local active_branch = self:_get_active_branch_name(directory)

    local root_session = self:_get_vcs_root_sessionx_file(directory)

    if vim.fn.filereadable(root_session) ~= 1 then
        return
    end

    local stored_branch = self:_get_stored_branch_name(root_session)

    if active_branch == stored_branch then
        return
    end

    local root = core_helpers.get_nearest_project_root(directory)

    if not root then
        error(string.format('No VCS root was found for "%s" directory.', directory))
    end

    local sessionx_destination = _P.get_branch_path(core_helpers._SESSIONX_NAME, root)

    if vim.fn.filereadable(sessionx_destination) ~= 1 then
        -- NOTE: This would only happen if a session was not saved for the git
        -- branch at least once already. It's unlikely but could happen. Just
        -- let it go if it does.
        --
        return
    end

    local root_destination = vim.fs.joinpath(root, core_helpers._SESSIONX_NAME)
    vim.uv.fs_copyfile(sessionx_destination, root_destination)
end

--- Copy all session-related files to the VCS root.
---
--- Raises:
---     If the session could not be written to-disk.
---
function SessionManager:write_current_session()
    local directory = vim.fn.getcwd()
    local root = core_helpers.get_nearest_project_root(directory)

    if not root then
        error(string.format('Directory "%s" has no VCS root. Cannot sync a session.', directory))
    end

    local paths = {} ---@type string[]

    for name, callback in pairs(self._callbacks) do
        local destination = _P.get_branch_path(name, root)
        vim.fn.mkdir(vim.fs.dirname(destination), "p")
        write_file(destination, callback())
        table.insert(paths, destination)
    end

    local sessionx_destination = _P.get_branch_path(core_helpers._SESSIONX_NAME, root)

    local handler, error_ = io.open(sessionx_destination, "w")
    assert(handler, error_)

    handler:write(self:_get_header_vcs_text(root) .. "\n")

    for _, path in ipairs(paths) do
        handler:write(string.format("source %s", path), "\n")
    end

    handler:close()

    local root_destination = vim.fs.joinpath(root, core_helpers._SESSIONX_NAME)
    vim.uv.fs_copyfile(sessionx_destination, root_destination)
end

M._SESSION_MANAGER = SessionManager.new()

--- Unset the bookmark if it is set or set it if it's not set.
function M.toggle_bookmark_in_current_buffer()
    --- Delete and re-add all bookmarks.
    ---
    --- Bookmarks can sometimes become internally messy and tis function just
    --- forces them to be clean and contiguous.
    ---
    local function _refresh_all_bookmark_values()
        ---@type {index: integer?, path: string?}[]
        local buffers = {}

        for _, buffer_number, buffer_path in core_helpers.iter_bookmarks() do
            if buffer_number == 0 then
                table.insert(buffers, { path = buffer_path })
            else
                table.insert(buffers, { index = buffer_number })
            end
        end

        core_helpers.delete_all_bookmarks()

        for new_index, buffer in ipairs(buffers) do
            local value = buffer.index or buffer.path

            if not value then
                error(string.format('Buffer "%s" has no index or path.', vim.inspect(buffer)), 0)
            end

            local mark = core_helpers.get_vim_mark_from_bookmark_index(new_index)
            core_helpers.reset_bookmark(mark, value)
        end
    end

    --- Add the current buffer to the bookmarks list if it isn't already.
    local function _add_current_buffer_if_needed()
        local current_buffer = vim.api.nvim_get_current_buf()
        ---@type integer[]
        local current_buffer_bookmarks = {}

        for index, buffer_number, _ in core_helpers.iter_bookmarks() do
            -- NOTE: Don't add the current buffer because it's already in the list
            if buffer_number == current_buffer then
                table.insert(current_buffer_bookmarks, index)

                break
            end
        end

        if vim.tbl_isempty(current_buffer_bookmarks) then
            core_helpers.mark_current_buffer_as_next_bookmark()
        else
            for _, mark_index in ipairs(current_buffer_bookmarks) do
                local mark = core_helpers.get_vim_mark_from_bookmark_index(mark_index)
                vim.cmd.delmarks(mark)
            end
        end
    end

    _add_current_buffer_if_needed()
    _refresh_all_bookmark_values()

    M._SESSION_MANAGER:write_current_session()
end

--- Open or close the QuickFix window (don't move the cursor to the window).
function M.toggle_quickfix()
    local current_window = vim.api.nvim_get_current_win()

    for _, window in ipairs(vim.fn.getwininfo()) do
        if window.quickfix == 1 then
            vim.cmd.cclose()

            return
        end
    end

    vim.cmd.copen()

    -- NOTE: If we were on a non-quickfix window, go back to that window
    local info = vim.fn.getwininfo(current_window)

    if info[1] and info[1].quickfix ~= 1 then
        vim.api.nvim_set_current_win(current_window)
    end
end

--- Write `data` to `filename`.
---
---@param filename string The file on-disk to write to.
---@param data string[] The file contents to write.
---@return boolean # If the write worked, return `true`.
---@return string # If the write failed, this is the error message.
---
function M.write_async(filename, data)
    local status = true
    local message = ""
    local handler, open_error, _ = vim.uv.fs_open(filename, "w", 438)

    if not handler then
        status, message = false, ("Failed to open: %s\n%s"):format(filename, open_error)
    else
        local ok, write_error, _ = vim.uv.fs_write(handler, data, 0)

        if not ok then
            status, message = false, ("Failed to write: %s\n%s"):format(filename, write_error)
        end

        assert(vim.uv.fs_close(handler), 'Path "%s" could not be closed.', filename)
    end

    return status, message
end

--- Find the git branch name, if any.
---
---@param path string? Use this path to find the git repository. If not provided, we use Vim's own $PWD instead.
---@return string? # Get the current Git branch, if any.
---
function M.get_git_branch_safe(path)
    local command = { core_helpers._GIT_EXECUTABLE, "rev-parse", "--abbrev-ref", "HEAD" }

    if path then
        vim.list_extend(command, { "-C", path })
    end

    if not core_helpers.exists_command(command[1]) then
        return nil
    end

    local process = vim.system(command, { text = true }):wait()

    if process.code ~= 0 then
        return nil
    end

    local branch = vim.split(process.stdout, "\n", { plain = true })[1]

    if branch == "" then
        return nil
    end

    return branch
end

---@return string # Get a human-readable git branch name, if possible.
function M.get_git_branch_label_safe()
    local command = { core_helpers._GIT_EXECUTABLE, "rev-parse", "--abbrev-ref", "HEAD" }

    if not core_helpers.exists_command(command[1]) then
        return "<No git command>"
    end

    local process = vim.system(command, { text = true }):wait()

    if process.code ~= 0 then
        return "<Git command failed>"
    end

    local branch = process.stdout:gsub("\n", "")

    if branch == "" then
        return "<No git branch found>"
    end

    local git_prefix = "git "

    if core_helpers._IS_NERDFONT_ALLOWED then
        git_prefix = " "
    end

    return git_prefix .. branch
end

---@return string # Get the position in the current file.
-- luacheck: push ignore
function get_window_line_progress()
    -- luacheck: pop
    local current_line = vim.fn.line(".")
    local total_lines = vim.fn.line("$")

    if current_line == 1 then
        return "Top"
    end

    if current_line == total_lines then
        return "Bot"
    end

    local percent = math.floor((current_line / total_lines) * 100)

    return percent .. "%"
end

-- Example Run: PATH=/home/selecaoone/.local/bin:$PATH NVIM_APPNAME=noplugins nvim ~/temp/class_test.py

vim.g.mapleader = ","

-- Enable messages during File operations
--
-- Reference: https://vi.stackexchange.com/a/26492
-- Reference: https://neovim.io/doc/user/faq.html#faq
--
vim.cmd("set shortmess-=F")

---------- Auto-Commands [Start] ----------
is_ignoring_syntax_events = function()
    for _, value in pairs(vim.opt.eventignore) do
        if value == "Syntax" then
            return true
        end
    end

    return false
end

-- Remove the column-highlight on QuickFix & LocationList buffers
vim.api.nvim_create_autocmd("FileType", {
    pattern = "qf",
    command = "setlocal nonumber colorcolumn=",
})

vim.api.nvim_create_autocmd("FileType", {
    callback = function()
        vim.keymap.set("n", "<leader>ct", function()
            local current_name = vim.fn.getqflist({ title = true, winid = true }).title
            local name = vim.fn.input("New Name: ", current_name)

            if name == "" then
                return
            end

            vim.fn.setqflist({}, "r", { title = name, winid = true })

            local success, winbar = pcall(require, "winbar")

            if success then
                winbar.run_on_current_buffer()
            end
        end, {
            buffer = true,
            desc = "[c]hange Quickfix [t]itle.",
        })
    end,
    pattern = "qf",
})

-- Reference: https://stackoverflow.com/questions/12485981
--
-- Enable syntax highlighting when buffers are displayed in a window through
-- :argdo and :bufdo, which disable the Syntax autocmd event to speed up
-- processing.
--
_SYNTAX_HIGHLIGHTING_GROUP = vim.api.nvim_create_augroup("my.highlighter", { clear = true })

vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    callback = function()
        if not vim.fn.exists("syntax_on") then
            return
        end

        if vim.fn.exists("b:current_syntax") then
            return
        end

        if not vim.bo.filetype then
            return
        end

        if is_ignoring_syntax_events() then
            return
        end

        vim.cmd("syntax enable")
    end,
    nested = true,
    pattern = "*",
    group = _SYNTAX_HIGHLIGHTING_GROUP,
})

-- The above does not handle reloading via :bufdo edit!, because the
-- b:current_syntax variable is not cleared by that. During the :bufdo,
-- 'eventignore' contains "Syntax", so this can be used to detect this
-- situation when the file is re-read into the buffer. Due to the
-- 'eventignore', an immediate :syntax enable is ignored, but by clearing
-- b:current_syntax, the above handler will do this when the reloaded buffer
-- is displayed in a window again.
--
vim.api.nvim_create_autocmd("BufRead", {
    callback = function()
        if not vim.fn.exists("b:current_syntax") then
            return
        end

        -- TODO: Check if this is needed
        if not vim.fn.exists("syntax_on") then
            return
        end

        -- TODO: Check if this is needed
        if vim.bo.filetype then
            return
        end

        -- TODO: Check if this is needed
        if not is_ignoring_syntax_events() then
            return
        end

        vim.cmd("unlet! b:current_syntax")
    end,
    pattern = "*",
})

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.highlight.on_yank()`
vim.api.nvim_create_autocmd("TextYankPost", {
    desc = "Highlight when yanking (copying) text",
    group = vim.api.nvim_create_augroup("my.highlight.yank", { clear = true }),
    callback = function()
        vim.highlight.on_yank()
    end,
})

--- @return boolean # Check if the current buffer is an fzf prompt
is_fzf_terminal = function()
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    local ending = ";#FZF"

    return name:sub(-#ending) == ending
end

-- Switch from the terminal window back to other buffers quickly
-- Reference: https://github.com/junegunn/fzf.vim/issues/544#issuecomment-457456166
--
vim.api.nvim_create_autocmd("TermOpen", {
    callback = function()
        if is_fzf_terminal() then
            return
        end

        vim.keymap.set("t", "<ESC><ESC>", "<C-\\><C-n>", {
            buffer = true,
            desc = "Exit the terminal by pressing <ESC> twice in a row.",
            noremap = true,
        })
    end,
    group = core_helpers._TERMINAL_GROUP,
    pattern = "*",
})

---------- Auto-Commands [End] ----------

---------- Auto-Commands 2 [Start] ----------
vim.api.nvim_create_autocmd("BufEnter", {
    pattern = "*",
    callback = vim.schedule_wrap(function()
        -- In the future these will be default values.
        --
        -- Reference: https://github.com/neovim/neovim/commit/52481eecf0dfc596a4d8df389c901f46cd3b6661
        --
        if vim.bo.buftype == "terminal" then
            vim.opt_local.relativenumber = false
            vim.opt_local.number = false
            vim.opt_local.signcolumn = "no"
        end
    end),
})
---------- Auto-Commands 2 [End] ----------

---------- Fix Terminal Padding [Start] ----------
--- Remove the weird padding around the terminal and the Neovim instance.
---
--- The technical details are a bit lost on me but the jist apparently is that
--- we mess with the terminal UI event to extend the colorscheme a bit further
--- than normal. But this must run *before* a colorscheme is loaded.
---
--- Reference: https://www.reddit.com/r/neovim/comments/1ehidxy/you_can_remove_padding_around_neovim_instance
---

vim.api.nvim_create_autocmd({ "UIEnter", "ColorScheme" }, {
    callback = function()
        local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
        if not normal.bg then
            return
        end

        if core_helpers.in_tmux() then
            io.write(string.format("\027Ptmux;\027\027]11;#%06x\007\027\\", normal.bg))
        else
            io.write(string.format("\027]11;#%06x\027\\", normal.bg))
        end
    end,
})

vim.api.nvim_create_autocmd("UILeave", {
    callback = function()
        if core_helpers.in_tmux() then
            io.write("\027Ptmux;\027\027]111;\007\027\\")
        else
            io.write("\027]111\027\\")
        end
    end,
})
---------- Fix Terminal Padding [End] ----------

---------- Initialization [Start] ----------
vim.opt.ttyfast = true -- Makes certain terminals scroll faster

-- Command-line completion, use '<Tab>' to move and '<CR>' to validate.
vim.opt.wildmenu = true

-- Ignore compiled/backup files when displaying files
vim.opt.wildignore = "*.o,*~,*.pyc,.git,.hg,.svn,*/.hg/*,*/.svn/*,*/.DS_Store"

-- Always show current position at the given line
vim.opt.ruler = true

-- Set the height of the command bar
vim.opt.cmdheight = 2

-- A buffer becomes hidden when it is abandoned, even if it has modifications
vim.opt.hidden = true

-- In many terminal emulators the mouse works just fine, thus enable it.
if vim.fn.has("mouse") then
    vim.opt.mouse = "a"
end

-- Ignore case when searching
vim.opt.ignorecase = true

-- When searching try to be smart about cases
vim.opt.smartcase = true

-- Makes regular characters act as they do in grep, during searches
vim.opt.magic = true

-- Show matching brackets when text indicator is over them
vim.opt.showmatch = true

-- How many tenths of a second to blink when matching brackets
vim.opt.mat = 2

-- Add a bit extra margin to the gutter
vim.opt.foldcolumn = "1"

-- Only let Vim wait for user input (characters) for 0.3 seconds. Gotta go fast!
vim.opt.timeoutlen = 300
-- Wait very little for key sequences
vim.opt.ttimeoutlen = 10

-- Return to last edit position when opening files (You want this!)
vim.api.nvim_create_autocmd("BufReadPost", {
    callback = function()
        local line = vim.fn.line("'\"")

        if line > 0 and line <= vim.fn.line("$") then
            vim.cmd([[execute "normal! g`\""]])
        end
    end,
})

-- Remember info about open buffers on close
vim.cmd("set viminfo^=%")

-- Always show the status line
vim.opt.laststatus = 2

-- Show relative line numbers
vim.opt.relativenumber = true
vim.opt.number = true

-- Show weird characters (tabs, trailing whitespaces, etc)
vim.opt.list = true
vim.opt.listchars = "tab:> ,trail: ,nbsp:+"

-- Auto-save whenever you switch buffers - potentially dangerous
vim.opt.autowrite = true
vim.opt.autowriteall = true
vim.api.nvim_create_autocmd({ "FocusLost", "WinLeave" }, {
    -- Write all files before navigating away from Vim
    pattern = "*",
    command = ":silent! wa",
})

-- In vimdiff mode, make diffs open as vertical buffers
-- Seriously. Why is this not the default
--
vim.opt.diffopt:append({ "vertical" })

-- This makes joining lines more intelligent
--
-- Example:  without this patch - (X) is the cursor position
-- example_document.vim
-- 1
-- 2 " I am a multiline comment (X)
-- 3 " and here is more info
-- 4
--
-- press Shift+j
--
-- 1
-- 2 " I am a multiline comment (X) " and here is more info
-- 3
--
-- Nooo!! whyyyyy!
--
-- Example:
-- 1
-- 2 " I am a multiline comment (X) and here is more info
-- 3
--
-- Works with other coding languages, too, like Python!
-- Reference: kinbiko.com/vim/my-shiniest-vim-gems
--
if vim.v.version > 703 then
    vim.opt.formatoptions:append({ "j" })
end

-- Disable tag completion (TAB)
--
-- Reference: https://stackoverflow.com/a/13232327/3626104
--
vim.cmd("set complete-=t")

-- Common typos that I want to automatically fix
vim.cmd("abbreviate hte the")
vim.cmd("abbreviate het the")
vim.cmd("abbreviate chnage change")

-- Nvim does not have special `t_XX` options nor <t_XX> keycodes to configure
-- terminal capabilities. Instead Nvim treats the terminal as any other UI,
-- e.g. 'guicursor' sets the terminal cursor style if possible.
--
vim.opt.guicursor = "n-v-c:block-Cursor"

-- Allow sentences to start with "E.g.". Don't mark them as bad sentences
vim.opt.spellcapcheck = [[.?!]\_[\])'"\t ]\+,E.g.,I.e.]]

-- Don't auto-resize buffers when a buffer is opened or closed
--
-- Reference: https://stackoverflow.com/a/33388054/3626104
--
vim.opt.equalalways = false
---------- Initialization [End] ----------

return M
