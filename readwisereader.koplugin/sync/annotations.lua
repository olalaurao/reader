-- SPDX-License-Identifier: AGPL-3.0-only

local AnnotationSync = {}
AnnotationSync.__index = AnnotationSync

local function hashChanged(existing, item)
    return existing.last_text_hash ~= item.text_hash
        or existing.last_note_hash ~= item.note_hash
        or existing.locator_fingerprint ~= item.locator_fingerprint
end

local function localStateFor(existing, changed)
    if not existing then return "local_only" end
    if changed or existing.local_deleted_at ~= nil then
        return existing.created_remote and "local_changed" or "local_only"
    end
    return existing.sync_state or (existing.created_remote and "synced" or "local_only")
end

function AnnotationSync:new(options)
    options = options or {}
    return setmetatable({
        documents = assert(options.documents, "documents repository is required"),
        annotations = assert(options.annotations, "annotations repository is required"),
        adapter = assert(options.adapter, "annotation adapter is required"),
        now = options.now or os.time,
        file_exists = options.file_exists or function(path)
            return require("libs/libkoreader-lfs").attributes(path, "mode") == "file"
        end,
    }, self)
end

function AnnotationSync:scanPath(local_path)
    local document = self.documents:getByLocalPath(local_path)
    if not document or document.is_managed ~= true then
        return nil, {
            kind = "not_managed",
            retryable = false,
            message = "The current document is not managed by Readwise Reader.",
        }
    end
    if document.is_local_present ~= true then
        return nil, {
            kind = "not_local",
            retryable = false,
            message = "The managed Reader document is not recorded as local.",
        }
    end
    if not self.file_exists(document.local_path) then
        return nil, {
            kind = "local_missing",
            retryable = false,
            message = "The managed Reader file is missing; annotation deletion was not inferred.",
        }
    end

    local scan, scan_err = self.adapter:scan(document.local_path, document.reader_id)
    if not scan then return nil, scan_err end

    local report = {
        reader_document_id = document.reader_id,
        local_path = document.local_path,
        authoritative = scan.authoritative == true,
        status = scan.status,
        malformed = scan.malformed or 0,
        highlights = 0,
        notes = 0,
        new = 0,
        changed = 0,
        unchanged = 0,
        deleted = 0,
        degraded_identity = 0,
        identity_collisions = 0,
        sample = nil,
        -- Internal handoff for Phase O backlog queueing. These are the same
        -- candidates whose durable annotation_links were just reconciled
        -- above; they are not logged or persisted as document bodies.
        annotations = scan.annotations or {},
    }

    if not scan.authoritative then
        return report
    end

    local existing_by_id = {}
    local degraded_by_locator = {}
    for _, existing in ipairs(self.annotations:listByDocument(document.reader_id)) do
        existing_by_id[existing.local_annotation_id] = existing
        if existing.local_created_at == nil then
            local previous = degraded_by_locator[existing.locator_fingerprint]
            if previous == nil then
                degraded_by_locator[existing.locator_fingerprint] = existing
            else
                degraded_by_locator[existing.locator_fingerprint] = false
            end
        end
    end

    local seen = {}
    for _, item in ipairs(scan.annotations or {}) do
        if item.identity_quality == "degraded" then
            report.degraded_identity = report.degraded_identity + 1
            local prior = degraded_by_locator[item.locator_fingerprint]
            if type(prior) == "table" then
                -- datetime-less KOReader annotations use the first-seen text
                -- hash only for initial identity. Reuse the stored ID on later
                -- text edits when the locator has one unambiguous match.
                item.local_annotation_id = prior.local_annotation_id
            end
        end

        local existing = existing_by_id[item.local_annotation_id]
        if existing and existing.locator_fingerprint ~= item.locator_fingerprint then
            report.identity_collisions = report.identity_collisions + 1
            item.local_annotation_id = item.local_annotation_id
                .. "-"
                .. tostring(item.locator_fingerprint):sub(1, 12)
            existing = existing_by_id[item.local_annotation_id]
        end

        seen[item.local_annotation_id] = true
        report.highlights = report.highlights + 1
        if item.note ~= nil and item.note ~= "" then
            report.notes = report.notes + 1
        end

        local changed = existing and (
            hashChanged(existing, item) or existing.local_deleted_at ~= nil
        ) or false

        if not existing then
            report.new = report.new + 1
        elseif changed then
            report.changed = report.changed + 1
        else
            report.unchanged = report.unchanged + 1
        end

        self.annotations:upsertLocal{
            local_annotation_id = item.local_annotation_id,
            reader_document_id = document.reader_id,
            local_created_at = item.datetime,
            locator_fingerprint = item.locator_fingerprint,
            original_text_hash = item.text_hash,
            last_text_hash = item.text_hash,
            last_note_hash = item.note_hash,
            sync_state = localStateFor(existing, changed),
            last_sync_error = nil,
        }

        if not report.sample then
            report.sample = {
                local_annotation_id = item.local_annotation_id,
                locator_fingerprint = item.locator_fingerprint,
                identity_quality = item.identity_quality,
                datetime = item.datetime,
                datetime_updated = item.datetime_updated,
                text = item.text,
                note = item.note,
                page = item.page,
                pos0 = item.pos0,
                pos1 = item.pos1,
            }
        end
    end

    local deleted_at = self.now()
    for local_annotation_id, existing in pairs(existing_by_id) do
        if not seen[local_annotation_id] and existing.local_deleted_at == nil then
            self.annotations:markLocalDeleted(local_annotation_id, deleted_at)
            report.deleted = report.deleted + 1
        end
    end

    return report
end

AnnotationSync._hashChanged = hashChanged
AnnotationSync._localStateFor = localStateFor

return AnnotationSync
