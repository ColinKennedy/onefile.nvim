--- A lightweight "toggleterminal". Use <space>T to open and close it.

local M = {}
local _P = {}

---@type table<integer, _my.ToggleTerminal>
local _TAB_TERMINALS = {}
---@type table<integer, _my.ToggleTerminal>
local _BUFFER_TO_TERMINAL = {}
local _DARKER_TERMINAL_COLOR = "#111111"

---@type table<string, string>
local _Mode = {
    insert = "insert",
    normal = "normal",
    unknown = "?",
}
local _NEXT_NUMBER = 0
local _STARTING_MODE = _Mode.insert -- NOTE: Start off in insert mode

local _IS_VIM_ENTERED = false
local _DEFAULT_SHELL_COMMAND = nil

--- Check if `buffer` is shown to the user.
---
--- @param buffer number A 0-or-more index pointing to some Vim data.
--- @return boolean # If at least one window contains `buffer`.
---
local function _is_buffer_visible(buffer)
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(window) == buffer then
            return true
        end
    end

    return false
end

--- Find all windows that show `buffer`.
---
--- @param buffer number A 0-or-more index pointing to some Vim data.
--- @return number[] # All of the windows found, if any.
---
local function _get_buffer_windows(buffer)
    ---@type number[]
    local output = {}

    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(window) == buffer then
            table.insert(output, window)
        end
    end

    return output
end

--- Get the next UUID so we can use if for terminal buffer names.
local function _increment_terminal_uuid()
    _NEXT_NUMBER = _NEXT_NUMBER + 1
end

--- Check whether Neovim is running on Windows.
---
---@return boolean
local function _is_windows()
    return package.config:sub(1, 1) == "\\"
end

--- Check if `command` points back to Neovim itself.
---
---@param command string?
---@return boolean
local function _is_neovim_command(command)
    if not command or command == "" then
        return false
    end

    local executable = command:match("^%s*([^%s]+)")

    if not executable then
        return false
    end

    local name = vim.fs.basename(executable):lower()

    return name == "nvim" or name == "nvim.exe" or name == "neovim" or name == "neovim.exe"
end

--- Get the shell command to use for toggleterminal buffers.
---
---@return string
local function _get_default_shell_command()
    if _DEFAULT_SHELL_COMMAND then
        return _DEFAULT_SHELL_COMMAND
    end

    local shell = os.getenv("NEOVIM_SHELL_COMMAND")

    if not shell or shell == "" then
        shell = vim.o.shell
    end

    if not shell or shell == "" then
        if _is_windows() then
            shell = os.getenv("ComSpec") or "cmd.exe"
        else
            shell = os.getenv("SHELL") or "sh"
        end
    end

    if _is_neovim_command(shell) then
        shell = _is_windows() and (os.getenv("ComSpec") or "cmd.exe") or (os.getenv("SHELL") or "sh")
    end

    _DEFAULT_SHELL_COMMAND = shell

    return _DEFAULT_SHELL_COMMAND
end

--- Suggest a new terminal name, starting with `name`, that is unique.
---
--- @param name string
---     Some terminal prefix. i.e. `"term://powershell.exe"`.
--- @return string
---     The full buffer path that doesn't already exist. i.e.
---     `"term://powershell.exe;::toggleterminal::1"`. It's important though to remember
---     - This won't be the final, real terminal path name because this name
---     doesn't contain a $PWD.
---
local function _suggest_name(name)
    local current = name .. ";::toggleterminal::" .. _NEXT_NUMBER

    while vim.fn.bufexists(current) == 1 do
        _increment_terminal_uuid()
        current = name .. ";::toggleterminal::" .. _NEXT_NUMBER
    end

    -- We add another one so that, if `_suggest_name` is called again, we save
    -- 1 extra call to `vim.fn.bufexists`.
    --
    _increment_terminal_uuid()

    return current
end

--- Bootstrap `toggleterminal` logic to an existing terminal `buffer`.
---
--- @param buffer number A 0-or-more index pointing to some Vim data.
---
local function _initialize_terminal_buffer(buffer)
    vim.bo[buffer].bufhidden = "hide"
    vim.b[buffer]._toggle_terminal_buffer = true
    vim.b[buffer]._toggle_terminal_cwd = vim.b[buffer]._toggle_terminal_cwd or vim.fn.getcwd()
end

--- Set colors onto `window`.
---
--- @param window number A 1-or-more value of some `toggleterminal` buffer.
---
local function _apply_highlights(window)
    local namespace = "Normal"
    local window_namespace = "ToggleTerminalNormal"
    vim.api.nvim_set_hl(0, window_namespace, { bg = _DARKER_TERMINAL_COLOR })

    vim.api.nvim_set_option_value(
        "winhighlight",
        string.format("%s:%s", namespace, window_namespace),
        { scope = "local", win = window }
    )
end

--- Configure the current terminal window for toggle-terminal display.
---
---@param window integer The terminal window to configure.
local function _configure_terminal_window(window)
    vim.wo[window].relativenumber = false
    vim.wo[window].number = false
    vim.wo[window].signcolumn = "no"

    vim.schedule(function()
        _apply_highlights(window)
    end)
end

--- Set `buffer` into `window`, even if the window is temporarily fixed.
---
---@param window integer The window to update.
---@param buffer integer The buffer to show in `window`.
local function _set_window_buffer(window, buffer)
    local winfixbuf = vim.wo[window].winfixbuf

    if winfixbuf then
        vim.wo[window].winfixbuf = false
    end

    vim.api.nvim_win_set_buf(window, buffer)

    if winfixbuf then
        vim.wo[window].winfixbuf = true
    end
end

--- Create a new buffer or reuse the given terminal `buffer`.
---
---@param buffer integer? If not provided, a new terminal is created.
---@return _my.ToggleTerminal # Create a buffer from scratch.
---
local function _create_terminal(buffer)
    if not buffer then
        local terminal = require("modules.utilities.core_helpers").with_file_messages_suppressed(function()
            local command = _get_default_shell_command()
            local terminal_name = _suggest_name("term://" .. command)

            buffer = vim.api.nvim_create_buf(false, true)
            local window = vim.api.nvim_get_current_win()

            _set_window_buffer(window, buffer)
            vim.api.nvim_buf_set_name(buffer, terminal_name)
            _initialize_terminal_buffer(buffer)

            local job = vim.fn.jobstart(command, { term = true })

            if job <= 0 then
                vim.api.nvim_buf_delete(buffer, { force = true })
                error(string.format('Failed to start terminal shell "%s".', command), 0)
            end

            vim.api.nvim_buf_set_name(buffer, terminal_name)
            _configure_terminal_window(window)
            _initialize_terminal_buffer(buffer)
            require("modules.utilities.core_helpers").close_terminal_afterwards(buffer)

            return { buffer = buffer, mode = _STARTING_MODE }
        end)

        assert(terminal)

        return terminal
    end

    _initialize_terminal_buffer(buffer)
    require("modules.utilities.core_helpers").close_terminal_afterwards(buffer)

    return { buffer = buffer, mode = _STARTING_MODE }
end

--- Change `buffer` to insert or normal mode.
---
--- @param buffer number A 1-or-more index pointing to a `toggleterm` buffer.
---
local function _handle_term_enter(buffer)
    local terminal = _BUFFER_TO_TERMINAL[buffer]

    if not terminal then
        -- NOTE: This rare situation happens when a terminal window gets
        -- duplicated into a different buffer number. It's probably
        -- harmless when it happens so just ignore it.
        --
        return
    end

    local mode = terminal.mode

    if mode == _Mode.insert then
        vim.cmd.startinsert()
    elseif mode == _Mode.unknown then
        if _STARTING_MODE == _Mode.insert then
            vim.cmd.startinsert()
        end
    elseif mode == _Mode.normal then
        -- TODO: Double-check this part
        return
    end
end

--- Keep track of `buffer` mode so we can restore it as needed, later.
---
--- @param buffer number A 1-or-more index pointing to a `toggleterm` buffer.
---
local function _handle_term_leave(buffer)
    local raw_mode = vim.api.nvim_get_mode().mode
    local mode = _Mode.unknown

    if raw_mode:match("nt") then -- nt is normal mode in the terminal
        mode = _Mode.normal
    elseif raw_mode:match("t") then -- t is insert mode in the terminal
        mode = _Mode.insert
    end

    local terminal = _BUFFER_TO_TERMINAL[buffer]

    if terminal and mode then
        terminal.mode = mode
    end
end

--- Make a window (non-terminal) so we can assign a terminal into it later.
local function _prepare_terminal_window()
    vim.cmd("set nosplitbelow")
    vim.cmd("split")
    vim.cmd("set splitbelow&") -- Restore the previous split setting
    vim.cmd.wincmd("J") -- Move the split to the bottom of the tab
    vim.cmd.resize(10)
    vim.wo.winfixbuf = true
end

function M.save_terminal_state()
    _handle_term_leave(vim.fn.bufnr())
end

--- Open an existing terminal for the current tab or create one if it doesn't exist.
local function _toggle_terminal()
    local tab = vim.fn.tabpagenr()
    local existing_terminal = _TAB_TERMINALS[tab]

    if not existing_terminal or vim.fn.bufexists(existing_terminal.buffer) == 0 then
        _prepare_terminal_window()

        local terminal = _create_terminal()
        _TAB_TERMINALS[tab] = terminal
        _BUFFER_TO_TERMINAL[terminal.buffer] = _TAB_TERMINALS[tab]
        vim.schedule(function()
            vim.cmd.startinsert()
        end)

        return
    end

    local terminal = _TAB_TERMINALS[tab]

    if _is_buffer_visible(terminal.buffer) then
        for _, window in ipairs(_get_buffer_windows(terminal.buffer)) do
            vim.api.nvim_win_close(window, false)
        end
    else
        _prepare_terminal_window()
        require("modules.utilities.core_helpers").with_file_messages_suppressed(function()
            _set_window_buffer(vim.api.nvim_get_current_win(), terminal.buffer)
        end)
    end
end

--- Add Neovim `toggleterminal`-related autocommands.
function _P.setup_autocommands()
    local group = vim.api.nvim_create_augroup("my.toggle_terminal.commands", { clear = true })
    ---@type string[]
    local toggleterm_pattern = { "term://*::toggleterminal::*" }

    vim.api.nvim_create_autocmd("BufEnter", {
        pattern = toggleterm_pattern,
        group = group,
        nested = true, -- This is necessary in case the buffer is the last
        callback = function()
            local buffer = vim.fn.bufnr()

            vim.schedule(function()
                if not _IS_VIM_ENTERED then
                    -- NOTE: This is a special situation. If we're
                    -- restoring from a Vim Session, we won't have buffer
                    -- information. So we have to add it manually.
                    --
                    local terminal = _create_terminal(buffer)
                    local tab = vim.fn.tabpagenr()
                    _TAB_TERMINALS[tab] = terminal
                    _BUFFER_TO_TERMINAL[terminal.buffer] = _TAB_TERMINALS[tab]

                    return
                end

                _handle_term_enter(buffer)
            end)
        end,
    })

    vim.api.nvim_create_autocmd("TermOpen", {
        group = group,
        pattern = toggleterm_pattern,
        callback = function()
            local window = vim.fn.win_getid()

            _configure_terminal_window(window)
        end,
    })

    vim.api.nvim_create_autocmd("TermClose", {
        group = group,
        pattern = toggleterm_pattern,
        callback = function()
            vim.b.terminal_job_id = nil
        end,
    })

    vim.api.nvim_create_autocmd("VimEnter", {
        group = group,
        callback = function()
            vim.schedule(function()
                _IS_VIM_ENTERED = true
            end)
        end,
    })
end

--- Add command(s) for interacting with the terminals.
function _P.setup_commands()
    vim.api.nvim_create_user_command(
        "ToggleTerminal",
        _toggle_terminal,
        { desc = "Open / Close a terminal at the bottom of the tab", nargs = 0 }
    )
end

_P.setup_autocommands()
vim.keymap.set(
    "n",
    "<space>T",
    _toggle_terminal,
    { desc = "Toggle [T]erminal, in a split at the bottom of the current tab." }
)

return M
