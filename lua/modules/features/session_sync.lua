local _shared = require("modules.utilities.shared_environment")

_shared.run(function()
--- Session sync

-- TODO: Once `SessionLoadPre` exists, use that instead of this
pcall(function()
    _SESSION_MANAGER:sync_current_session()
end)

end)
