-- SPDX-License-Identifier: AGPL-3.0-only

local Queue = {}
Queue.__index = Queue

local function rowToItem(row)
    if not row then
        return nil
    end
    return {
        id = tonumber(row[1]),
        idempotency_key = row[2],
        operation = row[3],
        entity_type = row[4],
        local_annotation_id = row[5],
        reader_document_id = row[6],
        reader_highlight_document_id = row[7],
        readwise_v2_highlight_id = row[8] and tonumber(row[8]) or nil,
        payload_json = row[9],
        payload_hash = row[10],
        status = row[11],
        attempts = tonumber(row[12]) or 0,
        available_after = row[13],
        last_attempt_at = row[14],
        last_error_kind = row[15],
        last_error_message = row[16],
        created_at = row[17],
        updated_at = row[18],
    }
end

function Queue:new(options)
    options = options or {}
    return setmetatable({
        db = assert(options.db, "db is required"),
    }, self)
end

function Queue:enqueue(item)
    assert(type(item) == "table", "queue item is required")
    assert(type(item.idempotency_key) == "string" and item.idempotency_key ~= "", "idempotency_key is required")
    assert(type(item.operation) == "string" and item.operation ~= "", "operation is required")
    assert(type(item.entity_type) == "string" and item.entity_type ~= "", "entity_type is required")
    assert(type(item.payload_json) == "string", "payload_json is required")
    assert(type(item.payload_hash) == "string" and item.payload_hash ~= "", "payload_hash is required")
    assert(item.created_at ~= nil, "created_at is required")

    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        INSERT OR IGNORE INTO queue(
            idempotency_key, operation, entity_type, local_annotation_id,
            reader_document_id, reader_highlight_document_id,
            readwise_v2_highlight_id, payload_json, payload_hash, status,
            attempts, available_after, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ]])
    stmt:bind(
        item.idempotency_key,
        item.operation,
        item.entity_type,
        item.local_annotation_id,
        item.reader_document_id,
        item.reader_highlight_document_id,
        item.readwise_v2_highlight_id,
        item.payload_json,
        item.payload_hash,
        item.status or "pending",
        item.attempts or 0,
        item.available_after,
        item.created_at,
        item.updated_at or item.created_at
    ):step()
    stmt:close()
    return self:getByKey(item.idempotency_key)
end

function Queue:getByKey(idempotency_key)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        SELECT
            id, idempotency_key, operation, entity_type, local_annotation_id,
            reader_document_id, reader_highlight_document_id,
            readwise_v2_highlight_id, payload_json, payload_hash, status,
            attempts, available_after, last_attempt_at, last_error_kind,
            last_error_message, created_at, updated_at
        FROM queue WHERE idempotency_key = ?;
    ]])
    local row = stmt:bind(idempotency_key):step()
    stmt:close()
    return rowToItem(row)
end

function Queue:recoverStaleInFlight(updated_at)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE queue
        SET status = 'pending',
            updated_at = ?
        WHERE status = 'in_flight';
    ]])
    stmt:bind(updated_at):step()
    stmt:close()
end

function Queue:countByStatus(status)
    local conn = self.db:getConnection()
    local stmt = conn:prepare("SELECT count(*) FROM queue WHERE status = ?;")
    local row = stmt:bind(status):step()
    stmt:close()
    return row and (tonumber(row[1]) or 0) or 0
end

Queue._rowToItem = rowToItem

return Queue
