-- SPDX-License-Identifier: AGPL-3.0-only

local Collections = {}
Collections.__index = Collections

local LOCATION_COLLECTIONS = {
    new = "Readwise: Inbox",
    later = "Readwise: Later",
    archive = "Readwise: Archive",
    feed = "Readwise: Feed",
}

local MANAGED_COLLECTIONS = {
    ["Readwise: Inbox"] = true,
    ["Readwise: Later"] = true,
    ["Readwise: Archive"] = true,
    ["Readwise: Feed"] = true,
    ["Readwise: Other"] = true,
}

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
    return true
end

Collections.LOCATION_COLLECTIONS = LOCATION_COLLECTIONS
Collections.MANAGED_COLLECTIONS = MANAGED_COLLECTIONS

return Collections
