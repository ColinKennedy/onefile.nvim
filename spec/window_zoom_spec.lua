local window_zoom = require("modules.features.window_zoom")

---@class _WindowZoomNotification
---@field message string The message sent to `vim.notify`.
---@field level integer The log level sent to `vim.notify`.

--- Close all tabs except one scratch tab and reset window state.
---
local function reset_layout()
    vim.wo.winfixbuf = false

    while #vim.api.nvim_list_tabpages() > 1 do
        vim.cmd("tablast")
        vim.wo.winfixbuf = false
        vim.cmd("tabclose!")
    end

    vim.cmd("silent! only!")
    vim.cmd("enew!")
    vim.bo.buflisted = true
    window_zoom.reset_for_tests()
end

--- Create a listed scratch buffer with `name` and `lines`.
---
---@param name string The buffer name to assign.
---@param lines string[] The buffer lines to write.
---@return integer # The created buffer.
---
local function create_buffer(name, lines)
    local buffer = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buffer, name)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)

    return buffer
end

--- Return the current tabpage's non-floating window count.
---
---@return integer # The count of regular windows in the current tabpage.
---
local function current_tab_window_count()
    local count = 0

    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(window).relative == "" then
            count = count + 1
        end
    end

    return count
end

describe("window zoom", function()
    local original_notify
    local original_showtabline

    before_each(function()
        original_notify = vim.notify
        original_showtabline = vim.o.showtabline
        reset_layout()
    end)

    after_each(function()
        vim.notify = original_notify
        vim.o.showtabline = original_showtabline
        reset_layout()
    end)

    it("maps <C-w>o with a description", function()
        local mapping = vim.fn.maparg("<C-w>o", "n", false, true)

        assert.equal("Toggle-zoom the current window.", mapping.desc)
        assert.is_function(mapping.callback)
    end)

    it("zooms the current window into a temporary tab and restores the original layout", function()
        local first_buffer = create_buffer("window-zoom-first", { "first" })
        local second_buffer = create_buffer("window-zoom-second", { "second" })

        vim.api.nvim_win_set_buf(0, first_buffer)
        local source_window = vim.api.nvim_get_current_win()
        vim.cmd("vsplit")
        vim.api.nvim_win_set_buf(0, second_buffer)
        vim.api.nvim_set_current_win(source_window)

        assert.equal(2, current_tab_window_count())
        assert.equal(1, #vim.api.nvim_list_tabpages())

        window_zoom.toggle()

        assert.equal(2, #vim.api.nvim_list_tabpages())
        assert.is_true(window_zoom.is_zoomed_tab())
        assert.equal(1, current_tab_window_count())
        assert.equal(first_buffer, vim.api.nvim_get_current_buf())
        assert.equal(0, vim.o.showtabline)

        vim.cmd("split")
        assert.equal(2, current_tab_window_count())

        window_zoom.toggle()

        assert.equal(1, #vim.api.nvim_list_tabpages())
        assert.equal(source_window, vim.api.nvim_get_current_win())
        assert.equal(2, current_tab_window_count())
        assert.equal(first_buffer, vim.api.nvim_get_current_buf())
        assert.equal(original_showtabline, vim.o.showtabline)
    end)

    it("does nothing when there is only one window", function()
        window_zoom.toggle()

        assert.equal(1, #vim.api.nvim_list_tabpages())
        assert.equal(1, current_tab_window_count())
        assert.is_false(window_zoom.is_zoomed_tab())
    end)

    it("notifies once when the original tab cannot be restored", function()
        local first_buffer = create_buffer("window-zoom-deleted-tab-first", { "first" })
        local second_buffer = create_buffer("window-zoom-deleted-tab-second", { "second" })
        ---@type _WindowZoomNotification[]
        local notifications = {}

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.notify = function(message, level)
            table.insert(notifications, { message = message, level = level })
        end

        vim.api.nvim_win_set_buf(0, first_buffer)
        vim.cmd("vsplit")
        vim.api.nvim_win_set_buf(0, second_buffer)

        window_zoom.toggle()
        assert.is_true(window_zoom.is_zoomed_tab())

        vim.cmd("tabclose! 1")
        window_zoom.toggle()

        assert.equal(1, #notifications)
        assert.equal("Cannot restore zoomed window: original tab no longer exists.", notifications[1].message)
        assert.equal(vim.log.levels.ERROR, notifications[1].level)
        assert.equal(1, #vim.api.nvim_list_tabpages())
        assert.is_true(window_zoom.is_zoomed_tab())
    end)
end)
