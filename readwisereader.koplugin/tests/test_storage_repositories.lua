-- SPDX-License-Identifier: AGPL-3.0-only

local Annotations = require("storage/annotations")
local DB = require("storage/db")
local Documents = require("storage/documents")
local Queue = require("storage/queue")
local SQ3 = require("tests.support.lsqlite3_compat")
local SyncMeta = require("storage/sync_meta")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function newDB()
    return DB:new{
        path = ":memory:",
        sq3 = SQ3,
        device = { canUseWAL = function() return false end },
    }
end

local function testDocuments()
    local db = newDB()
    local docs = Documents:new{ db = db }

    local first = docs:upsertRemote({
        id = "doc-1",
        category = "article",
        location = "new",
        title = "Old title",
        author = "Author",
        source_url = "https://example.invalid/article",
        updated_at = "2026-09-22T12:00:00Z",
        raw_source_available = false,
        raw_source_url = "https://secret.invalid/signed?token=must-not-persist",
    }, 100)
    assertEqual(first.title, "Old title")
    assertEqual(first.raw_source_available, false)
    assertEqual(docs:count(), 1)

    docs:setLocalState("doc-1", {
        local_path = "/mnt/us/documents/Readwise/Articles/old.html",
        local_format = "html",
        download_strategy = "reader_html",
        local_content_hash = "local-hash",
        is_local_present = true,
        last_materialized_at = 101,
        materialized_remote_updated_at = "2026-09-22T12:00:00Z",
        content_refresh_pending = false,
    })

    local second = docs:upsertRemote({
        id = "doc-1",
        category = "article",
        location = "later",
        title = "Renamed title",
        author = "Author",
        source_url = "https://example.invalid/article",
        updated_at = "2026-09-22T13:00:00Z",
        raw_source_available = true,
        raw_source_url = "https://secret.invalid/another-signed-url",
    }, 200)

    assertEqual(docs:count(), 1, "remote rename must not duplicate document")
    assertEqual(second.title, "Renamed title")
    assertEqual(second.location, "later")
    assertEqual(second.local_path, "/mnt/us/documents/Readwise/Articles/old.html", "remote metadata upsert must preserve local state")
    assertEqual(second.local_content_hash, "local-hash")
    assertEqual(second.raw_source_available, true)
    assertEqual(second.materialized_remote_updated_at, "2026-09-22T12:00:00Z")
    assertEqual(second.content_refresh_pending, false)

    local pending = docs:markContentRefreshPending(
        "doc-1",
        "2026-09-22T13:00:00Z",
        202
    )
    assertEqual(pending.content_refresh_pending, true)
    assertEqual(
        pending.content_refresh_remote_updated_at,
        "2026-09-22T13:00:00Z"
    )
    assertEqual(pending.content_refresh_detected_at, 202)
    assertEqual(docs:countContentRefreshPending(), 1)
    local pending_rows = docs:listContentRefreshPending()
    assertEqual(#pending_rows, 1)
    assertEqual(pending_rows[1].reader_id, "doc-1")

    local cleared = docs:clearContentRefreshPending("doc-1")
    assertEqual(cleared.content_refresh_pending, false)
    assertEqual(cleared.content_refresh_remote_updated_at, nil)
    assertEqual(cleared.content_refresh_detected_at, nil)
    assertEqual(docs:countContentRefreshPending(), 0)

    local by_path = docs:getByLocalPath("/mnt/us/documents/Readwise/Articles/old.html")
    assertEqual(by_path.reader_id, "doc-1")
    local archived = docs:setLocation("doc-1", "archive")
    assertEqual(archived.location, "archive")
    assertEqual(docs:getById("doc-1").location, "archive")
    assertEqual(docs:getByLocalPath("/mnt/us/documents/Readwise/Articles/missing.html"), nil)

    local local_managed = docs:listManagedLocal()
    assertEqual(#local_managed, 1)
    assertEqual(local_managed[1].reader_id, "doc-1")

    docs:upsertRemote({
        id = "doc-2",
        category = "article",
        location = "new",
        title = "Remote only",
        updated_at = "2026-09-22T13:30:00Z",
        raw_source_available = false,
    }, 201)
    assertEqual(#docs:listManaged(), 2)
    assertEqual(#docs:listManagedLocal(), 1,
        "annotation backlog query must not load remote-only documents")

    local conn = db:getConnection()
    local raw_url_count = tonumber(conn:rowexec([[
        SELECT count(*) FROM documents
        WHERE source_url LIKE '%secret.invalid%';
    ]])) or 0
    assertEqual(raw_url_count, 0, "raw_source_url must never be persisted")

    db:close()
end

local function testAnnotations()
    local db = newDB()
    local docs = Documents:new{ db = db }
    local anns = Annotations:new{ db = db }
    docs:upsertRemote({ id = "doc-1" }, 1)

    local first = anns:upsertLocal({
        local_annotation_id = "ann-1",
        reader_document_id = "doc-1",
        local_created_at = "2026-09-22 12:00:00",
        locator_fingerprint = "loc-a",
        original_text_hash = "text-original",
        last_text_hash = "text-1",
        last_note_hash = "note-1",
    })
    assertEqual(first.sync_state, "local_only")
    assertEqual(first.created_remote, false)

    anns:setReaderRemoteLink("ann-1", "reader-highlight-1", {
        text = "selected text",
        note = "[[Foucault]]",
        text_hash = "text-1",
        note_hash = "note-1",
    })
    anns:setReadwiseV2Id("ann-1", 12345)

    local linked = anns:getById("ann-1")
    assertEqual(linked.reader_highlight_document_id, "reader-highlight-1")
    assertEqual(linked.readwise_v2_highlight_id, 12345)
    assertEqual(linked.created_remote, true)
    assertEqual(linked.last_synced_note, "[[Foucault]]")
    assertEqual(
        anns:getByReaderRemoteId("reader-highlight-1").local_annotation_id,
        "ann-1",
        "remote Reader highlight id must resolve to its local annotation"
    )

    local imported = anns:linkImported({
        local_annotation_id = "ann-imported",
        reader_document_id = "doc-1",
        reader_highlight_document_id = "reader-highlight-imported",
        local_created_at = "2026-09-22 12:30:00",
        locator_fingerprint = "loc-imported",
        original_text_hash = "imported-text",
        last_text_hash = "imported-text",
        last_note_hash = "imported-note",
        text = "Imported text",
        note = "Imported note",
        remote_updated_marker = "2026-09-22T12:31:00Z",
    })
    assertEqual(imported.reader_highlight_document_id, "reader-highlight-imported")
    assertEqual(imported.created_remote, true)
    assertEqual(imported.sync_state, "synced")
    assertEqual(imported.last_synced_text, "Imported text")
    assertEqual(imported.last_synced_note, "Imported note")
    assertEqual(imported.remote_updated_marker, "2026-09-22T12:31:00Z")
    assertEqual(
        anns:getByReaderRemoteId("reader-highlight-imported").local_annotation_id,
        "ann-imported"
    )

    anns:upsertLocal({
        local_annotation_id = "ann-1",
        reader_document_id = "doc-1",
        locator_fingerprint = "loc-a",
        last_text_hash = "text-2",
        last_note_hash = "note-2",
        sync_state = "local_changed",
    })
    local edited = anns:getById("ann-1")
    assertEqual(edited.reader_highlight_document_id, "reader-highlight-1", "local scan must preserve remote link")
    assertEqual(edited.readwise_v2_highlight_id, 12345, "local scan must preserve v2 mapping")
    assertEqual(edited.last_text_hash, "text-2")
    assertEqual(edited.sync_state, "local_changed")

    local listed = anns:listByDocument("doc-1")
    assertEqual(#listed, 1)
    assertEqual(listed[1].local_annotation_id, "ann-1")

    local deleted = anns:markLocalDeleted("ann-1", 555)
    assertEqual(deleted.local_deleted_at, 555)
    assertEqual(deleted.sync_state, "local_deleted")

    anns:upsertLocal({
        local_annotation_id = "ann-1",
        reader_document_id = "doc-1",
        locator_fingerprint = "loc-a",
        last_text_hash = "text-2",
        last_note_hash = "note-2",
        sync_state = "local_changed",
    })
    local restored = anns:getById("ann-1")
    assertEqual(restored.local_deleted_at, nil, "seen annotation must clear local deletion tombstone")
    assertEqual(restored.reader_highlight_document_id, "reader-highlight-1", "local rescan must preserve remote link")

    local conflicted = anns:setSyncState("ann-1", "conflict", "note_conflict")
    assertEqual(conflicted.sync_state, "conflict")
    assertEqual(conflicted.last_sync_error, "note_conflict")

    local remote_deleted = anns:markRemoteDeleted("ann-1")
    assertEqual(remote_deleted.created_remote, false)
    assertEqual(remote_deleted.reader_highlight_document_id, nil)
    assertEqual(remote_deleted.readwise_v2_highlight_id, nil)
    assertEqual(remote_deleted.sync_state, "deleted_synced")

    db:close()
end

local function testQueue()
    local db = newDB()
    local queue = Queue:new{ db = db }

    local first = queue:enqueue({
        idempotency_key = "archive:doc-1",
        operation = "archive_document",
        entity_type = "document",
        reader_document_id = "doc-1",
        payload_json = "{}",
        payload_hash = "hash-1",
        created_at = 10,
    })
    local duplicate = queue:enqueue({
        idempotency_key = "archive:doc-1",
        operation = "archive_document",
        entity_type = "document",
        reader_document_id = "doc-1",
        payload_json = "{\"changed\":true}",
        payload_hash = "hash-2",
        created_at = 20,
    })
    assertEqual(first.id, duplicate.id, "duplicate idempotency key must return existing item")
    assertEqual(duplicate.payload_hash, "hash-1", "duplicate enqueue must not mutate original payload")
    assertEqual(queue:countByStatus("pending"), 1)

    local prepared = queue:prepare({
        idempotency_key = "create_highlight:ann-1",
        operation = "create_highlight",
        entity_type = "annotation",
        local_annotation_id = "ann-1",
        reader_document_id = "doc-1",
        payload_json = "{\"v\":1}",
        payload_hash = "create-hash-1",
        created_at = 20,
    })
    assertEqual(prepared.status, "pending")
    prepared = queue:prepare({
        idempotency_key = "create_highlight:ann-1",
        operation = "create_highlight",
        entity_type = "annotation",
        local_annotation_id = "ann-1",
        reader_document_id = "doc-1",
        payload_json = "{\"v\":2}",
        payload_hash = "create-hash-2",
        created_at = 21,
        updated_at = 21,
    })
    assertEqual(prepared.payload_hash, "create-hash-2", "never-attempted payload may refresh")

    local in_flight = queue:markInFlight("create_highlight:ann-1", 22)
    assertEqual(in_flight.status, "in_flight")
    assertEqual(in_flight.attempts, 1)
    queue:recoverStaleInFlight(30)
    local stale = queue:getByKey("create_highlight:ann-1")
    assertEqual(stale.status, "blocked", "stale create must never become a blind retry")
    assertEqual(stale.last_error_kind, "stale_create_in_flight")

    local generic = queue:enqueue({
        idempotency_key = "archive:doc-2",
        operation = "archive_document",
        entity_type = "document",
        reader_document_id = "doc-2",
        payload_json = "{}",
        payload_hash = "hash-generic",
        created_at = 40,
    })
    conn = db:getConnection()
    conn:exec("UPDATE queue SET status='in_flight' WHERE id=" .. tostring(generic.id) .. ";")
    queue:recoverStaleInFlight(41)
    assertEqual(queue:getByKey("archive:doc-2").status, "pending")

    local archive_item = queue:prepareArchive({
        idempotency_key = "archive_document:doc-3",
        operation = "archive_document",
        entity_type = "document",
        reader_document_id = "doc-3",
        payload_json = "{\"location\":\"archive\"}",
        payload_hash = "archive-hash-1",
        created_at = 42,
        updated_at = 42,
    }, false)
    assertEqual(archive_item.status, "pending")
    assertEqual(queue:countArchiveWaiting(), 3)
    local archive_work = queue:listArchiveWork(42)
    assertEqual(#archive_work, 3)

    local cancelled = queue:markCancelled(
        "archive_document:doc-3",
        "local no longer finished",
        43
    )
    assertEqual(cancelled.status, "cancelled")
    assertEqual(cancelled.attempts, 0)
    assertEqual(queue:countArchiveWaiting(), 2)

    local reopened = queue:prepareArchive({
        idempotency_key = "archive_document:doc-3",
        operation = "archive_document",
        entity_type = "document",
        reader_document_id = "doc-3",
        payload_json = "{\"location\":\"archive\",\"again\":true}",
        payload_hash = "archive-hash-2",
        created_at = 44,
        updated_at = 44,
    }, false)
    assertEqual(reopened.status, "pending")
    assertEqual(reopened.payload_hash, "archive-hash-2")
    assertEqual(queue:countArchiveWaiting(), 3)

    local blocked = queue:markBlocked(
        "create_highlight:ann-1",
        "create_timeout",
        "unknown outcome",
        50
    )
    assertEqual(blocked.status, "blocked")

    local auth_pending = queue:markPendingError(
        "create_highlight:ann-1",
        "preflight_auth",
        "token rejected before POST",
        51
    )
    assertEqual(auth_pending.status, "pending")
    assertEqual(auth_pending.attempts, 1, "queue error state must not invent a new attempt")

    local waiting = queue:markRetryWait(
        "create_highlight:ann-1",
        "preflight_rate_limit",
        "retry later",
        100,
        52
    )
    assertEqual(waiting.status, "retry_wait")
    assertEqual(waiting.available_after, 100)
    assertEqual(#queue:listCreateWork(99), 0, "retry_wait item must not run early")
    local due = queue:listCreateWork(100)
    assertEqual(#due, 1)
    assertEqual(due[1].status, "pending")
    assertEqual(due[1].available_after, nil)
    assertEqual(queue:countCreateWaiting(), 1)

    local succeeded = queue:markSucceeded("create_highlight:ann-1", "remote-1", 60)
    assertEqual(succeeded.status, "succeeded")
    assertEqual(succeeded.reader_highlight_document_id, "remote-1")

    queue:prepare({
        idempotency_key = "create_highlight:ann-2",
        operation = "create_highlight",
        entity_type = "annotation",
        local_annotation_id = "ann-2",
        reader_document_id = "doc-2",
        payload_json = "{\"content\":\"two\"}",
        payload_hash = "create-hash-2",
        created_at = 70,
        updated_at = 70,
    })
    local diagnostics = queue:listCreateDiagnostics(10)
    assertEqual(#diagnostics, 2)
    assertEqual(diagnostics[1].local_annotation_id, "ann-2",
        "diagnostic rows must be newest-first without mutating queue state")
    local counts = queue:countCreateStatuses()
    assertEqual(counts.pending, 1)
    assertEqual(counts.succeeded, 1)
    assertEqual(queue:getByKey("create_highlight:ann-2").status, "pending",
        "read-only diagnostics must not promote or mutate queue rows")

    db:close()
end


local function testQueuePersistsAcrossRestart()
    local path = os.tmpname()
    os.remove(path)

    local function openFileDB()
        return DB:new{
            path = path,
            sq3 = SQ3,
            device = { canUseWAL = function() return false end },
            copy_file = function() return nil end,
        }
    end

    local first_db = openFileDB()
    local first_queue = Queue:new{ db = first_db }
    first_queue:enqueue({
        idempotency_key = "create_highlight:restart-ann",
        operation = "create_highlight",
        entity_type = "annotation",
        local_annotation_id = "restart-ann",
        reader_document_id = "restart-doc",
        payload_json = "{\"content\":\"durable\"}",
        payload_hash = "restart-hash",
        created_at = 100,
    })
    first_queue:markInFlight("create_highlight:restart-ann", 101)
    first_db:close()

    -- Simulate a KOReader/process restart: construct a fresh DB/repository
    -- against the same durable SQLite file, then run startup recovery.
    local second_db = openFileDB()
    local second_queue = Queue:new{ db = second_db }
    local before = second_queue:getByKey("create_highlight:restart-ann")
    assertEqual(before.status, "in_flight")
    assertEqual(before.attempts, 1)
    assertEqual(before.payload_hash, "restart-hash")
    second_queue:recoverStaleInFlight(200)
    local recovered = second_queue:getByKey("create_highlight:restart-ann")
    assertEqual(recovered.status, "blocked",
        "restart recovery must not blindly retry an ambiguous create")
    assertEqual(recovered.last_error_kind, "stale_create_in_flight")
    assertEqual(recovered.attempts, 1,
        "restart recovery must preserve the durable attempt count")
    assertEqual(recovered.payload_json, "{\"content\":\"durable\"}",
        "restart recovery must preserve the durable payload")
    second_db:close()

    os.remove(path)
    os.remove(path .. ".bak")
end


local function testSyncMeta()
    local db = newDB()
    local meta = SyncMeta:new{ db = db }

    assertEqual(meta:get("document_watermark"), nil)
    meta:set("document_watermark", "2026-09-22T12:00:00Z")
    assertEqual(meta:get("document_watermark"), "2026-09-22T12:00:00Z")
    meta:set("document_watermark", "2026-09-22T13:00:00Z")
    assertEqual(meta:get("document_watermark"), "2026-09-22T13:00:00Z")
    meta:setMany({
        document_watermark = "2026-09-22T14:00:00Z",
        document_query_after = "2026-09-22T13:55:00Z",
        last_successful_sync_at = "2026-09-22T14:01:00Z",
    })
    assertEqual(meta:get("document_watermark"), "2026-09-22T14:00:00Z")
    assertEqual(meta:get("document_query_after"), "2026-09-22T13:55:00Z")
    assertEqual(meta:get("last_successful_sync_at"), "2026-09-22T14:01:00Z")
    meta:delete("document_watermark")
    assertEqual(meta:get("document_watermark"), nil)

    db:close()
end

return function()
    testDocuments()
    testAnnotations()
    testQueue()
    testQueuePersistsAcrossRestart()
    testSyncMeta()
end
