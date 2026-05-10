--- Extend vim.notify with log-level filtering and optional file logging.

local _P = {}

local _ORIGINAL_VIM_NOTIFY = vim.notify

_P.ENABLE_NOTIFY_LOGGING_VARIABLE = "VIM_ENABLE_NOTIFY_LOGGING"
_P.MINIMUM_LOG_LEVEL = tonumber(os.getenv("VIM_LOG_LEVEL") or "2") or vim.log.levels.INFO
_P.TEMPORARY_LOG_PATH = nil

---@param level integer? Some raw log value.
---@return integer # A log level that can be compared against vim.log.levels.
function _P.normalize_log_level(level)
    return level or vim.log.levels.INFO
end

--- Convert `level` number into a real Neovim log level label (e.g. DEBUG).
---
---@param level integer Some raw log value.
---@return string # The found level, if any.
function _P.get_readable_log_level_label(level)
    for name, value in pairs(vim.log.levels) do
        if value == level then
            return name
        end
    end

    return tostring(level)
end

---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(message, level, ...)
    if _P.normalize_log_level(level) < _P.MINIMUM_LOG_LEVEL then
        return
    end

    _ORIGINAL_VIM_NOTIFY(message, level, ...)
end

if (os.getenv(_P.ENABLE_NOTIFY_LOGGING_VARIABLE) or "0") ~= "0" then
    local _ORIGINAL_FILTERED_VIM_NOTIFY = vim.notify
    _P.TEMPORARY_LOG_PATH = os.tmpname()

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(message, level, ...)
        local normalized_level = _P.normalize_log_level(level)
        local handler, error_ = io.open(_P.TEMPORARY_LOG_PATH, "a")

        if not handler then
            _ORIGINAL_FILTERED_VIM_NOTIFY(
                string.format('Log path "%s" could not be written to. Error: %s', _P.TEMPORARY_LOG_PATH, error_),
                vim.log.levels.ERROR
            )

            return
        end

        local level_name = _P.get_readable_log_level_label(normalized_level)
        handler:write(string.format("%s [%s]: %s\n", os.date("%Y-%m-%d:%X"), level_name, message))
        handler:close()

        _ORIGINAL_FILTERED_VIM_NOTIFY(message, level, ...)
    end
end

vim.api.nvim_create_user_command("OpenLogPath", function()
    if not _P.TEMPORARY_LOG_PATH then
        vim.notify(
            string.format(
                "No logging was enabled for this Neovim. Use %s=1 and restart to turn it on.",
                _P.ENABLE_NOTIFY_LOGGING_VARIABLE
            ),
            vim.log.levels.ERROR
        )

        return
    end

    print(string.format('Opening "%s" log file.', _P.TEMPORARY_LOG_PATH))
    vim.cmd.edit({ args = { _P.TEMPORARY_LOG_PATH }, mods = { silent = true } })
end, { nargs = "?", desc = "View/Edit the vim.notify(...) master log file." })

return _P
