-- SPDX-License-Identifier: AGPL-3.0-only

local AnnotationSync = require("sync/annotations")

local function copy(row)
    if not row then return nil end
    local out = {}
    for key, value in pairs(row) do out[key] = value end
    return out
end

local function annotationRepo()
    local rows = {}
    return {
        rows = rows,
        getById = function(_, id)
            return copy(rows[id])
        end,
        listByDocument = function(_, reader_id)
            local result = {}
            for _, row in pairs(rows) do
                if row.reader_document_id == reader_id then
                    result[#result + 1] = copy(row)
                end
            end
            return result
        end,
        upsertLocal = function(_, link)
            local row = rows[link.local_annotation_id] or {
                local_annotation_id = link.local_annotation_id,
                reader_document_id = link.reader_document_id,
                created_remote = false,
            }
            row.reader_document_id = link.reader_document_id
            row.local_created_at = row.local_created_at or link.local_created_at
            row.locator_fingerprint = link.locator_fingerprint
            row.original_text_hash = row.original_text_hash or link.original_text_hash
            row.last_text_hash = link.last_text_hash
            row.last_note_hash = link.last_note_hash
            row.sync_state = link.sync_state
            row.last_sync_error = link.last_sync_error
            row.local_deleted_at = nil
            rows[link.local_annotation_id] = row
            return copy(row)
        end,
        markLocalDeleted = function(_, id, deleted_at)
            local row = rows[id]
            row.local_deleted_at = row.local_deleted_at or deleted_at
            row.sync_state = "local_deleted"
            return copy(row)
        end,
    }
end

local function documentRepo()
    local managed = {
        reader_id = "reader-1",
        local_path = "/Readwise/a.epub",
        is_managed = true,
        is_local_present = true,
    }
    return {
        getByLocalPath = function(_, path)
            if path == managed.local_path then return copy(managed) end
            return nil
        end,
    }
end

local function item(note_hash, text_hash)
    return {
        local_annotation_id = "ko-ann-1",
        locator_fingerprint = "loc-1",
        datetime = "2026-09-23 10:00:00",
        text = "Selected",
        note = "Note",
        text_hash = text_hash or "text-1",
        note_hash = note_hash or "note-1",
        page = "xp-1",
        pos0 = "xp-1",
        pos1 = "xp-2",
    }
end

return function()
    local annotations = annotationRepo()
    local scan_result = {
        authoritative = true,
        status = "ok",
        malformed = 0,
        annotations = { item() },
    }
    local adapter = {
        scan = function()
            return scan_result
        end,
    }
    local now = 100
    local syncer = AnnotationSync:new{
        documents = documentRepo(),
        annotations = annotations,
        adapter = adapter,
        now = function() return now end,
        file_exists = function() return true end,
    }

    local first, first_err = syncer:scanPath("/Readwise/a.epub")
    assert(first_err == nil)
    assert(first.highlights == 1)
    assert(first.notes == 1)
    assert(first.new == 1)
    assert(first.changed == 0)
    assert(first.deleted == 0)
    assert(first.sample.local_annotation_id == "ko-ann-1")
    assert(annotations.rows["ko-ann-1"].sync_state == "local_only")

    local second = assert(syncer:scanPath("/Readwise/a.epub"))
    assert(second.new == 0)
    assert(second.changed == 0)
    assert(second.unchanged == 1)

    scan_result = {
        authoritative = true,
        status = "ok",
        malformed = 0,
        annotations = { item("note-2", "text-1") },
    }
    local third = assert(syncer:scanPath("/Readwise/a.epub"))
    assert(third.changed == 1)
    assert(third.new == 0)
    assert(annotations.rows["ko-ann-1"].sync_state == "local_only",
        "unsynced annotation edits remain local_only")

    annotations.rows["ko-ann-1"].created_remote = true
    annotations.rows["ko-ann-1"].sync_state = "synced"
    scan_result = {
        authoritative = true,
        status = "ok",
        malformed = 0,
        annotations = { item("note-3", "text-1") },
    }
    local fourth = assert(syncer:scanPath("/Readwise/a.epub"))
    assert(fourth.changed == 1)
    assert(annotations.rows["ko-ann-1"].sync_state == "local_changed",
        "linked annotation edit must be detectable for a later remote-update phase")

    scan_result = {
        authoritative = false,
        status = "annotations_missing",
        malformed = 0,
        annotations = {},
    }
    local non_authoritative = assert(syncer:scanPath("/Readwise/a.epub"))
    assert(non_authoritative.authoritative == false)
    assert(annotations.rows["ko-ann-1"].local_deleted_at == nil,
        "missing/unreadable annotation table must never imply deletion")

    scan_result = {
        authoritative = true,
        status = "ok",
        malformed = 0,
        annotations = {},
    }
    now = 200
    local deleted = assert(syncer:scanPath("/Readwise/a.epub"))
    assert(deleted.deleted == 1)
    assert(annotations.rows["ko-ann-1"].local_deleted_at == 200)
    assert(annotations.rows["ko-ann-1"].sync_state == "local_deleted")

    now = 300
    local deleted_again = assert(syncer:scanPath("/Readwise/a.epub"))
    assert(deleted_again.deleted == 0)
    assert(annotations.rows["ko-ann-1"].local_deleted_at == 200,
        "repeated scans must not rewrite deletion time")

    scan_result = {
        authoritative = true,
        status = "ok",
        malformed = 0,
        annotations = { item("note-3", "text-1") },
    }
    local restored = assert(syncer:scanPath("/Readwise/a.epub"))
    assert(restored.changed == 1)
    assert(annotations.rows["ko-ann-1"].local_deleted_at == nil)
    assert(annotations.rows["ko-ann-1"].sync_state == "local_changed")

    local report, err = syncer:scanPath("/Books/unrelated.epub")
    assert(report == nil)
    assert(err.kind == "not_managed")

    do
        local degraded_repo = annotationRepo()
        local degraded_scan = {
            authoritative = true,
            status = "ok",
            malformed = 0,
            annotations = {
                {
                    local_annotation_id = "provisional-first",
                    locator_fingerprint = "same-locator",
                    identity_quality = "degraded",
                    datetime = nil,
                    text = "first text",
                    note = nil,
                    text_hash = "text-first",
                    note_hash = "note-none",
                },
            },
        }
        local degraded_sync = AnnotationSync:new{
            documents = documentRepo(),
            annotations = degraded_repo,
            adapter = { scan = function() return degraded_scan end },
            now = function() return 400 end,
            file_exists = function() return true end,
        }
        local initial = assert(degraded_sync:scanPath("/Readwise/a.epub"))
        assert(initial.new == 1)
        assert(initial.degraded_identity == 1)
        assert(degraded_repo.rows["provisional-first"].local_created_at == nil)

        degraded_scan = {
            authoritative = true,
            status = "ok",
            malformed = 0,
            annotations = {
                {
                    local_annotation_id = "provisional-after-text-edit",
                    locator_fingerprint = "same-locator",
                    identity_quality = "degraded",
                    datetime = nil,
                    text = "edited text",
                    note = nil,
                    text_hash = "text-edited",
                    note_hash = "note-none",
                },
            },
        }
        local edited_degraded = assert(degraded_sync:scanPath("/Readwise/a.epub"))
        assert(edited_degraded.new == 0)
        assert(edited_degraded.changed == 1)
        assert(degraded_repo.rows["provisional-first"] ~= nil)
        assert(degraded_repo.rows["provisional-after-text-edit"] == nil,
            "degraded identity must reuse the first-seen ID for one unambiguous locator")
        assert(degraded_repo.rows["provisional-first"].last_text_hash == "text-edited")
    end
end
