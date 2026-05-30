--- Shared font and icon choices for UI modules.

local M = {}

---@enum _my.fonts.Icon
M.Icon = {
    aerial_class = "aerial_class",
    aerial_fallback = "aerial_fallback",
    aerial_function = "aerial_function",
}

---@type table<string, string>
local _ASCII_ICONS = {
    [M.Icon.aerial_class] = "CC",
    [M.Icon.aerial_fallback] = "--",
    [M.Icon.aerial_function] = "FF",
}

---@type table<string, string>
local _NERDFONT_ICONS = {
    [M.Icon.aerial_class] = "󰠱",
    [M.Icon.aerial_fallback] = "--",
    [M.Icon.aerial_function] = "󰊕",
}

--- Check whether Nerd Font icons are allowed in this configuration.
---
---@return boolean # If Nerd Font icons are allowed, return `true`.
function M.is_nerdfont_allowed()
    return require("modules.utilities.core_helpers").IS_NERDFONT_ALLOWED == true
end

--- Get an icon for the current font policy.
---
---@param icon _my.fonts.Icon The icon choice to render.
---@return string # The configured icon text.
function M.get_icon(icon)
    local icons = M.is_nerdfont_allowed() and _NERDFONT_ICONS or _ASCII_ICONS

    return icons[icon] or ""
end

return M
