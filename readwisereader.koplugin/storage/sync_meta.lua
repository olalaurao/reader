-- SPDX-License-Identifier: AGPL-3.0-only

local SyncMeta = {}
SyncMeta.__index = SyncMeta

function SyncMeta:new(options)
    options = options or {}
    return setmetatable({
        db = assert(options.db, "db is required"),
    }, self)
end

function SyncMeta:get(key)
    local conn = self.db:getConnection()
    local stmt = conn:prepare("SELECT value FROM sync_meta WHERE key = ?;")
    local row = stmt:bind(key):step()
    stmt:close()
    return row and row[1] or nil
end

function SyncMeta:set(key, value)
    assert(type(key) == "string" and key ~= "", "key is required")
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        INSERT INTO sync_meta(key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
    ]])
    stmt:bind(key, value):step()
    stmt:close()
end

function SyncMeta:delete(key)
    local conn = self.db:getConnection()
    local stmt = conn:prepare("DELETE FROM sync_meta WHERE key = ?;")
    stmt:bind(key):step()
    stmt:close()
end

return SyncMeta
