--- Center Neovim's externalized command line without taking over messages.

local M = {}
local _P = {}

M._initialized = false

---@class _my.cmdline.WidthConfiguration
---@field value string|integer Width: "60%" is a fraction of editor columns, integer is absolute columns.
---@field min integer Minimum width in columns.
---@field max integer Maximum width in columns.

---@class _my.cmdline.PositionConfiguration
---@field x string|integer Horizontal position: "50%" is centered, integer is absolute columns from the left.
---@field y string|integer Vertical position: "50%" is centered, integer is absolute rows from the top.

---@class _my.cmdline.Configuration
---@field width _my.cmdline.WidthConfiguration Cmdline window width.
---@field position _my.cmdline.PositionConfiguration Cmdline window position.
---@field border string? nil inherits `vim.o.winborder` at setup time.
---@field native_types string[] Cmdline types shown by Neovim's native cmdline instead of the centered float.

---@alias _my.cmdline.ContentChunk [integer, string]

---@type _my.cmdline.Configuration
M.config = {
    width = {
        value = "60%",
        min = 40,
        max = 80,
    },
    position = {
        x = "50%",
        y = "50%",
    },
    border = nil,
    native_types = { "/", "?" },
}

_P.namespace = vim.api.nvim_create_namespace("my.tiny_cmdline")
---@type integer?
_P.buffer = nil
---@type integer?
_P.window = nil
---@type integer?
_P.popup_buffer = nil
---@type integer?
_P.popup_window = nil
---@type string?
_P.cmdline_type = nil
---@type string
_P.current_line = ""
---@type integer
_P.prompt_width = 0
---@type integer
_P.cursor_column = 0
---@type integer
_P.cursor_byte_column = 0
---@type integer
_P.generation = 0
---@type boolean
_P.handling_cmdline_popupmenu = false

--- Parse a percent or absolute dimension into screen cells.
---
---@param value string|integer The user configured dimension.
---@param available integer The available screen cells.
---@return integer # The resolved size or position.
function _P.parse_dimension(value, available)
    if type(value) == "string" then
        local percent = tonumber(value:match("^(%d+)%%$"))

        if percent then
            return math.floor((available * percent) / 100)
        end

        return math.floor(tonumber(value) or 0)
    end

    return math.floor(value)
end

--- Get the target floating-window geometry for the current screen.
---
---@param content_height integer The visible cmdline window height.
---@return integer width The target window width.
---@return integer row The target top row.
---@return integer column The target left column.
---@return integer border_width The border width in cells.
function _P.get_geometry(content_height)
    local columns = vim.o.columns
    local lines = vim.o.lines
    local border_width = M.config.border == "none" and 0 or 1
    local width = math.max(
        M.config.width.min,
        math.min(M.config.width.max, _P.parse_dimension(M.config.width.value, columns))
    )

    width = math.min(width, columns - 4)

    local row = math.max(0, _P.parse_dimension(M.config.position.y, lines - content_height - (border_width * 2)))
    local column = math.max(0, _P.parse_dimension(M.config.position.x, columns - width - (border_width * 2)))

    return width, row, column, border_width
end

--- Keep a real message row so :messages and hit-enter prompts stay native.
function _P.ensure_message_row()
    if vim.o.cmdheight == 1 then
        return
    end

    pcall(function()
        vim._with({ noautocmd = true, o = { splitkeep = "screen" } }, function()
            vim.o.cmdheight = 1
        end)
    end)

    if vim.o.cmdheight ~= 1 then
        vim.o.cmdheight = 1
    end
end

--- Get or create the scratch buffer used by the centered cmdline.
---
---@return integer # The centered cmdline buffer.
function _P.get_buffer()
    if _P.buffer and vim.api.nvim_buf_is_valid(_P.buffer) then
        return _P.buffer
    end

    _P.buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[_P.buffer].bufhidden = "wipe"
    vim.bo[_P.buffer].buftype = "nofile"
    vim.bo[_P.buffer].filetype = "cmd"

    return _P.buffer
end

--- Build a floating-window configuration for `height` lines.
---
---@param height integer The window height.
---@return vim.api.keyset.win_config # The target floating-window config.
function _P.get_window_config(height)
    local width, row, column = _P.get_geometry(height)

    return {
        relative = "editor",
        row = row,
        col = column,
        width = width,
        height = height,
        style = "minimal",
        focusable = false,
        noautocmd = true,
        border = M.config.border,
    }
end

--- Check whether `window` is a usable Neovim window id.
---
---@param window integer? The window id to inspect.
---@return boolean # Whether the id points to a valid window.
function _P.is_valid_window(window)
    return window ~= nil and window > 0 and vim.api.nvim_win_is_valid(window)
end

--- Get or create the scratch buffer used by the command-line completion menu.
---
---@return integer # The popupmenu buffer.
function _P.get_popup_buffer()
    if _P.popup_buffer and vim.api.nvim_buf_is_valid(_P.popup_buffer) then
        return _P.popup_buffer
    end

    _P.popup_buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[_P.popup_buffer].bufhidden = "wipe"
    vim.bo[_P.popup_buffer].buftype = "nofile"

    return _P.popup_buffer
end

--- Open or resize the centered cmdline float.
---
---@param height integer The desired window height.
function _P.open_window(height)
    local buffer = _P.get_buffer()
    local config = _P.get_window_config(height)

    if _P.is_valid_window(_P.window) then
        vim.api.nvim_win_set_config(_P.window, config)

        if vim.api.nvim_win_get_buf(_P.window) ~= buffer then
            vim.api.nvim_win_set_buf(_P.window, buffer)
        end

        return
    end

    _P.window = vim.api.nvim_open_win(buffer, false, config)
    vim.wo[_P.window].winhighlight = "Normal:TinyCmdlineNormal,FloatBorder:TinyCmdlineBorder"
end

--- Close the centered cmdline float.
function _P.close_window()
    if _P.is_valid_window(_P.window) then
        pcall(vim.api.nvim_win_close, _P.window, true)
    end

    _P.window = nil
    _P.cmdline_type = nil
    _P.current_line = ""
    _P.prompt_width = 0
    _P.cursor_column = 0
    _P.cursor_byte_column = 0
    _P.close_popupmenu()
    _P.handling_cmdline_popupmenu = false
end

--- Convert external cmdline chunks into display text.
---
---@param content _my.cmdline.ContentChunk[] Command-line content chunks.
---@param firstc string The command-line type prefix.
---@param prompt string Prompt text for input()-style command lines.
---@param indent integer Prompt indentation.
---@return string # The rendered cmdline text.
function _P.render_line(content, firstc, prompt, indent)
    local parts = { firstc, prompt, string.rep(" ", indent) }

    for _, chunk in ipairs(content) do
        table.insert(parts, chunk[2])
    end

    return table.concat(parts)
end

--- Draw the command line in the centered float.
---
---@param content _my.cmdline.ContentChunk[] Command-line content chunks.
---@param position integer Current cursor position inside the command text.
---@param firstc string The command-line type prefix.
---@param prompt string Prompt text for input()-style command lines.
---@param indent integer Prompt indentation.
function _P.show_cmdline(content, position, firstc, prompt, indent)
    _P.cmdline_type = firstc
    _P.current_line = _P.render_line(content, firstc, prompt, indent)
    _P.prompt_width = vim.fn.strdisplaywidth(firstc .. prompt .. string.rep(" ", indent))

    _P.open_window(1)

    local buffer = _P.get_buffer()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { _P.current_line })
    _P.set_cursor_position(position)
end

--- Flush screen updates after external cmdline float changes.
function _P.flush_redraw()
    pcall(vim.api.nvim__redraw, { flush = true })
end

--- Schedule a command-line draw outside the UI callback.
---
---@param content _my.cmdline.ContentChunk[] Command-line content chunks.
---@param position integer Current cursor position inside the command text.
---@param firstc string The command-line type prefix.
---@param prompt string Prompt text for input()-style command lines.
---@param indent integer Prompt indentation.
function _P.schedule_show_cmdline(content, position, firstc, prompt, indent)
    _P.generation = _P.generation + 1
    local generation = _P.generation

    vim.schedule(function()
        if generation ~= _P.generation then
            return
        end

        local ok, message = pcall(_P.show_cmdline, content, position, firstc, prompt, indent)

        if ok then
            _P.flush_redraw()

            return
        end

        _P.close_window()
        vim.notify(string.format("tiny_cmdline failed to draw: %s", message), vim.log.levels.ERROR)
    end)
end

--- Get the single character that should be drawn as the cursor block.
---
---@return string # Character under the cursor, or a space at end-of-line.
function _P.get_cursor_text()
    if _P.cursor_byte_column >= #_P.current_line then
        return " "
    end

    local prefix = _P.current_line:sub(1, _P.cursor_byte_column)
    local char_index = vim.fn.strchars(prefix)
    local text = vim.fn.strcharpart(_P.current_line, char_index, 1)

    return text ~= "" and text or " "
end

--- Draw a visible block cursor in the non-focusable cmdline float.
function _P.draw_cursor_block()
    local buffer = _P.get_buffer()

    vim.api.nvim_buf_clear_namespace(buffer, _P.namespace, 0, 1)
    vim.api.nvim_buf_set_extmark(buffer, _P.namespace, 0, 0, {
        virt_text = { { _P.get_cursor_text(), "TinyCmdlineCursor" } },
        virt_text_pos = "overlay",
        virt_text_win_col = _P.cursor_column,
        priority = 1000,
    })
end

--- Move the floating-window cursor to match the command-line cursor.
---
---@param position integer Current cursor position inside the command text.
function _P.set_cursor_position(position)
    if not _P.is_valid_window(_P.window) then
        return
    end

    local prompt_text = _P.current_line:sub(1, _P.prompt_width)
    local command_text = _P.current_line:sub(#prompt_text + 1)
    local column = _P.prompt_width + vim.fn.strdisplaywidth(command_text:sub(1, position))
    _P.cursor_column = math.max(0, column)
    _P.cursor_byte_column = math.min(#_P.current_line, #prompt_text + position)
    pcall(vim.api.nvim_win_set_cursor, _P.window, { 1, _P.cursor_column })
    _P.draw_cursor_block()
end

--- Convert a popupmenu item into one display row.
---
---@param item table The external popupmenu item.
---@return string # The rendered popupmenu row.
function _P.render_popup_item(item)
    local word = tostring(item[1] or "")
    local kind = tostring(item[2] or "")
    local menu = tostring(item[3] or "")
    local suffix = table.concat(vim.tbl_filter(function(value)
        return value ~= ""
    end, { kind, menu }), " ")

    if suffix == "" then
        return word
    end

    return string.format("%s  %s", word, suffix)
end

--- Get the editor-relative popupmenu position beside the centered cmdline cursor.
---
---@param width integer The popupmenu width.
---@param height integer The popupmenu height.
---@return integer row The popupmenu row.
---@return integer column The popupmenu column.
function _P.get_cmdline_popupmenu_position(width, height)
    local _cmdline_width, row, column, border_width = _P.get_geometry(1)
    local content_row = row + border_width
    local content_column = column + border_width
    local popup_column = math.min(content_column + _P.cursor_column, math.max(0, vim.o.columns - width - 1))
    local below_row = content_row + 1

    if below_row + height <= vim.o.lines - vim.o.cmdheight then
        return below_row, popup_column
    end

    return math.max(0, content_row - height), popup_column
end

--- Get the editor-relative popupmenu position for insert-mode completion.
---
---@param anchor_row integer The screen row sent by the popupmenu UI event.
---@param anchor_column integer The screen column sent by the popupmenu UI event.
---@param width integer The popupmenu width.
---@param height integer The popupmenu height.
---@return integer row The popupmenu row.
---@return integer column The popupmenu column.
function _P.get_screen_popupmenu_position(anchor_row, anchor_column, width, height)
    local column = math.min(math.max(0, anchor_column), math.max(0, vim.o.columns - width - 1))
    local below_row = math.max(0, anchor_row + 1)

    if below_row + height <= vim.o.lines - vim.o.cmdheight then
        return below_row, column
    end

    return math.max(0, anchor_row - height), column
end

--- Get a popupmenu height that respects 'pumheight' without treating 0 as one row.
---
---@param item_count integer Number of popupmenu entries.
---@return integer # The desired popupmenu height.
function _P.get_popupmenu_height(item_count)
    local available = math.max(1, vim.o.lines - vim.o.cmdheight - 2)
    local configured = vim.o.pumheight

    if configured > 0 then
        available = math.min(available, configured)
    end

    return math.min(item_count, available)
end

--- Resolve a popupmenu event into either a screen anchor or cmdline-relative anchor.
---
---@param row integer? The popupmenu row from Neovim's UI event.
---@param column integer? The popupmenu column from Neovim's UI event.
---@param grid integer? The popupmenu grid from Neovim's UI event.
---@return {row: integer, column: integer}? anchor nil means anchor to the external cmdline.
function _P.get_popupmenu_anchor(row, column, grid)
    if grid == -1 then
        return nil
    end

    if row ~= nil and column ~= nil then
        return { row = row, column = column }
    end

    if _P.is_valid_window(_P.window) then
        return nil
    end

    return { row = row or 0, column = column or 0 }
end

--- Show completion popupmenu for either cmdline or insert-mode completion.
---
---@param items table[] Popupmenu entries from Neovim's external UI event.
---@param selected integer Selected item index, or -1 when no item is selected.
---@param anchor {row: integer, column: integer}? Insert-mode screen anchor. nil means external cmdline.
function _P.show_popupmenu(items, selected, anchor)
    if vim.tbl_isempty(items) then
        _P.close_popupmenu()

        return
    end

    if not anchor and not _P.is_valid_window(_P.window) then
        _P.close_popupmenu()

        return
    end

    local lines = {}
    local width = 1

    for _, item in ipairs(items) do
        local line = _P.render_popup_item(item)
        table.insert(lines, line)
        width = math.max(width, vim.fn.strdisplaywidth(line))
    end

    local height = _P.get_popupmenu_height(#lines)
    width = math.min(math.max(width, 12), math.max(12, vim.o.columns - 4))

    local buffer = _P.get_popup_buffer()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)

    local row, popup_column

    if anchor then
        row, popup_column = _P.get_screen_popupmenu_position(anchor.row, anchor.column, width, height)
    else
        row, popup_column = _P.get_cmdline_popupmenu_position(width, height)
    end
    local config = {
        relative = "editor",
        row = row,
        col = popup_column,
        width = width,
        height = height,
        style = "minimal",
        focusable = false,
        noautocmd = true,
        border = M.config.border,
    }

    if _P.is_valid_window(_P.popup_window) then
        vim.api.nvim_win_set_config(_P.popup_window, config)
    else
        _P.popup_window = vim.api.nvim_open_win(buffer, false, config)
        vim.wo[_P.popup_window].winhighlight = "Normal:Pmenu,FloatBorder:FloatBorder,CursorLine:PmenuSel"
        vim.wo[_P.popup_window].cursorline = true
    end

    _P.select_popupmenu(selected)
end

--- Move popupmenu selection highlight.
---
---@param selected integer Selected item index, or -1 when no item is selected.
function _P.select_popupmenu(selected)
    if not _P.is_valid_window(_P.popup_window) then
        return
    end

    if selected < 0 then
        vim.wo[_P.popup_window].cursorline = false

        return
    end

    vim.wo[_P.popup_window].cursorline = true
    pcall(vim.api.nvim_win_set_cursor, _P.popup_window, { selected + 1, 0 })
end

--- Return true when a popupmenu event belongs to the external command line.
---
---@param grid integer? The popupmenu anchor grid from Neovim.
---@return boolean # Whether this module should render the popupmenu.
function _P.is_cmdline_popupmenu(grid)
    return grid == -1 and _P.is_valid_window(_P.window)
end

--- Close command-line completion popupmenu.
function _P.close_popupmenu()
    if _P.is_valid_window(_P.popup_window) then
        pcall(vim.api.nvim_win_close, _P.popup_window, true)
    end

    _P.popup_window = nil
end

--- Ensure command-line completion is exposed as a popupmenu instead of one-row wildmenu.
function _P.ensure_popupmenu_completion()
    if not vim.tbl_contains(vim.opt.wildoptions:get(), "pum") then
        vim.opt.wildoptions:append("pum")
    end
end

--- Attach only to external command-line and popupmenu UI events, leaving messages native.
function _P.attach_cmdline_ui()
    pcall(vim.ui_detach, _P.namespace)

    local ok = pcall(vim.ui_attach, _P.namespace, { ext_cmdline = true, ext_popupmenu = true }, function(event, ...)
        if event == "cmdline_show" then
            local content, position, firstc, prompt, indent = ...

            if vim.tbl_contains(M.config.native_types, firstc) then
                _P.close_window()

                return false
            end

            _P.schedule_show_cmdline(content, position, firstc, prompt, indent)

            return true
        elseif event == "cmdline_pos" then
            local position = ...
            local generation = _P.generation

            vim.schedule(function()
                if generation == _P.generation then
                    _P.set_cursor_position(position)
                    _P.flush_redraw()
                end
            end)

            return true
        elseif event == "cmdline_hide" then
            _P.generation = _P.generation + 1
            vim.schedule(function()
                _P.close_window()
                _P.flush_redraw()
            end)

            return true
        elseif event == "popupmenu_show" then
            local items, selected, row, column, grid = ...
            local anchor = _P.get_popupmenu_anchor(row, column, grid)

            vim.schedule(function()
                _P.show_popupmenu(items, selected, anchor)
                _P.flush_redraw()
            end)

            return true
        elseif event == "popupmenu_select" then
            if not _P.handling_cmdline_popupmenu then
                return false
            end

            local selected = ...
            vim.schedule(function()
                _P.select_popupmenu(selected)
                _P.flush_redraw()
            end)

            return true
        elseif event == "popupmenu_hide" then
            if not _P.handling_cmdline_popupmenu then
                return false
            end

            vim.schedule(function()
                _P.close_popupmenu()
                _P.handling_cmdline_popupmenu = false
                _P.flush_redraw()
            end)

            return true
        elseif event == "cmdline_special_char" then
            return true
        elseif event == "cmdline_block_show" or event == "cmdline_block_append" or event == "cmdline_block_hide" then
            _P.generation = _P.generation + 1
            vim.schedule(function()
                _P.close_window()
                _P.flush_redraw()
            end)

            return false
        end

        return false
    end)

    if not ok then
        vim.notify("tiny_cmdline could not attach ext_cmdline UI", vim.log.levels.WARN)
    end
end

--- Set up centered command-line UI.
---
---@param opts _my.cmdline.Configuration?
function M.setup(opts)
    if M._initialized then
        return
    end

    M._initialized = true
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    if M.config.border == nil then
        local border = vim.o.winborder
        M.config.border = border ~= "" and border or "rounded"
    end

    vim.api.nvim_set_hl(0, "TinyCmdlineNormal", { link = "MsgArea", default = true })
    vim.api.nvim_set_hl(0, "TinyCmdlineBorder", { link = "FloatBorder", default = true })
    vim.api.nvim_set_hl(0, "TinyCmdlineCursor", { link = "Cursor", default = true })

    _P.ensure_message_row()
    _P.ensure_popupmenu_completion()
    _P.attach_cmdline_ui()
end

M._P = _P

M.setup(vim.g.tiny_cmdline)

return M
