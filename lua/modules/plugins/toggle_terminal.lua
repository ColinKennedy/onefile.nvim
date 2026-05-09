local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
    --- A lightweight "toggleterminal". Use <space>T to open and close it.
    ---@type table<integer, _my.ToggleTerminal>
    _TAB_TERMINALS = {}
    ---@type table<integer, _my.ToggleTerminal>
    _BUFFER_TO_TERMINAL = {}
    _DARKER_TERMINAL_COLOR = "#111111"

    _Mode = {
        insert = "insert",
        normal = "normal",
        unknown = "?",
    }
    _NEXT_NUMBER = 0
    _STARTING_MODE = _Mode.insert -- NOTE: Start off in insert mode

    _IS_VIM_ENTERED = false

    --- Check if `buffer` is shown to the user.
    ---
    --- @param buffer number A 0-or-more index pointing to some Vim data.
    --- @return boolean # If at least one window contains `buffer`.
    ---
    function _is_buffer_visible(buffer)
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
    function _get_buffer_windows(buffer)
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
    function _increment_terminal_uuid()
        _NEXT_NUMBER = _NEXT_NUMBER + 1
    end

    --- Suggest a new terminal name, starting with `name`, that is unique.
    ---
    --- @param name string
    ---     Some terminal prefix. i.e. `"term://bash"`.
    --- @return string
    ---     The full buffer path that doesn't already exist. i.e.
    ---     `"term://bash;::toggleterminal::1"`. It's important though to remember
    ---     - This won't be the final, real terminal path name because this name
    ---     doesn't contain a $PWD.
    ---
    function _suggest_name(name)
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
    function _initialize_terminal_buffer(buffer)
        vim.bo[buffer].bufhidden = "hide"
        vim.b[buffer]._toggle_terminal_buffer = true
    end

    --- Set colors onto `window`.
    ---
    --- @param window number A 1-or-more value of some `toggleterminal` buffer.
    ---
    function _apply_highlights(window)
        local namespace = "Normal"
        local window_namespace = "ToggleTerminalNormal"
        vim.api.nvim_set_hl(0, window_namespace, { bg = _DARKER_TERMINAL_COLOR })

        vim.api.nvim_set_option_value(
            "winhighlight",
            string.format("%s:%s", namespace, window_namespace),
            { scope = "local", win = window }
        )
    end

    --- Create a new buffer or reuse the given terminal `buffer`.
    ---
    ---@param buffer integer? If not provided, a new terminal is created.
    ---@return _my.ToggleTerminal # Create a buffer from scratch.
    ---
    function _create_terminal(buffer)
        if not buffer then
            vim.cmd("edit! " .. _suggest_name("term://bash"))

            buffer = vim.fn.bufnr()
        end

        _initialize_terminal_buffer(buffer)
        _P.close_terminal_afterwards(buffer)

        return { buffer = buffer, mode = _STARTING_MODE }
    end

    --- Change `buffer` to insert or normal mode.
    ---
    --- @param buffer number A 1-or-more index pointing to a `toggleterm` buffer.
    ---
    function _handle_term_enter(buffer)
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
    function _handle_term_leave(buffer)
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
    function _prepare_terminal_window()
        vim.cmd("set nosplitbelow")
        vim.cmd("split")
        vim.cmd("set splitbelow&") -- Restore the previous split setting
        vim.cmd.wincmd("J") -- Move the split to the bottom of the tab
        vim.cmd.resize(10)
    end

    --- Keep the current terminal mode and then passthrough `keys`.
    ---
    --- This function is intended to be used with a keymap with `expr = true`.
    ---
    ---@param keys string The original keymap to run.
    ---@return fun(): string # The wrapped function.
    ---
    function _save_terminal_state(keys)
        return function()
            _handle_term_leave(vim.fn.bufnr())

            return keys
        end
    end

    --- Open an existing terminal for the current tab or create one if it doesn't exist.
    function _toggle_terminal()
        local tab = vim.fn.tabpagenr()
        local existing_terminal = _TAB_TERMINALS[tab]

        if not existing_terminal or vim.fn.bufexists(existing_terminal.buffer) == 0 then
            _prepare_terminal_window()

            local terminal = _create_terminal()
            _TAB_TERMINALS[tab] = terminal
            _BUFFER_TO_TERMINAL[terminal.buffer] = _TAB_TERMINALS[tab]

            return
        end

        local terminal = _TAB_TERMINALS[tab]

        if _is_buffer_visible(terminal.buffer) then
            for _, window in ipairs(_get_buffer_windows(terminal.buffer)) do
                vim.api.nvim_win_close(window, false)
            end
        else
            _prepare_terminal_window()
            vim.cmd.buffer(terminal.buffer)
        end
    end

    --- Add Neovim `toggleterminal`-related autocommands.
    function _P.setup_autocommands()
        local group = vim.api.nvim_create_augroup("my.toggle_terminal.commands", { clear = true })
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

                vim.wo[window].relativenumber = false
                vim.wo[window].number = false
                vim.wo[window].signcolumn = "no"

                vim.schedule(function()
                    _apply_highlights(window)
                end)
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

    -- NOTE: Allow quick and easy movement out of a terminal buffer using just <C-hjkl>
    vim.keymap.set({ "n", "t" }, "<C-h>", _save_terminal_state("<C-\\><C-n><C-w>h"), {
        desc = "Move to the left of the terminal buffer.",
        expr = true,
        silent = true,
    })
    vim.keymap.set({ "n", "t" }, "<C-j>", _save_terminal_state("<C-\\><C-n><C-w>j"), {
        desc = "Move down to the buffer below the terminal buffer.",
        expr = true,
        silent = true,
    })
    vim.keymap.set({ "n", "t" }, "<C-k>", _save_terminal_state("<C-\\><C-n><C-w>k"), {
        desc = "Move up to the buffer above the terminal buffer.",
        expr = true,
        silent = true,
    })
    vim.keymap.set({ "n", "t" }, "<C-l>", _save_terminal_state("<C-\\><C-n><C-w>l"), {
        desc = "Move to the right of the terminal buffer.",
        expr = true,
        silent = true,
    })
end)
