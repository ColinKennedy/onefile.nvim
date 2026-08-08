--- Make sure quickfix entries can be deleted with `dd`-style mappings.

--- Close the quickfix and location list windows, if they are open.
local function close_quickfix()
    pcall(vim.cmd.cclose)
    pcall(vim.cmd.lclose)
end

--- Make quickfix entries whose text is each value in `texts`.
---
---@param texts string[] The text of each entry to create.
---@return table[] # The generated quickfix entries.
local function make_items(texts)
    ---@type table[]
    local items = {}

    for index, text in ipairs(texts) do
        table.insert(items, { bufnr = vim.api.nvim_get_current_buf(), lnum = index, col = 1, text = text })
    end

    return items
end

--- Get the text of every entry in the current quickfix list.
---
---@return string[] # The remaining quickfix entry text.
local function get_quickfix_texts()
    ---@type string[]
    local output = {}

    for _, item in ipairs(vim.fn.getqflist()) do
        table.insert(output, item.text)
    end

    return output
end

--- Open a quickfix window with an entry for each value in `texts`.
---
---@param texts string[] The text of each entry to create.
---@return integer # The created quickfix window.
local function open_quickfix(texts)
    vim.fn.setqflist({}, " ", { items = make_items(texts), title = "Some Title" })
    vim.cmd.copen({ mods = { silent = true } })

    return vim.fn.getqflist({ winid = true }).winid
end

--- Type `keys` as if a user pressed them, and wait for the result.
---
---@param keys string The keys to send.
local function call_keys(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
end

describe("quickfix entry deletion", function()
    before_each(function()
        close_quickfix()
        vim.cmd.enew({ bang = true })
    end)

    after_each(function()
        close_quickfix()
        vim.fn.setqflist({}, "r", { items = {} })
        vim.cmd.enew({ bang = true })
    end)

    it("deletes the entry under the cursor with dd", function()
        local window = open_quickfix({ "first", "second", "third" })
        vim.api.nvim_set_current_win(window)
        vim.api.nvim_win_set_cursor(window, { 2, 0 })

        call_keys("dd")

        assert.same({ "first", "third" }, get_quickfix_texts())
        assert.same({ 2, 0 }, vim.api.nvim_win_get_cursor(window))
    end)

    it("deletes multiple entries with d2d", function()
        local window = open_quickfix({ "first", "second", "third", "fourth" })
        vim.api.nvim_set_current_win(window)
        vim.api.nvim_win_set_cursor(window, { 2, 0 })

        call_keys("d2d")

        assert.same({ "first", "fourth" }, get_quickfix_texts())
    end)

    it("deletes multiple entries with a count before dd", function()
        local window = open_quickfix({ "first", "second", "third", "fourth" })
        vim.api.nvim_set_current_win(window)
        vim.api.nvim_win_set_cursor(window, { 1, 0 })

        call_keys("3dd")

        assert.same({ "fourth" }, get_quickfix_texts())
    end)

    it("multiplies the counts on both sides of d", function()
        local window = open_quickfix({ "first", "second", "third", "fourth", "fifth", "sixth", "seventh" })
        vim.api.nvim_set_current_win(window)
        vim.api.nvim_win_set_cursor(window, { 1, 0 })

        call_keys("2d3d")

        assert.same({ "seventh" }, get_quickfix_texts())
    end)

    it("stops at the last entry when the count is too big", function()
        local window = open_quickfix({ "first", "second", "third" })
        vim.api.nvim_set_current_win(window)
        vim.api.nvim_win_set_cursor(window, { 2, 0 })

        call_keys("10dd")

        assert.same({ "first" }, get_quickfix_texts())
        assert.same({ 1, 0 }, vim.api.nvim_win_get_cursor(window))
    end)

    it("deletes every selected entry from visual mode", function()
        local window = open_quickfix({ "first", "second", "third", "fourth" })
        vim.api.nvim_set_current_win(window)
        vim.api.nvim_win_set_cursor(window, { 3, 0 })

        call_keys("Vk")
        call_keys("d")

        assert.same({ "first", "fourth" }, get_quickfix_texts())
        assert.equal("n", vim.api.nvim_get_mode().mode)
    end)

    it("does not delete anything when the d sequence is cancelled", function()
        local window = open_quickfix({ "first", "second" })
        vim.api.nvim_set_current_win(window)
        vim.api.nvim_win_set_cursor(window, { 1, 0 })

        call_keys("dj")

        assert.same({ "first", "second" }, get_quickfix_texts())
    end)

    it("keeps the quickfix title after a deletion", function()
        local window = open_quickfix({ "first", "second" })
        vim.api.nvim_set_current_win(window)
        vim.api.nvim_win_set_cursor(window, { 1, 0 })

        call_keys("dd")

        assert.equal("Some Title", vim.fn.getqflist({ title = 0 }).title)
    end)

    it("empties the quickfix list when every entry is deleted", function()
        local window = open_quickfix({ "first", "second" })
        vim.api.nvim_set_current_win(window)
        vim.api.nvim_win_set_cursor(window, { 1, 0 })

        call_keys("2dd")

        assert.same({}, get_quickfix_texts())
        assert.same({ 1, 0 }, vim.api.nvim_win_get_cursor(window))
    end)

    it("deletes location list entries", function()
        local source_window = vim.api.nvim_get_current_win()
        vim.fn.setloclist(source_window, {}, " ", {
            items = make_items({ "first", "second", "third" }),
            title = "Some Location Title",
        })
        vim.cmd.lopen({ mods = { silent = true } })

        local window = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_cursor(window, { 1, 0 })

        call_keys("dd")

        local texts = vim.tbl_map(function(item)
            return item.text
        end, vim.fn.getloclist(window))

        assert.same({ "second", "third" }, texts)
        assert.equal("Some Location Title", vim.fn.getloclist(window, { title = 0 }).title)
    end)

    it("leaves the quickfix list alone when it is empty", function()
        vim.fn.setqflist({}, " ", { items = {}, title = "Empty Title" })
        vim.cmd.copen({ mods = { silent = true } })

        local window = vim.fn.getqflist({ winid = true }).winid
        vim.api.nvim_set_current_win(window)

        call_keys("dd")

        assert.same({}, get_quickfix_texts())
    end)
end)
