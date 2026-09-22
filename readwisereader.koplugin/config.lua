-- SPDX-License-Identifier: AGPL-3.0-only

local Constants = require("constants")

local Config = {}
Config.__index = Config

local function trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Config:new(options)
    options = options or {}

    local settings = options.settings
    if not settings then
        local DataStorage = require("datastorage")
        local LuaSettings = require("luasettings")
        local path = DataStorage:getSettingsDir() .. "/" .. Constants.SETTINGS_FILENAME
        settings = LuaSettings:open(path)
    end

    return setmetatable({
        settings = settings,
    }, self)
end

function Config:getAccessToken()
    local token = self.settings:readSetting("access_token")
    if type(token) ~= "string" or token == "" then
        return nil
    end
    return token
end

function Config:hasAccessToken()
    return self:getAccessToken() ~= nil
end

function Config:setAccessToken(value)
    local token = trim(value)
    if token == "" then
        return false, "empty"
    end

    self.settings:saveSetting("access_token", token)
    self.settings:flush()
    return true
end

function Config:clearAccessToken()
    self.settings:delSetting("access_token")
    self.settings:flush()
end

function Config:close()
    if self.settings and self.settings.close then
        self.settings:close()
    end
end

return Config
