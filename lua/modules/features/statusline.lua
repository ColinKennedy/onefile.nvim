--- Build the custom statusline with mode colors, git branch, Grapple marks, and cursor progress.
local _P = {}
local core_helpers = require("modules.utilities.core_helpers")
local git_status = require("modules.utilities.git_status")

-- TODO: Make these colors better later
---@type table<string, string>
local _Color = {
    command = "#e5c07b",
    normal = "#98c379",
    pending = "#98f390",
    visual = "#803a95",
    insert = "#61afef",
    replace = "#11d0ef",
}

-- Note: termcodes \19 and \22 are ^S and ^V
---@type table<string, {name: string, hl: string}>
local _ModeColor = {
    ["n"] = { name = "NORMAL", hl = _Color.normal },
    ["no"] = { name = "OP-PENDING", hl = _Color.pending },
    ["nov"] = { name = "OP-PENDING", hl = _Color.pending },
    ["noV"] = { name = "OP-PENDING", hl = _Color.pending },
    ["no\22"] = { name = "OP-PENDING", hl = _Color.pending },
    ["niI"] = { name = "NORMAL", hl = _Color.normal },
    ["niR"] = { name = "NORMAL", hl = _Color.normal },
    ["niV"] = { name = "NORMAL", hl = _Color.normal },
    ["nt"] = { name = "NORMAL", hl = _Color.normal },
    ["ntT"] = { name = "NORMAL", hl = _Color.normal },
    ["v"] = { name = "VISUAL", hl = _Color.visual },
    ["vs"] = { name = "VISUAL", hl = _Color.visual },
    ["V"] = { name = "V-LINE", hl = _Color.visual },
    ["Vs"] = { name = "V-LINE", hl = _Color.visual },
    ["\22"] = { name = "V-BLOCK", hl = _Color.visual },
    ["\22s"] = { name = "V-BLOCK", hl = _Color.visual },
    ["s"] = { name = "SELECT", hl = _Color.insert },
    ["S"] = { name = "S-LINE", hl = _Color.normal },
    ["\19"] = { name = "S-BLOCK", hl = _Color.normal },
    ["i"] = { name = "INSERT", hl = _Color.insert },
    ["ic"] = { name = "INSERT", hl = _Color.insert },
    ["ix"] = { name = "INSERT", hl = _Color.insert },
    ["R"] = { name = "REPLACE", hl = _Color.replace },
    ["Rc"] = { name = "REPLACE", hl = _Color.replace },
    ["Rx"] = { name = "REPLACE", hl = _Color.replace },
    ["Rv"] = { name = "V-REPLACE", hl = _Color.replace },
    ["Rvc"] = { name = "V-REPLACE", hl = _Color.replace },
    ["Rvx"] = { name = "V-REPLACE", hl = _Color.replace },
    ["c"] = { name = "COMMAND", hl = _Color.command },
    ["cv"] = { name = "EX", hl = _Color.command },
    ["ce"] = { name = "EX", hl = _Color.command },
    ["r"] = { name = "REPLACE", hl = _Color.normal },
    ["rm"] = { name = "MORE", hl = _Color.normal },
    ["r?"] = { name = "CONFIRM", hl = _Color.normal },
    ["!"] = { name = "SHELL", hl = _Color.normal },
    ["t"] = { name = "TERMINAL", hl = _Color.command },
}

--- Define a new `name` highlight based on `source` + `overrides`.
---
---@param name string
---    The highlight to make (or reuse).
---@param source string
---    The existing Vim highlight group to draw from.
---@param overrides vim.api.keyset.highlight?
---    Any highlight options to layer on top of `source`.
---
function _P.clone_highlight(name, source, overrides)
    ---@type vim.api.keyset.highlight
    local highlight = {}
    highlight = vim.tbl_extend("force", highlight, vim.api.nvim_get_hl(0, { name = source, link = false }))

    for key, value in pairs(overrides or {}) do
        highlight[key] = value
    end

    vim.api.nvim_set_hl(0, name, highlight)
end

---@return string # The Neovim statusline for saved grapple buffers
function _P.get_grapple_statusline()
    ---@type string[]
    local output = {}
    local current_buffer = vim.api.nvim_get_current_buf()
    local native_grapple = require("modules.plugins.native_grapple.core")

    for index, buffer_number, buffer_path in native_grapple.iter_bookmarks() do
        local buffer_name = vim.fs.basename(buffer_path)
        local group = "%#StatusGrappleInactive#"

        if buffer_number == current_buffer then
            group = "%#StatusGrappleActive#"
        end

        table.insert(output, group)
        table.insert(output, string.format("%s. %s", index, buffer_name))
    end

    if vim.tbl_isempty(output) then
        return ""
    end

    return " " .. table.concat(output, " ") .. " "
end

---@return string # Get the git branch name or an empty string.
_G.get_git_branch_label_safe = function()
    local core_editor_setup = require("modules.features.core_editor_setup")

    return core_editor_setup.get_git_branch_label_safe()
end

local _STATUSLINE_GROUP = vim.api.nvim_create_augroup("my.statusline", { clear = true })

vim.api.nvim_create_autocmd("DirChanged", {
    group = _STATUSLINE_GROUP,
    desc = "Sync statusline-only directory state after :cd / :tcd.",
    callback = function()
        local cwd = vim.v.event.cwd

        vim.schedule(function()
            require("modules.plugins.native_grapple.core").sync_branch(cwd)
            vim.cmd.redrawstatus()
        end)
    end,
})

local dark_lefthand_background = "#2c323c" -- NOTE: Blueish-dark gray
local lighter_background = "#3e4452" -- NOTE: Just a bit lighter than `dark_lefthand_background`

vim.api.nvim_set_hl(0, "StatusMode", {}) -- NOTE: We auto-replace the `bg` in another section.
vim.api.nvim_set_hl(0, "StatusLine", { fg = "#dddddd", bg = dark_lefthand_background })
vim.api.nvim_set_hl(0, "StatusGit", { bg = lighter_background })
_P.clone_highlight("StatusGitAhead", "DiffAdd", { bg = lighter_background })
_P.clone_highlight("StatusGitBehind", "WarningMsg", { bg = lighter_background })
_P.clone_highlight("StatusGitConflict", "ErrorMsg", { bg = lighter_background, bold = true })
_P.clone_highlight("StatusGitDeleted", "WarningMsg", { bg = lighter_background })
_P.clone_highlight("StatusGitModified", "Type", { bg = lighter_background })
_P.clone_highlight("StatusGitRenamed", "Search", { bg = lighter_background })
_P.clone_highlight("StatusGitSeparator", "Comment", { bg = lighter_background })
_P.clone_highlight("StatusGitStaged", "Title", { bg = lighter_background })
_P.clone_highlight("StatusGitStashed", "Special", { bg = lighter_background })
_P.clone_highlight("StatusGitUntracked", "DiagnosticHint", { bg = lighter_background })
vim.api.nvim_set_hl(0, "StatusLightArrow", { fg = lighter_background, bg = dark_lefthand_background })

_P.clone_highlight("StatusPosition", "Comment", { fg = "#aaaaaa", bg = lighter_background })
_P.clone_highlight("StatusProgress", "Comment", { fg = "#aaaaaa", bg = lighter_background })
_P.clone_highlight("StatusGrappleInactive", "Comment", { bg = dark_lefthand_background })
_P.clone_highlight("StatusGrappleActive", "Special", { bold = true, bg = dark_lefthand_background })

local left_arrow = ">"
local right_arrow = "<"
local left_arrow_outline = ">>"

if core_helpers.IS_NERDFONT_ALLOWED then
    -- NOTE: Technically these are regular unicodes, not nerd font. But whatever.
    left_arrow = ""
    right_arrow = ""
    left_arrow_outline = " "
end

---@return string # Get the optional git-details and grapple statusline tail.
_G.get_git_and_grapple_statusline = function()
    local details = git_status.get_statusline()
    local grapple = _P.get_grapple_statusline()

    if details == "" and grapple == "" then
        return " %#StatusLightArrow#" .. left_arrow
    end

    ---@type string[]
    local output = {}

    if details ~= "" then
        table.insert(output, "%#StatusGit#" .. left_arrow_outline)
        table.insert(output, details)
    end

    if grapple ~= "" then
        table.insert(output, "%#StatusLightArrow#" .. left_arrow)
        table.insert(output, grapple)
    elseif details ~= "" then
        table.insert(output, "%#StatusLightArrow#" .. left_arrow)
    end

    return table.concat(output, "")
end

vim.o.statusline = table.concat({
    "%#StatusMode#   ",
    "%#StatusModeArrow#",
    left_arrow,
    "%#StatusGit# ",
    "%{v:lua.get_git_branch_label_safe()}",
    "%{%v:lua.get_git_and_grapple_statusline()%}",
    "%=", -- Spacer
    "%#StatusLightArrow# ",
    right_arrow,
    "%#StatusLine#",
    "%#StatusPosition# %l:%c",
    "%#StatusProgress# [%{v:lua.get_window_line_progress()}] ",
    "%#StatusModeArrow#",
    right_arrow,
    "%#StatusMode#   ",
})

--- Set the statusbar colors according to `mode`.
---
---@param mode string The Neovim mode to display. e.g. `"n"` shows NORMAL mode colors.
---
function _P.update_status_mode_colors(mode)
    local color = _ModeColor.n.hl
    local mode_color = _ModeColor[mode]

    if mode_color then
        color = mode_color.hl
    end

    _P.clone_highlight("StatusMode", "StatusMode", { bg = color })
    _P.clone_highlight("StatusModeArrow", "StatusMode", { fg = color, bg = lighter_background })
end

vim.api.nvim_create_autocmd({ "ModeChanged", "InsertEnter" }, {
    callback = function(args)
        local mode = args.match:sub(3, 3)
        _P.update_status_mode_colors(mode)
    end,
})

git_status.setup()

_P.update_status_mode_colors(vim.api.nvim_get_mode().mode)
