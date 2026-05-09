local better_escape = require("modules.plugins.better_escape")

--- Press normal-mode keys and wait for Neovim to process them.
---
---@param keys string The keys to press.
local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
    vim.wait(500, function()
        return vim.fn.mode() == "n"
    end)
end

--- Prepare a scratch buffer for insert-mode tests.
local function prepare_buffer()
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_set_current_buf(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

--- Get the current scratch buffer line.
---
---@return string # The current line.
local function get_line()
    return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
end

describe("better escape", function()
    after_each(function()
        pcall(vim.cmd.stopinsert)
        vim.cmd.enew({ bang = true })
    end)

    it("does not install a plain insert-mode jk mapping", function()
        assert.equal("", vim.fn.maparg("jk", "i"))
        assert.is_true(vim.fn.maparg("j", "i") ~= "")
        assert.is_true(vim.fn.maparg("k", "i") ~= "")
    end)

    it("escapes insert mode when jk is typed quickly", function()
        prepare_buffer()
        press("ijk")

        assert.equal("", get_line())
        assert.equal("n", vim.fn.mode())
    end)

    it("inserts j immediately without waiting for k", function()
        prepare_buffer()
        press("ij<Esc>")

        assert.equal("j", get_line())
        assert.equal("n", vim.fn.mode())
    end)

    it("does not escape when another key interrupts jk", function()
        prepare_buffer()
        press("ijak<Esc>")

        assert.equal("jak", get_line())
        assert.equal("n", vim.fn.mode())
    end)

    it("installs terminal-mode j and k mappings without a plain jk mapping", function()
        assert.equal("", vim.fn.maparg("jk", "t"))
        assert.is_true(vim.fn.maparg("j", "t") ~= "")
        assert.is_true(vim.fn.maparg("k", "t") ~= "")
    end)

    it("returns a terminal escape sequence when terminal jk completes", function()
        local first_mapping = vim.fn.maparg("j", "t", false, true)
        local second_mapping = vim.fn.maparg("k", "t", false, true)

        assert.is_function(first_mapping.callback)
        assert.is_function(second_mapping.callback)
        assert.equal("j", first_mapping.callback())
        assert.equal("<BS><C-\\><C-n>", second_mapping.callback())
    end)

    it("can be set up more than once without failing", function()
        better_escape.setup()

        assert.is_true(vim.fn.maparg("j", "i") ~= "")
        assert.is_true(vim.fn.maparg("j", "t") ~= "")
    end)
end)
