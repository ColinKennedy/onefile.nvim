--- Move between Neovim windows and adjacent tmux panes with the same keys.

local _P = {}

---@alias _my.tmux.DirectionKey "h" | "j" | "k" | "l"
---@alias _my.tmux.DirectionName "left" | "down" | "up" | "right"

local _DIRECTION_NAMES = { "left", "down", "up", "right" }

local _DIRECTIONS = {
    h = {
        description = "left",
        edge = "left",
        resize_amount = 5,
        resize_direction = "left",
        send_target = "{left-of}",
        tmux = "L",
        tmux_resize_amount = 3,
    },
    j = {
        description = "down",
        edge = "bottom",
        resize_amount = 2,
        resize_direction = "down",
        send_target = "{down-of}",
        tmux = "D",
        tmux_resize_amount = 3,
    },
    k = {
        description = "up",
        edge = "top",
        resize_amount = 2,
        resize_direction = "up",
        send_target = "{up-of}",
        tmux = "U",
        tmux_resize_amount = 3,
    },
    l = {
        description = "right",
        edge = "right",
        resize_amount = 5,
        resize_direction = "right",
        send_target = "{right-of}",
        tmux = "R",
        tmux_resize_amount = 3,
    },
}

local _DIRECTION_BY_NAME = {
    down = "j",
    left = "h",
    right = "l",
    up = "k",
}

---@param direction _my.tmux.DirectionKey
---@param command "resize-pane" | "select-pane"
local function _run_tmux_pane_command(direction, command)
    if not require("modules.utilities.core_helpers").in_tmux() then
        return
    end

    local details = _DIRECTIONS[direction]
    local arguments = { "tmux", command, "-" .. details.tmux }

    if command == "resize-pane" then
        table.insert(arguments, tostring(details.tmux_resize_amount))
    end

    vim.fn.system(arguments)
end

local function _leave_terminal_mode_if_needed()
    if not vim.api.nvim_get_mode().mode:match("t") then
        return
    end

    pcall(function()
        require("modules.plugins.toggle_terminal").save_terminal_state()
    end)
    vim.cmd.stopinsert()
end

---@return _my.window.Edge[]?
local function _get_current_window_edges()
    local window = vim.api.nvim_get_current_win()
    local screen_width = vim.o.columns
    local screen_height = vim.o.lines - vim.o.cmdheight
    local configuration = vim.api.nvim_win_get_config(window)

    if not configuration.relative or configuration.relative ~= "" then
        return nil
    end

    local position = vim.api.nvim_win_get_position(window)
    local row = position[1]
    local column = position[2]
    local height = vim.api.nvim_win_get_height(window)
    local width = vim.api.nvim_win_get_width(window)

    ---@type _my.window.Edge[]
    local edges = {}

    if row == 0 then
        table.insert(edges, "top")
    end

    if (row + height + 1) == screen_height then
        table.insert(edges, "bottom")
    end

    if column == 0 then
        table.insert(edges, "left")
    end

    if (column + width) == screen_width then
        table.insert(edges, "right")
    end

    return edges
end

--- Split text into tmux `send-keys` arguments.
---
---@param text string The user-provided text to send.
---@return string[] # Text chunks and `Enter` key names.
local function _split_send_text(text)
    ---@type string[]
    local parts = {}
    local start = 1

    while true do
        local open, close = text:find("<CR>", start, true)

        if not open then
            local tail = text:sub(start)

            if tail ~= "" then
                table.insert(parts, tail)
            end

            return parts
        end

        local chunk = text:sub(start, open - 1)

        if chunk ~= "" then
            table.insert(parts, chunk)
        end

        table.insert(parts, "Enter")
        start = close + 1
    end
end

--- Parse a `:SendTmux` argument string.
---
---@param arguments string The raw command arguments.
---@return _my.tmux.DirectionName? # The requested direction, if present.
---@return string? # The text to send, preserving spaces after the direction.
local function _parse_send_tmux_arguments(arguments)
    local direction, text = arguments:match("^%s*(%S+)%s+(.*)$")

    if not direction then
        return nil, nil
    end

    if not _DIRECTION_BY_NAME[direction] then
        return nil, nil
    end

    return direction, text
end

--- Notify that `:SendTmux` could not be run.
---
---@param message string The error message to show.
local function _notify_send_tmux_error(message)
    vim.notify(":SendTmux " .. message, vim.log.levels.ERROR)
end

---@param direction "h" | "j" | "k" | "l"
---@return boolean
local function _is_on_directional_edge(direction)
    local edges = _get_current_window_edges()

    if not edges then
        return false
    end

    return vim.tbl_contains(edges, _DIRECTIONS[direction].edge)
end

---@param direction "h" | "j" | "k" | "l"
---@return boolean
local function _is_on_tmux_resize_edge(direction)
    local edges = _get_current_window_edges()

    if not edges then
        return false
    end

    if direction == "j" or direction == "k" then
        return vim.tbl_contains(edges, "bottom")
    end

    return vim.tbl_contains(edges, "right")
end

---@param direction "h" | "j" | "k" | "l"
---@return integer
local function _get_resize_dimension(direction)
    if direction == "j" or direction == "k" then
        return vim.api.nvim_win_get_height(0)
    end

    return vim.api.nvim_win_get_width(0)
end

---@param direction "h" | "j" | "k" | "l"
function _P.move(direction)
    _leave_terminal_mode_if_needed()

    local current_window = vim.api.nvim_get_current_win()
    vim.cmd("wincmd " .. direction)

    if vim.api.nvim_get_current_win() ~= current_window then
        return
    end

    _run_tmux_pane_command(direction, "select-pane")
end

---@param direction "h" | "j" | "k" | "l"
function _P.resize(direction)
    local core_helpers = require("modules.utilities.core_helpers")
    local details = _DIRECTIONS[direction]

    if core_helpers.in_tmux() and _is_on_tmux_resize_edge(direction) then
        _run_tmux_pane_command(direction, "resize-pane")

        return
    end

    local before = _get_resize_dimension(direction)

    core_helpers.resize_window(details.resize_direction, details.resize_amount)

    if before ~= _get_resize_dimension(direction) then
        return
    end

    if _is_on_directional_edge(direction) then
        _run_tmux_pane_command(direction, "resize-pane")
    end
end

--- Build the tmux command used to send text to an adjacent pane.
---
---@param direction_name _my.tmux.DirectionName The adjacent tmux pane direction.
---@param text string The text to send. Literal `<CR>` is converted to Enter.
---@return string[] # The `tmux send-keys` command arguments.
function _P.get_send_text_arguments(direction_name, text)
    local direction = _DIRECTION_BY_NAME[direction_name]
    local details = _DIRECTIONS[direction]
    local arguments = { "tmux", "send-keys", "-t", details.send_target }

    vim.list_extend(arguments, _split_send_text(text))

    return arguments
end

--- Send text to an adjacent tmux pane.
---
---@param direction_name _my.tmux.DirectionName The adjacent tmux pane direction.
---@param text string The text to send. Literal `<CR>` is converted to Enter.
function _P.send_text(direction_name, text)
    if not require("modules.utilities.core_helpers").in_tmux() then
        _notify_send_tmux_error("requires tmux.")

        return
    end

    vim.fn.system(_P.get_send_text_arguments(direction_name, text))
end

--- Parse and run a `:SendTmux` command.
---
---@param arguments string The raw command arguments.
function _P.send_text_from_command(arguments)
    local direction, text = _parse_send_tmux_arguments(arguments)

    if not direction or not text then
        _notify_send_tmux_error("usage: :SendTmux <left|down|up|right> <text>")

        return
    end

    _P.send_text(direction, text)
end

--- Complete the direction argument for `:SendTmux`.
---
---@param argument_lead string The current argument fragment.
---@param command_line string The whole command line.
---@return string[] # Matching direction names.
function _P.complete_send_text(argument_lead, command_line)
    local arguments = command_line:match("^%s*%S+%s*(.*)$") or ""

    if arguments:match("^%S+%s+") then
        return {}
    end

    return vim.tbl_filter(function(direction)
        return vim.startswith(direction, argument_lead)
    end, _DIRECTION_NAMES)
end

for direction, details in pairs(_DIRECTIONS) do
    vim.keymap.set({ "n", "t" }, "<C-" .. direction .. ">", function()
        _P.move(direction)
    end, {
        desc = string.format('Move to the "%s" split or tmux pane.', details.description),
        silent = true,
    })

    vim.keymap.set({ "n", "t" }, "<M-" .. direction .. ">", function()
        _P.resize(direction)
    end, {
        desc = string.format('Resize the "%s" split or tmux pane.', details.description),
        silent = true,
    })
end

return _P
