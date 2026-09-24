-- SPDX-License-Identifier: AGPL-3.0-only

local Mutations = require("sync/annotation_mutations")
local Identity = require("sync/annotation_identity")

local function copy(value)
    if not value then return nil end
    local out = {}
    for k, v in pairs(value) do out[k] = v end
    return out
end

local function baseState()
    return {
        row = {
            local_annotation_id = "ann-1",
            reader_document_id = "doc-1",
            reader_highlight_document_id = "remote-1",
            created_remote = true,
            locator_fingerprint = "loc-1",
            last_synced_text = "Selected text",
            last_synced_note = "old note",
            last_text_hash = "th",
            last_note_hash = "old-hash",
            sync_state = "local_changed",
            local_deleted_at = nil,
        },
        updates = 0,
        deletes = 0,
        v2_updates = 0,
        v2_lists = 0,
        v3_updates = 0,
        reader_gets = 0,
        auto_propagate_v2 = true,
        v2_deleted = false,
    }
end

local function candidate(note)
    return {
        local_annotation_id = "ann-1",
        locator_fingerprint = "loc-1",
        text = "Selected text",
        note = note,
        text_hash = "th",
        note_hash = "hash:" .. tostring(note),
    }
end

local function repos(state)
    local annotations = {
        getById = function(_, id)
            if id == "ann-1" then return copy(state.row) end
        end,
        listByDocument = function(_, id)
            if id == "doc-1" then return { copy(state.row) } end
            return {}
        end,
        setReaderRemoteLink = function(_, id, remote_id, synced)
            assert(id == "ann-1")
            state.row.reader_highlight_document_id = remote_id
            state.row.created_remote = true
            state.row.last_synced_text = synced.text
            state.row.last_synced_note = synced.note
            state.row.last_text_hash = synced.text_hash
            state.row.last_note_hash = synced.note_hash
            state.row.sync_state = synced.sync_state
            state.row.last_sync_error = nil
        end,
        setSyncState = function(_, id, sync_state, last_error)
            assert(id == "ann-1")
            state.row.sync_state = sync_state
            state.row.last_sync_error = last_error
            return copy(state.row)
        end,
        markRemoteDeleted = function(_, id)
            assert(id == "ann-1")
            state.row.reader_highlight_document_id = nil
            state.row.created_remote = false
            state.row.sync_state = "deleted_synced"
            state.row.last_sync_error = nil
            return copy(state.row)
        end,
        setReadwiseV2Id = function(_, id, v2_id)
            assert(id == "ann-1")
            state.row.readwise_v2_highlight_id = v2_id
        end,
    }
    local documents = {
        getByLocalPath = function(_, path)
            if path == "/Readwise/a.html" then
                return {
                    reader_id = "doc-1",
                    local_path = path,
                    is_managed = true,
                    is_local_present = true,
                }
            end
        end,
    }
    return documents, annotations
end

local function child(note, source)
    return {
        id = "remote-1",
        parent_id = "doc-1",
        category = "highlight",
        source = source or Identity.markerFor("ann-1"),
        notes = note,
    }
end

local function newMutator(state, local_note, remote_note, propagate, source)
    local documents, annotations = repos(state)
    local remote = child("unreliable-v3-note", source)
    local v2 = {
        id = 77,
        external_id = "remote-1",
        note = remote_note,
    }
    local reader = {
        getDocument = function()
            state.reader_gets = state.reader_gets + 1
            if remote == nil then
                return nil, { kind = "not_found", retryable = false }
            end
            return copy(remote)
        end,
        updateDocument = function(_, id, patch)
            assert(id == "remote-1")
            state.v3_updates = state.v3_updates + 1
            remote.notes = patch.notes
            return { id = id }
        end,
        deleteDocument = function(_, id)
            assert(id == "remote-1")
            state.deletes = state.deletes + 1
            remote = nil
            state.v2_deleted = true
            return true
        end,
    }
    local readwise = {
        listHighlights = function(_, options)
            state.v2_lists = state.v2_lists + 1
            assert(options.page_size == 1000)
            assert(options.page == 1)
            if state.v2_deleted then
                return { count = 0, results = {} }
            end
            return {
                count = 1,
                results = { copy(v2) },
            }
        end,
        getHighlight = function(_, id)
            assert(id == 77)
            if state.v2_deleted then
                return nil, { kind = "not_found", retryable = false }
            end
            return copy(v2)
        end,
        updateHighlight = function(_, id, patch)
            assert(id == 77)
            state.v2_updates = state.v2_updates + 1
            v2.note = patch.note
            if state.auto_propagate_v2 then
                remote.notes = patch.note
            end
            return copy(v2)
        end,
    }
    return Mutations:new{
        documents = documents,
        annotations = annotations,
        adapter = {
            scan = function()
                return {
                    authoritative = true,
                    status = "ok",
                    annotations = local_note == false and {} or { candidate(local_note) },
                }
            end,
        },
        reader = reader,
        readwise = readwise,
        propagate_deletions = propagate == true,
        sleep = function() end,
        reader_verify_attempts = 2,
        reader_verify_delay = 0,
        file_exists = function() return true end,
    }
end

local function updateCase()
    local state = baseState()
    local mutator = newMutator(state, "new [[Foucault]]", "old note", false)
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.notes_updated == 1)
    assert(report.conflicts == 0)
    assert(state.v2_updates == 1)
    assert(state.v2_lists == 1)
    assert(state.row.readwise_v2_highlight_id == 77)
    assert(state.row.last_synced_note == "new [[Foucault]]")
    assert(state.row.sync_state == "synced")
end

local function legacyUpdateCase()
    local state = baseState()
    local mutator = newMutator(
        state,
        "legacy updated [[Foucault]]",
        "old note",
        false,
        "KOReader Readwise Reader"
    )
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.notes_updated == 1)
    assert(report.conflicts == 0)
    assert(report.blocked == 0)
    assert(report.remote_errors == 0)
    assert(report.legacy_identity_accepted >= 1)
    assert(state.v2_updates == 1)
    assert(state.row.last_synced_note == "legacy updated [[Foucault]]")
end

local function missingMarkerUpdateCase()
    local state = baseState()
    state.row.sync_state = "blocked"
    state.row.last_sync_error = "remote_identity"
    local mutator = newMutator(
        state,
        "retry after missing marker",
        "old note",
        false,
        "reader"
    )
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.notes_updated == 1)
    assert(report.blocked == 0)
    assert(report.remote_errors == 0)
    assert(report.durable_link_identity_accepted >= 1)
    assert(state.v2_updates == 1)
    assert(state.row.sync_state == "synced")
    assert(state.row.last_synced_note == "retry after missing marker")
end

local function reconcileCase()
    local state = baseState()
    local mutator = newMutator(state, "new note", "new note", false)
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.notes_updated == 0)
    assert(report.notes_reconciled == 1)
    assert(state.v2_updates == 0)
    assert(state.row.sync_state == "synced")
end

local function normalizedBaselineCase()
    local state = baseState()
    state.row.last_synced_note = "old note\r\n"
    local mutator = newMutator(state, "new note", "old note\n", false)
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.notes_updated == 1)
    assert(report.conflicts == 0)
    assert(state.v2_updates == 1)
end

local function normalizedRemoteEqualsLocalCase()
    local state = baseState()
    local mutator = newMutator(state, "same note\n", "same note\r\n", false)
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.notes_reconciled == 1)
    assert(report.notes_updated == 0)
    assert(report.conflicts == 0)
end

local function propagationRepairCase()
    local state = baseState()
    state.auto_propagate_v2 = false
    local mutator = newMutator(state, "new note", "old note", false)
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.notes_updated == 1)
    assert(report.v2_note_updates == 1)
    assert(report.reader_note_propagation_misses == 1)
    assert(report.reader_v3_note_repairs == 1)
    assert(report.reader_note_repairs == 1)
    assert(state.v3_updates == 1)
    assert(state.row.last_synced_note == "new note")
end

local function prematureBaselineRepairCase()
    local state = baseState()
    state.row.last_synced_note = "new note"
    state.row.sync_state = "synced"
    state.row.readwise_v2_highlight_id = 77
    state.auto_propagate_v2 = false
    local mutator = newMutator(state, "new note", "new note", false)
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.notes_updated == 0)
    assert(report.notes_reconciled == 1)
    assert(report.reader_note_repairs == 1)
    assert(report.reader_v3_note_repairs == 1)
    assert(state.v2_updates == 0)
    assert(state.v3_updates == 1)
    assert(state.row.sync_state == "synced")
end

local function conflictCase()
    local state = baseState()
    local mutator = newMutator(state, "local edit", "remote edit", false)
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.conflicts == 1)
    assert(state.v2_updates == 0)
    assert(state.row.sync_state == "conflict")
    assert(state.row.last_sync_error == "note_conflict")
    assert(state.row.last_synced_note == "old note")
end

local function deletionOffCase()
    local state = baseState()
    state.row.local_deleted_at = 123
    state.row.sync_state = "local_deleted"
    local mutator = newMutator(state, false, "old note", false)
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.deletions_detected == 1)
    assert(report.deletions_retained == 1)
    assert(report.deletions_remote == 0)
    assert(state.deletes == 0)
    assert(state.row.created_remote == true)
end

local function deletionOnCase()
    local state = baseState()
    state.row.local_deleted_at = 123
    state.row.sync_state = "local_deleted"
    local mutator = newMutator(state, false, "old note", true)
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.deletions_detected == 1)
    assert(report.deletions_remote == 1)
    assert(report.delete_cross_api_identity_verified == 1)
    assert(report.reader_deletions_verified == 1)
    assert(report.reader_delete_verification_reads >= 1)
    assert(state.deletes == 1)
    assert(state.row.created_remote == false)
    assert(state.row.reader_highlight_document_id == nil)
    assert(state.row.sync_state == "deleted_synced")
end

local function missingMarkerDeleteUsesCrossApiIdentity()
    local state = baseState()
    state.row.local_deleted_at = 123
    state.row.sync_state = "local_deleted"
    local mutator = newMutator(state, false, "old note", true, "reader")
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.blocked == 0)
    assert(report.delete_cross_api_identity_verified == 1)
    assert(report.deletions_remote == 1)
    assert(report.reader_deletions_verified == 1)
    assert(state.deletes == 1)
    assert(state.row.created_remote == false)
end

local function legacyMarkerDeleteUsesCrossApiIdentity()
    local state = baseState()
    state.row.local_deleted_at = 123
    state.row.sync_state = "local_deleted"
    local mutator = newMutator(
        state,
        false,
        "old note",
        true,
        "KOReader Readwise Reader"
    )
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.blocked == 0)
    assert(report.delete_cross_api_identity_verified == 1)
    assert(report.deletions_remote == 1)
    assert(state.deletes == 1)
    assert(state.row.created_remote == false)
end

local function crossApiMismatchBlocksDelete()
    local state = baseState()
    state.row.local_deleted_at = 123
    state.row.sync_state = "local_deleted"
    state.row.readwise_v2_highlight_id = 77
    local documents, annotations = repos(state)
    local remote = child("old note", "reader")
    local reader = {
        getDocument = function() return copy(remote) end,
        deleteDocument = function()
            state.deletes = state.deletes + 1
            return true
        end,
    }
    local readwise = {
        getHighlight = function()
            return {
                id = 77,
                external_id = "different-reader-child",
                note = "old note",
            }
        end,
        listHighlights = function()
            return { count = 0, results = {} }
        end,
    }
    local mutator = Mutations:new{
        documents = documents,
        annotations = annotations,
        adapter = { scan = function() return { authoritative = true, annotations = {} } end },
        reader = reader,
        readwise = readwise,
        propagate_deletions = true,
        sleep = function() end,
        reader_verify_attempts = 2,
        reader_verify_delay = 0,
        file_exists = function() return true end,
    }
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.blocked == 1)
    assert(report.deletions_remote == 0)
    assert(state.deletes == 0)
    assert(state.row.created_remote == true)
end

local function identityMismatchBlocksDelete()
    local state = baseState()
    state.row.local_deleted_at = 123
    state.row.sync_state = "local_deleted"
    local documents, annotations = repos(state)
    local reader = {
        getDocument = function()
            local bad = child("old note")
            bad.parent_id = "other-parent"
            return bad
        end,
        deleteDocument = function()
            state.deletes = state.deletes + 1
            return true
        end,
    }
    local mutator = Mutations:new{
        documents = documents,
        annotations = annotations,
        adapter = { scan = function() return { authoritative = true, annotations = {} } end },
        reader = reader,
        propagate_deletions = true,
        file_exists = function() return true end,
    }
    local report = assert(mutator:syncPath("/Readwise/a.html"))
    assert(report.blocked == 1)
    assert(state.deletes == 0)
    assert(state.row.created_remote == true)
end

return function()
    updateCase()
    legacyUpdateCase()
    missingMarkerUpdateCase()
    reconcileCase()
    normalizedBaselineCase()
    normalizedRemoteEqualsLocalCase()
    propagationRepairCase()
    prematureBaselineRepairCase()
    conflictCase()
    deletionOffCase()
    deletionOnCase()
    missingMarkerDeleteUsesCrossApiIdentity()
    legacyMarkerDeleteUsesCrossApiIdentity()
    crossApiMismatchBlocksDelete()
    identityMismatchBlocksDelete()
end
