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

-- Refresh a never-attempted create with the latest literal local note/text.
-- Once an attempt has started, its durable payload is immutable: changing it
-- would make timeout reconciliation ambiguous.
function Queue:prepare(item)
    local existing = self:enqueue(item)
    if existing.status == "pending" and existing.attempts == 0 then
        local conn = self.db:getConnection()
        local stmt = conn:prepare([[
            UPDATE queue SET
                payload_json = ?,
                payload_hash = ?,
                updated_at = ?
            WHERE idempotency_key = ?
              AND status = 'pending'
              AND attempts = 0;
        ]])
        stmt:bind(
            item.payload_json,
            item.payload_hash,
            item.updated_at or item.created_at,
            item.idempotency_key
        ):step()
        stmt:close()
    end
    return self:getByKey(item.idempotency_key)
end

-- Archive operations are idempotent state assignments, so a never-attempted
-- cancelled row may be reopened. A previously-succeeded row may also be
-- reopened only when the caller has fresh evidence that Reader is no longer
-- archived while the local canonical status is still Finished.
function Queue:prepareArchive(item, reopen_succeeded)
    local existing = self:enqueue(item)
    local reusable = existing
        and existing.attempts == 0
        and (
            existing.status == "pending"
            or existing.status == "cancelled"
            or (reopen_succeeded == true and existing.status == "succeeded")
        )
    if reusable then
        local conn = self.db:getConnection()
        local stmt = conn:prepare([[
            UPDATE queue SET
                payload_json = ?,
                payload_hash = ?,
                status = 'pending',
                attempts = 0,
                available_after = NULL,
                last_attempt_at = NULL,
                last_error_kind = NULL,
                last_error_message = NULL,
                updated_at = ?
            WHERE idempotency_key = ?
              AND attempts = 0;
        ]])
        stmt:bind(
            item.payload_json,
            item.payload_hash,
            item.updated_at or item.created_at,
            item.idempotency_key
        ):step()
        stmt:close()
    end
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

function Queue:markInFlight(idempotency_key, attempted_at)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE queue SET
            status = 'in_flight',
            attempts = attempts + 1,
            last_attempt_at = ?,
            last_error_kind = NULL,
            last_error_message = NULL,
            updated_at = ?
        WHERE idempotency_key = ?
          AND status = 'pending';
    ]])
    stmt:bind(attempted_at, attempted_at, idempotency_key):step()
    stmt:close()
    return self:getByKey(idempotency_key)
end

function Queue:markSucceeded(idempotency_key, remote_id, updated_at)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE queue SET
            status = 'succeeded',
            reader_highlight_document_id = COALESCE(?, reader_highlight_document_id),
            available_after = NULL,
            last_error_kind = NULL,
            last_error_message = NULL,
            updated_at = ?
        WHERE idempotency_key = ?;
    ]])
    stmt:bind(remote_id, updated_at, idempotency_key):step()
    stmt:close()
    return self:getByKey(idempotency_key)
end

function Queue:markCancelled(idempotency_key, reason, updated_at)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE queue SET
            status = 'cancelled',
            available_after = NULL,
            last_error_kind = 'cancelled',
            last_error_message = ?,
            updated_at = ?
        WHERE idempotency_key = ?
          AND attempts = 0;
    ]])
    stmt:bind(reason, updated_at, idempotency_key):step()
    stmt:close()
    return self:getByKey(idempotency_key)
end

function Queue:markBlocked(idempotency_key, error_kind, error_message, updated_at)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE queue SET
            status = 'blocked',
            available_after = NULL,
            last_error_kind = ?,
            last_error_message = ?,
            updated_at = ?
        WHERE idempotency_key = ?;
    ]])
    stmt:bind(error_kind, error_message, updated_at, idempotency_key):step()
    stmt:close()
    return self:getByKey(idempotency_key)
end

function Queue:markPendingError(idempotency_key, error_kind, error_message, updated_at)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE queue SET
            status = 'pending',
            available_after = NULL,
            last_error_kind = ?,
            last_error_message = ?,
            updated_at = ?
        WHERE idempotency_key = ?;
    ]])
    stmt:bind(error_kind, error_message, updated_at, idempotency_key):step()
    stmt:close()
    return self:getByKey(idempotency_key)
end

function Queue:markRetryWait(idempotency_key, error_kind, error_message, available_after, updated_at)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE queue SET
            status = 'retry_wait',
            available_after = ?,
            last_error_kind = ?,
            last_error_message = ?,
            updated_at = ?
        WHERE idempotency_key = ?;
    ]])
    stmt:bind(
        available_after,
        error_kind,
        error_message,
        updated_at,
        idempotency_key
    ):step()
    stmt:close()
    return self:getByKey(idempotency_key)
end

function Queue:promoteAvailable(now)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE queue SET
            status = 'pending',
            available_after = NULL,
            updated_at = ?
        WHERE status = 'retry_wait'
          AND (available_after IS NULL OR available_after <= ?);
    ]])
    stmt:bind(now, now):step()
    stmt:close()
end

function Queue:listCreateWork(now)
    self:promoteAvailable(now)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        SELECT
            id, idempotency_key, operation, entity_type, local_annotation_id,
            reader_document_id, reader_highlight_document_id,
            readwise_v2_highlight_id, payload_json, payload_hash, status,
            attempts, available_after, last_attempt_at, last_error_kind,
            last_error_message, created_at, updated_at
        FROM queue
        WHERE operation = 'create_highlight'
          AND status IN ('pending', 'in_flight', 'blocked')
        ORDER BY id;
    ]])
    local items = {}
    while true do
        local row = stmt:step()
        if not row then break end
        items[#items + 1] = rowToItem(row)
    end
    stmt:close()
    return items
end

function Queue:listArchiveWork(now)
    self:promoteAvailable(now)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        SELECT
            id, idempotency_key, operation, entity_type, local_annotation_id,
            reader_document_id, reader_highlight_document_id,
            readwise_v2_highlight_id, payload_json, payload_hash, status,
            attempts, available_after, last_attempt_at, last_error_kind,
            last_error_message, created_at, updated_at
        FROM queue
        WHERE operation = 'archive_document'
          AND status IN ('pending', 'in_flight')
        ORDER BY id;
    ]])
    local items = {}
    while true do
        local row = stmt:step()
        if not row then break end
        items[#items + 1] = rowToItem(row)
    end
    stmt:close()
    return items
end

function Queue:countArchiveWaiting()
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        SELECT count(*) FROM queue
        WHERE operation = 'archive_document'
          AND status IN ('pending', 'retry_wait', 'in_flight', 'blocked');
    ]])
    local row = stmt:step()
    stmt:close()
    return row and (tonumber(row[1]) or 0) or 0
end

function Queue:listCreateDiagnostics(limit)
    limit = math.max(1, math.min(tonumber(limit) or 10, 50))
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        SELECT
            id, idempotency_key, operation, entity_type, local_annotation_id,
            reader_document_id, reader_highlight_document_id,
            readwise_v2_highlight_id, payload_json, payload_hash, status,
            attempts, available_after, last_attempt_at, last_error_kind,
            last_error_message, created_at, updated_at
        FROM queue
        WHERE operation = 'create_highlight'
        ORDER BY updated_at DESC, id DESC
        LIMIT ?;
    ]])
    stmt:bind(limit)
    local items = {}
    while true do
        local row = stmt:step()
        if not row then break end
        items[#items + 1] = rowToItem(row)
    end
    stmt:close()
    return items
end

function Queue:countCreateStatuses()
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        SELECT status, count(*)
        FROM queue
        WHERE operation = 'create_highlight'
        GROUP BY status;
    ]])
    local counts = {}
    while true do
        local row = stmt:step()
        if not row then break end
        counts[tostring(row[1])] = tonumber(row[2]) or 0
    end
    stmt:close()
    return counts
end

function Queue:countCreateWaiting()
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        SELECT count(*) FROM queue
        WHERE operation = 'create_highlight'
          AND status IN ('pending', 'retry_wait', 'in_flight', 'blocked');
    ]])
    local row = stmt:step()
    stmt:close()
    return row and (tonumber(row[1]) or 0) or 0
end

function Queue:countByStatus(status)
    local conn = self.db:getConnection()
    local stmt = conn:prepare("SELECT count(*) FROM queue WHERE status = ?;")
    local row = stmt:bind(status):step()
    stmt:close()
    return row and (tonumber(row[1]) or 0) or 0
end

-- A stale create may have reached Reader even if the child process died before
-- persisting the response. Never turn that operation back into a blind retry.
-- Other operation types retain the older generic pending recovery semantics.
function Queue:recoverStaleInFlight(updated_at)
    local conn = self.db:getConnection()

    local creates = conn:prepare([[
        UPDATE queue SET
            status = 'blocked',
            last_error_kind = 'stale_create_in_flight',
            last_error_message = 'Create outcome is unknown; reconcile before retry.',
            updated_at = ?
        WHERE status = 'in_flight'
          AND operation = 'create_highlight';
    ]])
    creates:bind(updated_at):step()
    creates:close()

    local others = conn:prepare([[
        UPDATE queue SET
            status = 'pending',
            updated_at = ?
        WHERE status = 'in_flight'
          AND operation <> 'create_highlight';
    ]])
    others:bind(updated_at):step()
    others:close()
end

Queue._rowToItem = rowToItem

return Queue
