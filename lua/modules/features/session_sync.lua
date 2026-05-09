local core_editor_setup = require("modules.features.core_editor_setup")

--- Session sync

-- TODO: Once `SessionLoadPre` exists, use that instead of this
pcall(function()
    core_editor_setup._SESSION_MANAGER:sync_current_session()
end)
