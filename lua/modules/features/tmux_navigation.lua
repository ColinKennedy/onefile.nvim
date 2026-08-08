--- Move between Neovim windows and adjacent tmux panes with the same keys.

local M = {}
local _P = {}

---@alias _my.tmux.DirectionKey "h" | "j" | "k" | "l"
---@alias _my.tmux.DirectionName "left" | "down" | "up" | "right"

---@class _my.tmux.DirectionDetails
---@field description _my.tmux.DirectionName
---@field resize_amount integer
---@field send_target string
---@field tmux string
---@field tmux_resize_amount integer

---@type _my.tmux.DirectionName[]
local _DIRECTION_NAMES = { "left", "down", "up", "right" }

---@type table<_my.tmux.DirectionKey, _my.tmux.DirectionDetails>
local _DIRECTIONS = {
    h = {
        description = "left",
        resize_amount = 5,
        send_target = "{left-of}",
        tmux = "L",
        tmux_resize_amount = 3,
    },
    j = {
        description = "down",
        resize_amount = 2,
        send_target = "{down-of}",
        tmux = "D",
        tmux_resize_amount = 3,
    },
    k = {
        description = "up",
        resize_amount = 2,
        send_target = "{up-of}",
        tmux = "U",
        tmux_resize_amount = 3,
    },
    l = {
        description = "right",
        resize_amount = 5,
        send_target = "{right-of}",
        tmux = "R",
        tmux_resize_amount = 3,
    },
}

---@type table<_my.tmux.DirectionName, _my.tmux.DirectionKey>
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
    ---@type string[]
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

--- The tmux format that reports whether the active pane touches an edge.
---
---@type table<_my.tmux.DirectionKey, string>
local _PANE_EDGE_FORMAT = {
    h = "#{pane_at_left}",
    j = "#{pane_at_bottom}",
    k = "#{pane_at_top}",
    l = "#{pane_at_right}",
}

--- Check whether the current window has a Neovim split in `direction`.
---
---@param direction _my.tmux.DirectionKey
---@return boolean
local function _has_split_in_direction(direction)
    return vim.fn.winnr(direction) ~= vim.fn.winnr()
end

--- Check whether a tmux pane sits next to Neovim in `direction`.
---
--- `#{pane_at_<edge>}` is `1` when the active tmux pane is flush against that
--- edge of its window (so nothing is beyond it) and `0` when another pane is
--- adjacent. We only consult tmux when Neovim itself has no split to resize in
--- that direction, which is what lets alt-j resize a tmux pane sitting below the
--- bottom-most split instead of resizing Neovim.
---
---@param direction _my.tmux.DirectionKey
---@return boolean
local function _has_adjacent_tmux_pane(direction)
    if not require("modules.utilities.core_helpers").in_tmux() then
        return false
    end

    local output = vim.fn.system({ "tmux", "display-message", "-p", "-F", _PANE_EDGE_FORMAT[direction] })

    return vim.trim(output) == "0"
end

--- Describe what borders the current window on `direction`'s side.
---
--- Neovim splits take priority; tmux is only consulted when there is no split,
--- so a normal grid cell never shells out to tmux.
---
---@param direction _my.tmux.DirectionKey
---@return "split" | "pane" | nil
local function _neighbor_kind(direction)
    if _has_split_in_direction(direction) then
        return "split"
    end

    if _has_adjacent_tmux_pane(direction) then
        return "pane"
    end

    return nil
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
function M._resize(direction)
    local core_helpers = require("modules.utilities.core_helpers")
    local details = _DIRECTIONS[direction]

    -- NOTE: Both keys on an axis act on the *same* divider. Vertically that is
    -- the cell below when one exists (otherwise the cell above); horizontally the
    -- cell to the right when one exists (otherwise the left). A "cell" is a
    -- Neovim split or a tmux pane -- both are detected and handled seamlessly.
    local vertical = direction == "j" or direction == "k"
    local far = vertical and "j" or "l"
    local near = vertical and "k" or "h"

    local target = far
    local kind = _neighbor_kind(far)

    if not kind then
        target = near
        kind = _neighbor_kind(near)
    end

    if not kind then
        -- The window fills the whole axis with no split or pane beyond it.
        return
    end

    if kind == "pane" then
        -- Move the shared tmux border in the key's geometric direction (j down,
        -- k up, h left, l right); tmux moves whichever border that touches.
        _run_tmux_pane_command(direction, "resize-pane")

        return
    end

    -- Resize within Neovim. The key grows the current window when it pushes the
    -- targeted divider away from the window and shrinks it otherwise, which
    -- reduces to: grow when the key points at the targeted side.
    local amount = (direction == target) and details.resize_amount or -details.resize_amount

    core_helpers.resize_window(vertical and "height" or "width", amount)
end

--- Build the tmux command used to send text to an adjacent pane.
---
---@param direction_name _my.tmux.DirectionName The adjacent tmux pane direction.
---@param text string The text to send. Literal `<CR>` is converted to Enter.
---@return string[] # The `tmux send-keys` command arguments.
function M._get_send_text_arguments(direction_name, text)
    local direction = _DIRECTION_BY_NAME[direction_name]
    local details = _DIRECTIONS[direction]
    ---@type string[]
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

    vim.fn.system(M._get_send_text_arguments(direction_name, text))
end

--- Parse and run a `:SendTmux` command.
---
---@param arguments string The raw command arguments.
function M.send_text_from_command(arguments)
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
function M.complete_send_text(argument_lead, command_line)
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
        M._resize(direction)
    end, {
        desc = string.format('Resize the "%s" split or tmux pane.', details.description),
        silent = true,
    })
end

return M
