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
---@type string?
_P.cmdline_type = nil
---@type string
_P.current_line = ""
---@type integer
_P.prompt_width = 0
---@type integer
_P.generation = 0

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
--- window integer? The window id to inspect.
--- boolean # Whether the id points to a valid window.
function _P.is_valid_window(window)
    return window ~= nil and window > 0 and vim.api.nvim_win_is_valid(window)
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

--- Move the floating-window cursor to match the command-line cursor.
---
---@param position integer Current cursor position inside the command text.
function _P.set_cursor_position(position)
    if not _P.is_valid_window(_P.window) then
        return
    end

    local column = _P.prompt_width + vim.fn.strdisplaywidth(_P.current_line:sub(_P.prompt_width + 1, _P.prompt_width + position))
    pcall(vim.api.nvim_win_set_cursor, _P.window, { 1, math.max(0, column) })
end

--- Attach only to external command-line UI events, leaving messages native.
function _P.attach_cmdline_ui()
    pcall(vim.ui_detach, _P.namespace)

    local ok = pcall(vim.ui_attach, _P.namespace, { ext_cmdline = true }, function(event, ...)
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

    _P.ensure_message_row()
    _P.attach_cmdline_ui()
end

M._P = _P

M.setup(vim.g.tiny_cmdline)

return M
