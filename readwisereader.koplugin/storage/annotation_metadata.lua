-- SPDX-License-Identifier: AGPL-3.0-only

local Tags = require("metadata/tags")

local AnnotationMetadata = {}
AnnotationMetadata.__index = AnnotationMetadata

local function rowToItem(row)
    if not row then return nil end
    return {
        local_annotation_id = row[1],
        last_synced_tags = Tags.decode(row[2]),
        pending_tags = row[3] ~= nil and Tags.decode(row[3]) or nil,
        updated_at = row[4] and tonumber(row[4]) or nil,
    }
end

function AnnotationMetadata:new(options)
    options = options or {}
    return setmetatable({ db = assert(options.db, "db is required") }, self)
end

function AnnotationMetadata:getById(local_annotation_id)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        SELECT local_annotation_id, last_synced_tags_json, pending_tags_json, updated_at
        FROM annotation_metadata WHERE local_annotation_id = ?;
    ]])
    local row = stmt:bind(local_annotation_id):step()
    stmt:close()
    return rowToItem(row)
end

function AnnotationMetadata:setPendingTags(local_annotation_id, baseline, desired, updated_at)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        INSERT INTO annotation_metadata(
            local_annotation_id, last_synced_tags_json, pending_tags_json, updated_at
        ) VALUES (?, ?, ?, ?)
        ON CONFLICT(local_annotation_id) DO UPDATE SET
            last_synced_tags_json = excluded.last_synced_tags_json,
            pending_tags_json = excluded.pending_tags_json,
            updated_at = excluded.updated_at;
    ]])
    stmt:bind(
        local_annotation_id,
        Tags.encode(baseline),
        Tags.encode(desired),
        updated_at or os.time()
    ):step()
    stmt:close()
    return self:getById(local_annotation_id)
end

function AnnotationMetadata:markTagsSynced(local_annotation_id, tags, updated_at)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        INSERT INTO annotation_metadata(
            local_annotation_id, last_synced_tags_json, pending_tags_json, updated_at
        ) VALUES (?, ?, NULL, ?)
        ON CONFLICT(local_annotation_id) DO UPDATE SET
            last_synced_tags_json = excluded.last_synced_tags_json,
            pending_tags_json = NULL,
            updated_at = excluded.updated_at;
    ]])
    stmt:bind(local_annotation_id, Tags.encode(tags), updated_at or os.time()):step()
    stmt:close()
    return self:getById(local_annotation_id)
end

function AnnotationMetadata:clearPendingTags(local_annotation_id, updated_at)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE annotation_metadata SET pending_tags_json = NULL, updated_at = ?
        WHERE local_annotation_id = ?;
    ]])
    stmt:bind(updated_at or os.time(), local_annotation_id):step()
    stmt:close()
    return self:getById(local_annotation_id)
end

return AnnotationMetadata
