-- SPDX-License-Identifier: AGPL-3.0-only

local Annotations = {}
Annotations.__index = Annotations

local function rowToLink(row)
    if not row then
        return nil
    end
    return {
        local_annotation_id = row[1],
        reader_document_id = row[2],
        reader_highlight_document_id = row[3],
        readwise_v2_highlight_id = row[4] and tonumber(row[4]) or nil,
        created_remote = tonumber(row[5]) == 1,
        local_created_at = row[6],
        locator_fingerprint = row[7],
        original_text_hash = row[8],
        last_text_hash = row[9],
        last_note_hash = row[10],
        last_synced_text = row[11],
        last_synced_note = row[12],
        remote_updated_marker = row[13],
        local_deleted_at = row[14],
        sync_state = row[15],
        last_sync_error = row[16],
    }
end

function Annotations:new(options)
    options = options or {}
    return setmetatable({
        db = assert(options.db, "db is required"),
    }, self)
end

function Annotations:upsertLocal(link)
    assert(type(link) == "table", "link is required")
    assert(type(link.local_annotation_id) == "string" and link.local_annotation_id ~= "", "local_annotation_id is required")
    assert(type(link.reader_document_id) == "string" and link.reader_document_id ~= "", "reader_document_id is required")
    assert(type(link.locator_fingerprint) == "string" and link.locator_fingerprint ~= "", "locator_fingerprint is required")

    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        INSERT INTO annotation_links(
            local_annotation_id, reader_document_id, local_created_at,
            locator_fingerprint, original_text_hash, last_text_hash,
            last_note_hash, sync_state, last_sync_error
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(local_annotation_id) DO UPDATE SET
            reader_document_id = excluded.reader_document_id,
            locator_fingerprint = excluded.locator_fingerprint,
            last_text_hash = excluded.last_text_hash,
            last_note_hash = excluded.last_note_hash,
            local_deleted_at = NULL,
            sync_state = excluded.sync_state,
            last_sync_error = excluded.last_sync_error;
    ]])
    stmt:bind(
        link.local_annotation_id,
        link.reader_document_id,
        link.local_created_at,
        link.locator_fingerprint,
        link.original_text_hash,
        link.last_text_hash,
        link.last_note_hash,
        link.sync_state or "local_only",
        link.last_sync_error
    ):step()
    stmt:close()
    return self:getById(link.local_annotation_id)
end

function Annotations:getById(local_annotation_id)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        SELECT
            local_annotation_id, reader_document_id, reader_highlight_document_id,
            readwise_v2_highlight_id, created_remote, local_created_at,
            locator_fingerprint, original_text_hash, last_text_hash, last_note_hash,
            last_synced_text, last_synced_note, remote_updated_marker,
            local_deleted_at, sync_state, last_sync_error
        FROM annotation_links
        WHERE local_annotation_id = ?;
    ]])
    local row = stmt:bind(local_annotation_id):step()
    stmt:close()
    return rowToLink(row)
end

function Annotations:listByDocument(reader_document_id)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        SELECT
            local_annotation_id, reader_document_id, reader_highlight_document_id,
            readwise_v2_highlight_id, created_remote, local_created_at,
            locator_fingerprint, original_text_hash, last_text_hash, last_note_hash,
            last_synced_text, last_synced_note, remote_updated_marker,
            local_deleted_at, sync_state, last_sync_error
        FROM annotation_links
        WHERE reader_document_id = ?
        ORDER BY local_annotation_id;
    ]])
    local result = {}
    stmt:bind(reader_document_id)
    while true do
        local row = stmt:step()
        if not row then break end
        result[#result + 1] = rowToLink(row)
    end
    stmt:close()
    return result
end

function Annotations:markLocalDeleted(local_annotation_id, deleted_at)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE annotation_links SET
            local_deleted_at = COALESCE(local_deleted_at, ?),
            sync_state = 'local_deleted',
            last_sync_error = NULL
        WHERE local_annotation_id = ?;
    ]])
    stmt:bind(deleted_at, local_annotation_id):step()
    stmt:close()
    return self:getById(local_annotation_id)
end

function Annotations:setReaderRemoteLink(local_annotation_id, reader_highlight_document_id, synced)
    synced = synced or {}
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE annotation_links SET
            reader_highlight_document_id = ?,
            created_remote = 1,
            last_synced_text = ?,
            last_synced_note = ?,
            last_text_hash = ?,
            last_note_hash = ?,
            sync_state = ?,
            last_sync_error = NULL
        WHERE local_annotation_id = ?;
    ]])
    stmt:bind(
        reader_highlight_document_id,
        synced.text,
        synced.note,
        synced.text_hash,
        synced.note_hash,
        synced.sync_state or "synced",
        local_annotation_id
    ):step()
    stmt:close()
end

function Annotations:setReadwiseV2Id(local_annotation_id, readwise_v2_highlight_id)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE annotation_links
        SET readwise_v2_highlight_id = ?
        WHERE local_annotation_id = ?;
    ]])
    stmt:bind(readwise_v2_highlight_id, local_annotation_id):step()
    stmt:close()
end

return Annotations
