--- Center Neovim's ui2 command line while keeping ui2 messages bottom-oriented.

local M = {}
local _P = {}

M._initialized = false

---@class _my.cmdline.Adapters
M.adapters = {
    --- Reposition blink.cmp's command-line completion menu when present.
    blink = function()
        local ok, menu = pcall(require, "blink.cmp.completion.windows.menu")

        if ok and menu.win and menu.win:is_open() then
            pcall(menu.update_position)
        end
    end,
}

---@class _my.cmdline.WidthConfiguration
---@field value string|integer Width: "60%" is a fraction of editor columns, integer is absolute columns.
---@field min integer Minimum width in columns.
---@field max integer Maximum width in columns.

---@class _my.cmdline.PositionConfiguration
---@field x string|integer Horizontal position: "50%" is centered, integer is absolute columns from the left.
---@field y string|integer Vertical position: "50%" is centered, integer is absolute rows from the top.

---@class _my.cmdline.MessageConfiguration
---@field targets table<string, 'cmd'|'msg'|'pager'> Message kinds or triggers routed to ui2 targets.
---@field target 'cmd'|'msg'|'pager' Default message target.

---@class _my.cmdline.Configuration
---@field width _my.cmdline.WidthConfiguration Cmdline window width.
---@field position _my.cmdline.PositionConfiguration Cmdline window position.
---@field border string? nil inherits `vim.o.winborder` at setup time.
---@field menu_col_offset integer Completion menu offset from the window's left inner edge.
---@field native_types string[] Cmdline types shown by ui2's bottom cmdline instead of the centered float.
---@field msg _my.cmdline.MessageConfiguration ui2 message routing.
---@field on_reposition fun()? Called after every cmdline reposition.

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
    menu_col_offset = 3,
    native_types = { "/", "?" },
    msg = {
        target = "cmd",
        targets = {
            typed_cmd = "pager",
            list_cmd = "pager",
            lua_print = "pager",
        },
    },
    on_reposition = nil,
}

---@type string?
_P.cmdline_type = nil
---@type table?
_P.original_ui_cmdline_pos = nil
---@type table?
_P.cmd_window_saved = nil
---@type table?
_P.ui2 = nil
---@type boolean
_P.wrapped = false

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

--- Keep the user's real cmdheight so the statusline and bottom message area remain stable.
function _P.keep_configured_cmdheight()
    local ui2 = _P.get_ui2()

    if ui2 then
        ui2.cmdheight = vim.o.cmdheight
    end
end

--- Ensure command-line completion uses a popupmenu.
function _P.ensure_popupmenu_completion()
    if not vim.tbl_contains(vim.opt.wildoptions:get(), "pum") then
        vim.opt.wildoptions:append("pum")
    end
end

--- Load Neovim's ui2 module.
---
---@return table? # The ui2 module when available.
function _P.get_ui2()
    if _P.ui2 then
        return _P.ui2
    end

    local ok, ui2 = pcall(require, "vim._core.ui2")

    if not ok then
        return nil
    end

    _P.ui2 = ui2

    return ui2
end

--- Get ui2's command-line window.
---
---@return integer? # A valid window id, when ui2 has one.
function _P.get_cmd_window()
    local ui2 = _P.get_ui2()
    local window = ui2 and ui2.wins and ui2.wins.cmd

    if window and vim.api.nvim_win_is_valid(window) then
        return window
    end

    return nil
end

--- Restore ui2's cmd window to its original bottom placement.
function _P.restore_cmd_window()
    local window = _P.get_cmd_window()

    if window and _P.cmd_window_saved then
        pcall(vim.api.nvim_win_set_config, window, _P.cmd_window_saved)
        _P.cmd_window_saved = nil
    end
end

--- Move ui2's command-line window to its centered position while typing.
function _P.reposition()
    if not _P.cmdline_type then
        return
    end

    local window = _P.get_cmd_window()

    if not window then
        return
    end

    local current = vim.api.nvim_win_get_config(window)

    if not _P.cmd_window_saved then
        _P.cmd_window_saved = {
            relative = current.relative,
            anchor = current.anchor,
            col = current.col,
            row = current.row,
            width = current.width,
            border = current.border,
        }
        vim.wo[window].winhighlight = "Normal:TinyCmdlineNormal,FloatBorder:TinyCmdlineBorder"
    end

    local content_height = math.max(1, vim.api.nvim_win_get_height(window))

    if vim.tbl_contains(M.config.native_types, _P.cmdline_type) then
        local target_row = math.max(0, vim.o.lines - content_height)

        if current.relative ~= "editor" or current.row ~= target_row or current.col ~= 0 or current.width ~= vim.o.columns then
            pcall(vim.api.nvim_win_set_config, window, {
                relative = "editor",
                row = target_row,
                col = 0,
                width = vim.o.columns,
                border = "none",
            })
        end

        vim.g.ui_cmdline_pos = _P.original_ui_cmdline_pos

        return
    end

    local width, row, column, border_width = _P.get_geometry(content_height)

    if current.relative ~= "editor" or current.row ~= row or current.col ~= column or current.width ~= width then
        pcall(vim.api.nvim_win_set_config, window, {
            relative = "editor",
            row = row,
            col = column,
            width = width,
            border = M.config.border,
        })
    end

    vim.g.ui_cmdline_pos = { row + content_height + (border_width * 2), column + border_width + M.config.menu_col_offset }
end

--- Wrap ui2's cmdline renderer so we can reposition after it updates text and height.
function _P.wrap_cmdline_show()
    if _P.wrapped then
        return
    end

    local ok, cmdline = pcall(require, "vim._core.ui2.cmdline")

    if not ok then
        return
    end

    local original_cmdline_show = cmdline.cmdline_show

    cmdline.cmdline_show = function(...)
        local result = original_cmdline_show(...)

        if not _P.cmdline_type then
            return result
        end

        _P.keep_configured_cmdheight()
        _P.reposition()

        return result
    end

    _P.wrapped = true
end

--- Wrap ui2 and reposition once ui2 has created its cmd window.
function _P.wrap_and_reposition()
    _P.wrap_cmdline_show()
    _P.reposition()
end

--- Enable Neovim's ui2 with bottom-oriented message routing.
function _P.enable_ui2()
    local ui2 = _P.get_ui2()

    if not ui2 then
        vim.notify("tiny_cmdline could not load vim._core.ui2", vim.log.levels.WARN)

        return
    end

    ui2.enable({
        enable = true,
        msg = {
            target = M.config.msg.target,
            targets = M.config.msg.targets,
            cmd = { height = 0.5 },
            dialog = { height = 0.5 },
            msg = { height = 0.5, timeout = 4000 },
            pager = { height = 1 },
        },
    })
end

--- Set up centered command-line UI using Neovim's experimental ui2 module.
---
---@param opts _my.cmdline.Configuration?
function M.setup(opts)
    if M._initialized then
        return
    end

    M._initialized = true

    if vim.fn.has("nvim-0.12") == 0 then
        vim.notify("tiny_cmdline requires Neovim >= 0.12", vim.log.levels.WARN)

        return
    end

    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    if M.config.border == nil then
        local border = vim.o.winborder
        M.config.border = border ~= "" and border or "rounded"
    end

    vim.api.nvim_set_hl(0, "TinyCmdlineNormal", { link = "MsgArea", default = true })
    vim.api.nvim_set_hl(0, "TinyCmdlineBorder", { link = "FloatBorder", default = true })

    _P.original_ui_cmdline_pos = vim.g.ui_cmdline_pos
    _P.cmd_window_saved = nil
    _P.ensure_popupmenu_completion()
    _P.enable_ui2()

    local group = vim.api.nvim_create_augroup("tiny-cmdline", { clear = true })

    vim.api.nvim_create_autocmd("CmdlineEnter", {
        group = group,
        callback = function()
            _P.cmdline_type = vim.fn.getcmdtype()
        end,
    })

    vim.api.nvim_create_autocmd("CmdlineLeave", {
        group = group,
        callback = function()
            _P.cmdline_type = nil
            vim.g.ui_cmdline_pos = _P.original_ui_cmdline_pos
            _P.restore_cmd_window()
            vim.schedule(_P.keep_configured_cmdheight)
        end,
    })

    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "cmd",
        callback = function()
            vim.schedule(_P.wrap_and_reposition)
        end,
    })

    vim.api.nvim_create_autocmd({ "VimResized", "TabEnter" }, {
        group = group,
        callback = function()
            vim.schedule(function()
                _P.reposition()

                if M.config.on_reposition then
                    M.config.on_reposition()
                end
            end)
        end,
    })

    vim.schedule(_P.wrap_and_reposition)
end

M._P = _P

M.setup(vim.g.tiny_cmdline)

return M
