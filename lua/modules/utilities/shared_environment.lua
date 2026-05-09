local _ENVIRONMENT = rawget(_G, "__NOPLUGINS_SHARED_ENVIRONMENT")

if not _ENVIRONMENT then
    _ENVIRONMENT = {
        _G = _G,
    }

    setmetatable(_ENVIRONMENT, {
        __index = _G,
    })

    rawset(_G, "__NOPLUGINS_SHARED_ENVIRONMENT", _ENVIRONMENT)
end

function _ENVIRONMENT.run(callback)
    setfenv(callback, _ENVIRONMENT)

    return callback()
end

return _ENVIRONMENT
