local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
    --- The `ii` indentwise text-object
    --- Find the first column that is not whitespace for some `line`.
    ---
    ---@param line integer | string The 1-or-more index of some Vim buffer to search for text.
    ---@return integer # A 1-or-more found column value.
    ---
    function _get_first_non_whitespace_column(line)
        line = vim.fn.getline(line)
        local _, column = string.find(line, "^%s*")

        return column and (column + 1) or 1 -- Lua is 1-indexed
    end

    --- Find the last column that is not whitespace for some `line`.
    ---
    ---@param line integer | string The 1-or-more index of some Vim buffer to search for text.
    ---@return integer # A 1-or-more found column value.
    ---
    function _get_last_non_whitespace_column(line)
        line = vim.fn.getline(line)
        local trimmed = string.match(line, "^(.-)%s*$")
        return #trimmed + 1 -- again, Lua is 1-indexed
    end

    --- Select all lines with the same indentation.
    ---
    ---@param allow_empty_line boolean
    ---    If `false` then "same indentation or
    ---    greater" are selected. If `true` then empty newlines are also included
    ---    in the selection.
    ---
    function select_same_indent(allow_empty_line)
        allow_empty_line = allow_empty_line or false
        local current_line = vim.fn.line(".")
        local indent = vim.fn.indent(current_line)

        --- Check `line` to see if we should keep looking for more indented lines.
        ---
        ---@param line integer The row in a buffer to check. (A 1-or-more value).
        ---@return boolean # If we should end the scan, return `true`.
        ---
        local function _needs_stop(line)
            local text = vim.fn.getline(line)

            if vim.fn.indent(line) >= indent then
                return false
            end

            -- TODO: Check for trailing whitespace here
            if text ~= "" then
                return true
            end

            if not allow_empty_line then
                return true
            end

            return false
        end

        local start_line = current_line

        while start_line > 1 do
            if _needs_stop(start_line) then
                break
            end

            start_line = start_line - 1
        end

        local end_line = current_line

        while end_line < vim.fn.line("$") do
            if _needs_stop(end_line) then
                break
            end

            end_line = end_line + 1
        end

        start_line = start_line + 1
        end_line = end_line - 1

        _P.set_text_object_marks(
            start_line,
            _get_first_non_whitespace_column(start_line) - 1,
            end_line,
            _get_last_non_whitespace_column(end_line) - 2
        )
    end

    vim.keymap.set({ "o", "x" }, "ii", function()
        select_same_indent(false)
    end, { desc = "Select block with same indentation, stop at whitespace lines." })
    vim.keymap.set({ "o", "x" }, "iI", function()
        select_same_indent(true)
    end, { desc = "Select block with same indentation, ignore whitespace lines." })
end)
