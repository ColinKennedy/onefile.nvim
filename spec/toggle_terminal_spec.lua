--- Press the normal-mode toggle-terminal mapping and wait for queued work.
---
local function press_toggle_terminal()
    local mapping = vim.fn.maparg(" T", "n", false, true)

    assert.is_function(mapping.callback)
    mapping.callback()
    vim.wait(50)
end

--- Check if `buffer` is visible in the current tab.
---
---@param buffer integer The buffer to inspect.
---@return boolean # If any current-tab window shows `buffer`, return `true`.
local function is_buffer_visible(buffer)
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(window) == buffer then
            return true
        end
    end

    return false
end

describe("modules.plugins.toggle_terminal", function()
    local showmode

    before_each(function()
        showmode = vim.o.showmode
        vim.o.showmode = false
    end)

    after_each(function()
        pcall(vim.cmd.stopinsert)
        vim.o.showmode = showmode
    end)

    it("does not enter insert mode for a terminal buffer unless that buffer is current", function()
        local original_window = vim.api.nvim_get_current_win()

        press_toggle_terminal()

        assert.True(vim.wait(1000, function()
            return vim.bo[vim.api.nvim_get_current_buf()].buftype == "terminal"
        end, 20))

        local terminal_buffer = vim.api.nvim_get_current_buf()

        vim.cmd.stopinsert()
        vim.api.nvim_set_current_win(original_window)
        require("modules.plugins.toggle_terminal")._P.handle_term_enter(terminal_buffer)

        assert.equal(original_window, vim.api.nvim_get_current_win())
        assert.equal("n", vim.fn.mode())

        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_buf(window) == terminal_buffer then
                vim.api.nvim_win_close(window, true)
            end
        end
    end)

    it("restores a saved terminal-normal mode without entering terminal insert", function()
        press_toggle_terminal()

        assert.True(vim.wait(1000, function()
            return vim.bo[vim.api.nvim_get_current_buf()].buftype == "terminal"
        end, 20))

        local toggle_terminal = require("modules.plugins.toggle_terminal")
        local terminal_buffer = vim.api.nvim_get_current_buf()
        local terminal_name = vim.api.nvim_buf_get_name(terminal_buffer)

        vim.cmd.stopinsert()
        toggle_terminal.restore_session_modes({ [terminal_name] = "normal" })
        toggle_terminal._P.handle_term_enter(terminal_buffer)

        assert.equal(terminal_buffer, vim.api.nvim_get_current_buf())
        assert.equal("n", vim.fn.mode())

        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_buf(window) == terminal_buffer then
                vim.api.nvim_win_close(window, true)
            end
        end
    end)

    it("writes terminal-normal mode into appended session state", function()
        press_toggle_terminal()

        assert.True(vim.wait(1000, function()
            return vim.bo[vim.api.nvim_get_current_buf()].buftype == "terminal"
        end, 20))

        local toggle_terminal = require("modules.plugins.toggle_terminal")
        local terminal_buffer = vim.api.nvim_get_current_buf()
        local terminal_name = vim.api.nvim_buf_get_name(terminal_buffer)
        local session = vim.fn.tempname()

        vim.cmd.stopinsert()
        toggle_terminal.save_terminal_state()
        toggle_terminal.append_session_state(session)

        local lines = table.concat(vim.fn.readfile(session), "\n")

        assert.is_not_nil(lines:find("restore_session_modes", 1, true))
        assert.is_not_nil(lines:find(terminal_name, 1, true))
        assert.is_not_nil(lines:find('"normal"', 1, true))

        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_buf(window) == terminal_buffer then
                vim.api.nvim_win_close(window, true)
            end
        end

        vim.fn.delete(session)
    end)

    it("can open, close, and reopen the terminal mapping", function()
        local shortmess = vim.o.shortmess

        press_toggle_terminal()

        assert.True(vim.wait(1000, function()
            return vim.bo[vim.api.nvim_get_current_buf()].buftype == "terminal"
        end, 20))
        assert.equal(shortmess, vim.o.shortmess)

        local terminal_buffer = vim.api.nvim_get_current_buf()

        assert.equal("terminal", vim.bo[terminal_buffer].buftype)
        assert.True(vim.b[terminal_buffer]._toggle_terminal_buffer)

        vim.cmd.stopinsert()
        press_toggle_terminal()

        assert.True(vim.wait(1000, function()
            return not is_buffer_visible(terminal_buffer)
        end, 20))

        press_toggle_terminal()

        assert.True(vim.wait(1000, function()
            return is_buffer_visible(terminal_buffer)
        end, 20))
        assert.equal(shortmess, vim.o.shortmess)

        assert.equal(terminal_buffer, vim.api.nvim_get_current_buf())
    end)
end)
