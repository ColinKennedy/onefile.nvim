--- Strip trailing whitespace only from lines changed in the current buffer.

local _P = {}

local _GROUP = vim.api.nvim_create_augroup("my.formatter.strip_trailing_whitespace", { clear = true })
---@type table<integer, table<integer, boolean>>
local _LINES = {}

--- Group `values` according to nearest neighbors.
---
--- A group is "2 or more values that are contiguous". All groups have
--- exactly 2 elements. Any orphans will be in a group by themselves.
---
---@param values integer[]
---    The values to group-up.
---    e.g. `{1, 2, 3, 7, 9, 10, 11, 13, 14, 18, 19, 20}`
---@return {[1]: integer, [2]: integer}[]
---    All tuples of start-and-end-group pairs.
---
function _P.get_contiguous_chunks(values)
    ---@type integer[][]
    local result = {}

    if #values == 0 then
        return result
    end

    local start = values[1]
    local previous = values[1]

    for i = 2, #values do
        local current = values[i]

        if current == previous + 1 then
            previous = current
        else
            -- NOTE: Close the previous group.
            if start == previous then
                table.insert(result, { start, start })
            else
                table.insert(result, { start, previous })
            end

            start = current
            previous = current
        end
    end

    -- NOTE: Close the final group.
    if start == previous then
        table.insert(result, { start, start })
    else
        table.insert(result, { start, previous })
    end

    return result
end

--- Remove all trailing whitespaces for all changed lines in the current buffer.
function _P.strip_trailing_whitespaces()
    local buffer = vim.api.nvim_get_current_buf()

    if not _LINES[buffer] then
        -- NOTE: This should only happen if we enter a buffer and immediately
        -- save the file but without making any changes to the buffer.
        --
        -- The above situation could be thought of as "accidental" which is
        -- why we ignore it.
        --
        return
    end

    local lines = vim.tbl_keys(_LINES[buffer])
    table.sort(lines)

    -- NOTE: The chunks are actually necessary but they do cut down on the
    -- number of `vim.cmd` calls that we have to do later so we'll chunk anyway.
    --
    local line_chunks = _P.get_contiguous_chunks(lines)

    -- NOTE: Save and restore the user's cursor, jumplist, etc. Strip the whitespace.
    -- Then restore any state that we need to.
    --
    local view = vim.fn.winsaveview()
    pcall(function()
        for _, chunk in ipairs(line_chunks) do
            local start, last = unpack(chunk)
            vim.cmd(string.format("keeppatterns %s,%ss/\\s\\+$//e", start, last))
        end
    end)
    vim.fn.winrestview(view)

    _LINES[buffer] = {}
end

vim.api.nvim_create_user_command(
    "StripTrailingWhitespaces",
    _P.strip_trailing_whitespaces,
    { nargs = 0, desc = "Remove all trailing whitespaces from all changed lines." }
)

vim.api.nvim_create_autocmd("BufEnter", {
    group = _GROUP,
    callback = function()
        vim.api.nvim_buf_attach(0, false, {
            on_lines = function(_, buffer, _, first_line, _, last_line)
                vim.schedule(function()
                    for index = first_line + 1, last_line do
                        _LINES[buffer] = _LINES[buffer] or {}
                        _LINES[buffer][index] = true
                    end
                end)
            end,
        })
    end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
    group = _GROUP,
    callback = _P.strip_trailing_whitespaces,
})
