-- SPDX-License-Identifier: AGPL-3.0-only

local NetworkState = {}
NetworkState.__index = NetworkState

local function defaultLipcloader()
    local ok, lipc = pcall(require, "liblipclua")
    return ok, lipc
end

local function defaultPopen(command, mode)
    return io.popen(command, mode)
end

function NetworkState:new(options)
    options = options or {}
    return setmetatable({
        device = options.device or require("device"),
        network_mgr = options.network_mgr or require("ui/network/manager"),
        lipc_loader = options.lipc_loader or defaultLipcloader,
        popen = options.popen or defaultPopen,
    }, self)
end

function NetworkState:_kindleAirplaneMode()
    if not self.device or not self.device.isKindle or not self.device:isKindle() then
        return nil
    end

    local ok, lipc = self.lipc_loader()
    if ok and lipc and lipc.init then
        local handle = lipc.init("com.github.koreader.readwisereader")
        if handle then
            local value
            local got = pcall(function()
                value = handle:get_int_property("com.lab126.cmd", "airplaneMode")
            end)
            pcall(handle.close, handle)
            if got and value ~= nil then
                return tonumber(value) == 1
            end
        end
    end

    local pipe = self.popen(
        "lipc-get-prop -i com.lab126.cmd airplaneMode 2>/dev/null",
        "r"
    )
    if pipe then
        local value = pipe:read("*number")
        pipe:close()
        if value ~= nil then
            return tonumber(value) == 1
        end
    end

    return nil
end

function NetworkState:isAvailable()
    local airplane = self:_kindleAirplaneMode()
    if airplane == true then
        return false, "kindle_airplane_mode"
    end

    if self.network_mgr.queryNetworkState then
        pcall(self.network_mgr.queryNetworkState, self.network_mgr)
    end

    if self.network_mgr.isWifiOn then
        local ok, value = pcall(self.network_mgr.isWifiOn, self.network_mgr)
        if ok and value == false then
            return false, "wifi_off"
        end
    end

    if self.network_mgr.isConnected then
        local ok, value = pcall(self.network_mgr.isConnected, self.network_mgr)
        if ok and value == false then
            return false, "not_connected"
        end
    end

    local ok, online = pcall(self.network_mgr.isOnline, self.network_mgr)
    if not ok or online ~= true then
        return false, "not_online"
    end

    return true, "online"
end

NetworkState._defaultLipcloader = defaultLipcloader

return NetworkState
