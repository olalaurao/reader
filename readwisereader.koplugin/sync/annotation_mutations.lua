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
        readwise = options.readwise,
        v2_by_external_id = {},
        v2_duplicate_external_id = {},
        v2_scan_complete = false,
        propagate_deletions = options.propagate_deletions == true,
        file_exists = options.file_exists or function(path)
            return require("libs/libkoreader-lfs").attributes(path, "mode") == "file"
        end,
    }, self)
end

function Mutations:_verifyChild(document, link, options)
    options = options or {}
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

    if child.id ~= link.reader_highlight_document_id
        or child.parent_id ~= document.reader_id
        or child.category ~= "highlight" then
        return nil, err(
            "remote_identity",
            "Reader child id/parent/category did not match the durable link; no mutation was attempted.",
            false
        )
    end

    local expected_source = AnnotationIdentity.markerFor(link.local_annotation_id)
    if child.source == expected_source then
        return child, nil, "exact"
    end

    if options.allow_legacy_source == true
        and child.source == "KOReader Readwise Reader" then
        return child, nil, "legacy"
    end

    if options.allow_durable_link_without_source == true then
        -- Reader LIST has not returned saved_using/source consistently for
        -- production highlight children. For non-destructive note updates the
        -- durable child ID + original parent + highlight category are already
        -- an unambiguous identity. DELETE deliberately does not use this path.
        return child, nil, "durable_link"
    end

    return nil, err(
        "remote_identity",
        "Reader child ownership marker did not match the linked annotation; no mutation was attempted.",
        false
    )
end

function Mutations:_loadV2Index(report)
    if self.v2_scan_complete then return true end
    if not self.readwise then
        return nil, err(
            "v2_unavailable",
            "Readwise v2 client is required for safe note conflict detection.",
            false
        )
    end

    local page_number = 1
    while true do
        local page, page_err = self.readwise:listHighlights{
            page_size = 1000,
            page = page_number,
        }
        if not page then return nil, page_err end
        report.v2_pages_scanned = report.v2_pages_scanned + 1

        for _, highlight in ipairs(page.results or {}) do
            local external_id = highlight.external_id
            if type(external_id) == "string" and external_id ~= "" then
                local prior = self.v2_by_external_id[external_id]
                if prior and prior.id ~= highlight.id then
                    self.v2_duplicate_external_id[external_id] = true
                else
                    self.v2_by_external_id[external_id] = highlight
                end
            end
        end

        local count = tonumber(page.count) or #(page.results or {})
        if #(page.results or {}) == 0 or page_number * 1000 >= count then
            break
        end
        page_number = page_number + 1
        if page_number > 1000 then
            return nil, err(
                "v2_pagination",
                "Readwise v2 highlight pagination exceeded the safety bound.",
                false
            )
        end
    end

    self.v2_scan_complete = true
    return true
end

function Mutations:_getV2Highlight(link, report)
    if not self.readwise then
        return nil, err(
            "v2_unavailable",
            "Readwise v2 client is required for safe note conflict detection.",
            false
        )
    end

    local external_id = link.reader_highlight_document_id
    if self.v2_duplicate_external_id[external_id] then
        return nil, err(
            "v2_mapping_ambiguous",
            "Multiple Readwise v2 highlights share the Reader child external_id.",
            false
        )
    end

    if link.readwise_v2_highlight_id then
        local detail, detail_err = self.readwise:getHighlight(link.readwise_v2_highlight_id)
        if detail then
            report.v2_remote_note_reads = report.v2_remote_note_reads + 1
            if detail.external_id ~= external_id then
                return nil, err(
                    "remote_identity",
                    "Stored Readwise v2 highlight id no longer maps to the linked Reader child.",
                    false
                )
            end
            self.v2_by_external_id[external_id] = detail
            return detail
        end
        if detail_err and not isNotFound(detail_err) then
            return nil, detail_err
        end
        self.annotations:setReadwiseV2Id(link.local_annotation_id, nil)
    end

    local loaded, load_err = self:_loadV2Index(report)
    if not loaded then return nil, load_err end
    if self.v2_duplicate_external_id[external_id] then
        return nil, err(
            "v2_mapping_ambiguous",
            "Multiple Readwise v2 highlights share the Reader child external_id.",
            false
        )
    end

    local highlight = self.v2_by_external_id[external_id]
    if not highlight then
        return nil, err(
            "v2_mapping",
            "No deterministic Readwise v2 highlight matched the Reader child external_id.",
            false
        )
    end

    self.annotations:setReadwiseV2Id(link.local_annotation_id, highlight.id)
    report.v2_mappings_resolved = report.v2_mappings_resolved + 1
    report.v2_remote_note_reads = report.v2_remote_note_reads + 1
    return highlight
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

    local child, child_err, identity_mode = self:_verifyChild(
        document,
        link,
        {
            allow_legacy_source = true,
            allow_durable_link_without_source = true,
        }
    )
    if not child then
        self.annotations:setSyncState(
            candidate.local_annotation_id,
            child_err and child_err.kind == "remote_identity" and "blocked" or "local_changed",
            child_err and child_err.kind or "remote_lookup"
        )
        if child_err and child_err.kind == "remote_identity" then
            report.blocked = report.blocked + 1
        else
            report.remote_errors = report.remote_errors + 1
        end
        return
    end
    if identity_mode == "legacy" then
        report.legacy_identity_accepted = report.legacy_identity_accepted + 1
    elseif identity_mode == "durable_link" then
        report.durable_link_identity_accepted = report.durable_link_identity_accepted + 1
    end

    local baseline = link.last_synced_note
    local local_note = candidate.note

    if local_note == baseline then
        self:_markSynced(candidate, link)
        report.notes_reconciled = report.notes_reconciled + 1
        return
    end

    local remote_v2, v2_err = self:_getV2Highlight(link, report)
    if not remote_v2 then
        local safe_block = v2_err and (
            v2_err.kind == "v2_mapping"
            or v2_err.kind == "v2_mapping_ambiguous"
            or v2_err.kind == "remote_identity"
            or v2_err.kind == "v2_unavailable"
        )
        self.annotations:setSyncState(
            candidate.local_annotation_id,
            safe_block and "blocked" or "local_changed",
            v2_err and v2_err.kind or "v2_remote_note"
        )
        if safe_block then
            report.blocked = report.blocked + 1
        else
            report.remote_errors = report.remote_errors + 1
        end
        return
    end

    local remote_note = remote_v2.note
    if remote_note == local_note then
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
        self.annotations:setSyncState(
            candidate.local_annotation_id,
            "blocked",
            "note_clear_unvalidated"
        )
        report.blocked = report.blocked + 1
        return
    end

    local updated, update_err = self.readwise:updateHighlight(
        remote_v2.id,
        { note = local_note }
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
    if updated.id ~= remote_v2.id or updated.note ~= local_note then
        self.annotations:setSyncState(
            candidate.local_annotation_id,
            "local_changed",
            "v2_note_update_verify"
        )
        report.remote_errors = report.remote_errors + 1
        return
    end

    self.annotations:setReadwiseV2Id(candidate.local_annotation_id, updated.id)
    self:_markSynced(candidate, link)
    report.notes_updated = report.notes_updated + 1
    report.v2_note_updates = report.v2_note_updates + 1
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
        legacy_identity_accepted = 0,
        durable_link_identity_accepted = 0,
        v2_pages_scanned = 0,
        v2_mappings_resolved = 0,
        v2_remote_note_reads = 0,
        v2_note_updates = 0,
    }
    if not scan.authoritative then return report end

    local present = {}
    for _, candidate in ipairs(scan.annotations or {}) do
        present[candidate.local_annotation_id] = candidate
        local link = self.annotations:getById(candidate.local_annotation_id)
        if link
            and link.created_remote == true
            and link.local_deleted_at == nil then
            local note_differs_from_baseline = candidate.note ~= link.last_synced_note
            local should_retry_note = link.sync_state == "local_changed"
                or link.sync_state == "blocked"
                or link.sync_state == "conflict"
            if note_differs_from_baseline and should_retry_note then
                self:_syncChangedNote(document, candidate, link, report)
            end
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
