-- SPDX-License-Identifier: AGPL-3.0-only

local Constants = require("constants")

local Config = {}
Config.__index = Config

local function copyList(values)
    local copy = {}
    for _, value in ipairs(values or {}) do
        copy[#copy + 1] = value
    end
    return copy
end

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

function Config:getDownloadDirectory()
    local path = self.settings:readSetting("download_directory")
    if type(path) ~= "string" or trim(path) == "" then
        return Constants.DEFAULT_DOWNLOAD_ROOT
    end
    return trim(path):gsub("/+$", "")
end

function Config:setDownloadDirectory(value)
    local path = trim(value):gsub("/+$", "")
    if path == "" then
        return false, "empty"
    end

    local under_documents = path == "/mnt/us/documents"
        or path:sub(1, #"/mnt/us/documents/") == "/mnt/us/documents/"
    if not under_documents or path:find("%z") then
        return false, "unsafe"
    end
    for component in path:gmatch("[^/]+") do
        if component == "." or component == ".." then
            return false, "unsafe"
        end
    end
    self.settings:saveSetting("download_directory", path)
    self.settings:flush()
    return true
end

function Config:_getListSetting(key, defaults)
    local value = self.settings:readSetting(key)
    if type(value) ~= "table" then
        return copyList(defaults)
    end
    local result, seen = {}, {}
    for _, item in ipairs(value) do
        if type(item) == "string" and item ~= "" and not seen[item] then
            seen[item] = true
            result[#result + 1] = item
        end
    end
    return result
end

function Config:_setListSetting(key, values)
    self.settings:saveSetting(key, copyList(values))
    self.settings:flush()
end

function Config:getSyncLocations()
    return self:_getListSetting("sync_locations", Constants.DEFAULT_SYNC_LOCATIONS)
end

function Config:getSyncCategories()
    return self:_getListSetting("sync_categories", Constants.DEFAULT_SYNC_CATEGORIES)
end

local function setEnabled(config, key, defaults, value, enabled)
    local values = config:_getListSetting(key, defaults)
    local result, found = {}, false
    for _, item in ipairs(values) do
        if item == value then
            found = true
            if enabled then result[#result + 1] = item end
        else
            result[#result + 1] = item
        end
    end
    if enabled and not found then result[#result + 1] = value end
    config:_setListSetting(key, result)
end

local function isEnabled(values, value)
    for _, item in ipairs(values) do
        if item == value then return true end
    end
    return false
end

function Config:setSyncLocationEnabled(location, enabled)
    setEnabled(self, "sync_locations", Constants.DEFAULT_SYNC_LOCATIONS, location, enabled == true)
end

function Config:isSyncLocationEnabled(location)
    return isEnabled(self:getSyncLocations(), location)
end

function Config:setSyncCategoryEnabled(category, enabled)
    setEnabled(self, "sync_categories", Constants.DEFAULT_SYNC_CATEGORIES, category, enabled == true)
end

function Config:isSyncCategoryEnabled(category)
    return isEnabled(self:getSyncCategories(), category)
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
