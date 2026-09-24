-- SPDX-License-Identifier: AGPL-3.0-only

local NetworkState = require("platform/network_state")

local function device(kindled)
    return { isKindle = function() return kindled == true end }
end

local function manager(values)
    values = values or {}
    return {
        queryNetworkState = function() values.queried = true end,
        isWifiOn = function() return values.wifi_on ~= false end,
        isConnected = function() return values.connected ~= false end,
        isOnline = function() return values.online ~= false end,
    }
end

local function lipcWith(value)
    return function()
        return true, {
            init = function()
                return {
                    get_int_property = function(_, service, prop)
                        assert(service == "com.lab126.cmd")
                        assert(prop == "airplaneMode")
                        return value
                    end,
                    close = function() end,
                }
            end,
        }
    end
end

return function()
    do
        local m = manager{ online = true, wifi_on = true, connected = true }
        local state = NetworkState:new{
            device = device(true),
            network_mgr = m,
            lipc_loader = lipcWith(1),
            popen = function() error("shell fallback must not run") end,
        }
        local online, reason = state:isAvailable()
        assert(online == false)
        assert(reason == "kindle_airplane_mode")
    end

    do
        local m = manager{ online = true, wifi_on = true, connected = true }
        local state = NetworkState:new{
            device = device(true),
            network_mgr = m,
            lipc_loader = lipcWith(0),
            popen = function() error("shell fallback must not run") end,
        }
        local online, reason = state:isAvailable()
        assert(online == true)
        assert(reason == "online")
        assert(m.queried == true)
    end

    do
        local m = manager{ online = true, wifi_on = true, connected = false }
        local state = NetworkState:new{
            device = device(false),
            network_mgr = m,
            lipc_loader = function() return false end,
            popen = function() error("non-Kindle must not query LIPC shell") end,
        }
        local online, reason = state:isAvailable()
        assert(online == false)
        assert(reason == "not_connected")
    end
end
