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
    local by_path = docs:getByLocalPath("/mnt/us/documents/Readwise/Articles/old.html")
    assertEqual(by_path.reader_id, "doc-1")
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

    db:close()
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
    testSyncMeta()
end
