-- SPDX-License-Identifier: AGPL-3.0-only

local AnnotationIdentity = require("sync/annotation_identity")

local Mutations = {}
Mutations.__index = Mutations

local function err(kind, message, retryable)
    return { kind = kind, message = message, retryable = retryable == true }
end

local function isNotFound(value)
    return value and value.kind == "not_found"
end

function Mutations:new(options)
    options = options or {}
    return setmetatable({
        documents = assert(options.documents, "documents repository is required"),
        annotations = assert(options.annotations, "annotations repository is required"),
        adapter = assert(options.adapter, "annotation adapter is required"),
        reader = assert(options.reader, "Reader API is required"),
        propagate_deletions = options.propagate_deletions == true,
        file_exists = options.file_exists or function(path)
            return require("libs/libkoreader-lfs").attributes(path, "mode") == "file"
        end,
    }, self)
end

function Mutations:_verifyChild(document, link)
    if type(link.reader_highlight_document_id) ~= "string"
        or link.reader_highlight_document_id == "" then
        return nil, err("remote_identity", "Linked annotation has no Reader child id.", false)
    end

    local child, child_err = self.reader:getDocument(
        link.reader_highlight_document_id,
        false,
        false
    )
    if not child then return nil, child_err end

    local expected_source = AnnotationIdentity.markerFor(link.local_annotation_id)
    if child.id ~= link.reader_highlight_document_id
        or child.parent_id ~= document.reader_id
        or child.category ~= "highlight"
        or child.source ~= expected_source then
        return nil, err(
            "remote_identity",
            "Reader child identity did not match the linked annotation; no mutation was attempted.",
            false
        )
    end
    return child
end

function Mutations:_markSynced(candidate, link)
    self.annotations:setReaderRemoteLink(
        candidate.local_annotation_id,
        link.reader_highlight_document_id,
        {
            text = candidate.text,
            note = candidate.note,
            text_hash = candidate.text_hash,
            note_hash = candidate.note_hash,
            sync_state = "synced",
        }
    )
end

function Mutations:_syncChangedNote(document, candidate, link, report)
    if candidate.text ~= link.last_synced_text then
        self.annotations:setSyncState(
            candidate.local_annotation_id,
            "blocked",
            "local_text_changed"
        )
        report.blocked = report.blocked + 1
        report.text_changes_blocked = report.text_changes_blocked + 1
        return
    end

    local child, child_err = self:_verifyChild(document, link)
    if not child then
        self.annotations:setSyncState(
            candidate.local_annotation_id,
            "local_changed",
            child_err and child_err.kind or "remote_lookup"
        )
        report.remote_errors = report.remote_errors + 1
        return
    end

    local baseline = link.last_synced_note
    local local_note = candidate.note
    local remote_note = child.notes

    if local_note == baseline then
        -- The scanner can flag a locator-only change. No remote mutation is
        -- required when text/note semantics are unchanged.
        self:_markSynced(candidate, link)
        report.notes_reconciled = report.notes_reconciled + 1
        return
    end

    if remote_note == local_note then
        -- Covers timeout/response-loss after a previous PATCH.
        self:_markSynced(candidate, link)
        report.notes_reconciled = report.notes_reconciled + 1
        return
    end

    if remote_note ~= baseline then
        self.annotations:setSyncState(
            candidate.local_annotation_id,
            "conflict",
            "note_conflict"
        )
        report.conflicts = report.conflicts + 1
        return
    end

    if local_note == nil then
        -- Clearing a highlight note through Reader v3 has not been physically
        -- validated for this project. Preserve both sides instead of guessing.
        self.annotations:setSyncState(
            candidate.local_annotation_id,
            "blocked",
            "note_clear_unvalidated"
        )
        report.blocked = report.blocked + 1
        return
    end

    local updated, update_err = self.reader:updateDocument(
        link.reader_highlight_document_id,
        { notes = local_note }
    )
    if not updated then
        self.annotations:setSyncState(
            candidate.local_annotation_id,
            "local_changed",
            update_err and update_err.kind or "note_update"
        )
        report.remote_errors = report.remote_errors + 1
        return
    end

    local verified, verify_err = self:_verifyChild(document, link)
    if not verified then
        self.annotations:setSyncState(
            candidate.local_annotation_id,
            "local_changed",
            verify_err and verify_err.kind or "note_verify"
        )
        report.remote_errors = report.remote_errors + 1
        return
    end
    if verified.notes ~= local_note then
        self.annotations:setSyncState(
            candidate.local_annotation_id,
            "local_changed",
            "note_verify_mismatch"
        )
        report.remote_errors = report.remote_errors + 1
        return
    end

    self:_markSynced(candidate, link)
    report.notes_updated = report.notes_updated + 1
end

function Mutations:_syncDeletion(document, link, report)
    report.deletions_detected = report.deletions_detected + 1

    if not self.propagate_deletions then
        report.deletions_retained = report.deletions_retained + 1
        return
    end

    local child, child_err = self:_verifyChild(document, link)
    if not child then
        if isNotFound(child_err) then
            self.annotations:markRemoteDeleted(link.local_annotation_id)
            report.deletions_already_remote = report.deletions_already_remote + 1
            return
        end
        self.annotations:setSyncState(
            link.local_annotation_id,
            "local_deleted",
            child_err and child_err.kind or "delete_lookup"
        )
        if child_err and child_err.kind == "remote_identity" then
            report.blocked = report.blocked + 1
        else
            report.remote_errors = report.remote_errors + 1
        end
        return
    end

    local deleted, delete_err = self.reader:deleteDocument(child.id)
    if not deleted then
        self.annotations:setSyncState(
            link.local_annotation_id,
            "local_deleted",
            delete_err and delete_err.kind or "delete_remote"
        )
        report.remote_errors = report.remote_errors + 1
        return
    end

    self.annotations:markRemoteDeleted(link.local_annotation_id)
    report.deletions_remote = report.deletions_remote + 1
end

function Mutations:syncPath(local_path)
    local document = self.documents:getByLocalPath(local_path)
    if not document or document.is_managed ~= true then
        return nil, err("not_managed", "The current document is not managed by Readwise Reader.", false)
    end
    if document.is_local_present ~= true or not self.file_exists(document.local_path) then
        return nil, err("local_missing", "The managed Reader file is missing.", false)
    end

    local scan, scan_err = self.adapter:scan(document.local_path, document.reader_id)
    if not scan then return nil, scan_err end

    local report = {
        status = scan.authoritative and "ok" or (scan.status or "sidecar_not_authoritative"),
        scanned = #(scan.annotations or {}),
        notes_updated = 0,
        notes_reconciled = 0,
        conflicts = 0,
        blocked = 0,
        text_changes_blocked = 0,
        deletions_detected = 0,
        deletions_retained = 0,
        deletions_remote = 0,
        deletions_already_remote = 0,
        remote_errors = 0,
    }
    if not scan.authoritative then return report end

    local present = {}
    for _, candidate in ipairs(scan.annotations or {}) do
        present[candidate.local_annotation_id] = candidate
        local link = self.annotations:getById(candidate.local_annotation_id)
        if link
            and link.created_remote == true
            and link.local_deleted_at == nil
            and link.sync_state == "local_changed" then
            self:_syncChangedNote(document, candidate, link, report)
        end
    end

    for _, link in ipairs(self.annotations:listByDocument(document.reader_id)) do
        if link.created_remote == true
            and link.local_deleted_at ~= nil
            and present[link.local_annotation_id] == nil then
            self:_syncDeletion(document, link, report)
        end
    end

    return report
end

Mutations._isNotFound = isNotFound

return Mutations
