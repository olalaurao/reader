-- SPDX-License-Identifier: AGPL-3.0-only

local Collections = {}
Collections.__index = Collections

local LOCATION_COLLECTIONS = {
    new = "Readwise: Inbox",
    later = "Readwise: Later",
    shortlist = "Readwise: Shortlist",
    archive = "Readwise: Archive",
    feed = "Readwise: Feed",
}

local MANAGED_COLLECTIONS = {
    ["Readwise: Inbox"] = true,
    ["Readwise: Later"] = true,
    ["Readwise: Shortlist"] = true,
    ["Readwise: Archive"] = true,
    ["Readwise: Feed"] = true,
    ["Readwise: Other"] = true,
}

-- Reader documents are installed from Trapper's child process. If SimpleUI or
-- KOReader's FileManager already has a directory item table cached, the file is
-- physically present (and searchable) but can remain absent from the visible
-- folder until a manual refresh/restart. Keep this best-effort and dependency
-- free: only touch UI modules that are already loaded in the parent process.
local function refreshFileBrowser()
    local simpleui_foldercovers = package.loaded["features/library/sui_foldercovers"]
    if type(simpleui_foldercovers) == "table"
        and type(simpleui_foldercovers.invalidateItemTableCache) == "function" then
        pcall(simpleui_foldercovers.invalidateItemTableCache)
    end

    local filemanager_module = package.loaded["apps/filemanager/filemanager"]
    local filemanager = type(filemanager_module) == "table"
        and filemanager_module.instance or nil
    local file_chooser = filemanager and filemanager.file_chooser or nil
    if file_chooser and type(file_chooser.refreshPath) == "function" then
        pcall(file_chooser.refreshPath, file_chooser)
    end

    return true
end

function Collections:new(options)
    options = options or {}
    return setmetatable({
        read_collection = options.read_collection or require("readcollection"),
    }, self)
end

function Collections:nameForLocation(location)
    return LOCATION_COLLECTIONS[location] or "Readwise: Other"
end

function Collections:syncLocation(filepath, location)
    assert(type(filepath) == "string" and filepath ~= "", "filepath is required")
    local rc = self.read_collection
    local target = self:nameForLocation(location)
    local updated = {}

    local ok, err = pcall(function()
        if not rc.coll[target] then
            rc:addCollection(target)
            updated[target] = true
        end
        for name in pairs(MANAGED_COLLECTIONS) do
            if name ~= target and rc.coll[name] and rc.coll[name][filepath] then
                rc:removeItem(filepath, name, true)
                updated[name] = true
            end
        end
        if not rc.coll[target][filepath] then
            rc:addItem(filepath, target)
            updated[target] = true
        end
        if next(updated) ~= nil then rc:write(updated) end
    end)
    if not ok then
        return nil, { kind = "collection", retryable = true, message = tostring(err) }
    end
    return true
end

function Collections:refresh()
    local ok, err = pcall(function() self.read_collection:_read() end)
    if not ok then return nil, tostring(err) end

    -- UI refresh is deliberately non-fatal. Collection persistence already
    -- succeeded; a third-party UI/cache refresh must never block the document
    -- watermark or turn a successful download into a failed sync.
    pcall(refreshFileBrowser)
    return true
end

Collections.LOCATION_COLLECTIONS = LOCATION_COLLECTIONS
Collections.MANAGED_COLLECTIONS = MANAGED_COLLECTIONS
Collections._refreshFileBrowser = refreshFileBrowser

return Collections
