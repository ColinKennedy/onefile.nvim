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
