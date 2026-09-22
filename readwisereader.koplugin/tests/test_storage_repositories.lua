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

    local conn = db:getConnection()
    conn:exec("UPDATE queue SET status='in_flight' WHERE id=" .. tostring(first.id) .. ";")
    assertEqual(queue:countByStatus("in_flight"), 1)
    queue:recoverStaleInFlight(30)
    assertEqual(queue:countByStatus("in_flight"), 0)
    assertEqual(queue:countByStatus("pending"), 1)

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
