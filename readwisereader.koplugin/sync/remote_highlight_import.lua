-- SPDX-License-Identifier: AGPL-3.0-only

local Import = {}
Import.__index = Import

local function domainError(kind, message)
    return { kind = kind, retryable = false, message = message }
end


local function samePagingPos(a, b)
    return type(a) == "table" and type(b) == "table"
        and a.x == b.x and a.y == b.y
end

-- Mirror KOReader ReaderAnnotation:getMatchFunc() for paging annotations.
-- KOReader matches by datetime (when present on both), page, and native
-- endpoint x/y. pboxes are rendering geometry and may be normalized
-- independently, so they are not part of the persisted-item lookup.
local function pdfNativeMatch(normalized, item)
    if item.page ~= normalized.page then return false end
    if normalized.datetime ~= nil and item.datetime ~= nil
        and normalized.datetime ~= item.datetime then
        return false
    end
    return samePagingPos(item.pos0, normalized.pos0)
        and samePagingPos(item.pos1, normalized.pos1)
end

local function pdfCandidateStats(normalized, items)
    local stats = {
        scanned = 0,
        same_page = 0,
        same_datetime = 0,
        same_pos0 = 0,
        same_pos1 = 0,
        native_matches = 0,
    }
    for _, item in ipairs(items or {}) do
        stats.scanned = stats.scanned + 1
        if item.page == normalized.page then
            stats.same_page = stats.same_page + 1
            local datetime_ok = not (
                normalized.datetime ~= nil and item.datetime ~= nil
                and normalized.datetime ~= item.datetime
            )
            if datetime_ok then
                stats.same_datetime = stats.same_datetime + 1
                if samePagingPos(item.pos0, normalized.pos0) then
                    stats.same_pos0 = stats.same_pos0 + 1
                    if samePagingPos(item.pos1, normalized.pos1) then
                        stats.same_pos1 = stats.same_pos1 + 1
                        stats.native_matches = stats.native_matches + 1
                    end
                end
            end
        end
    end
    return stats
end

function Import:new(options)
    options = options or {}
    return setmetatable({
        documents = assert(options.documents, "documents repository is required"),
        annotations = assert(options.annotations, "annotations repository is required"),
        adapter = assert(options.adapter, "annotation adapter is required"),
    }, self)
end

function Import:getDocument(local_path)
    local document = self.documents:getByLocalPath(local_path)
    if not document or document.is_managed ~= true then
        return nil, domainError("not_managed", "The current document is not managed by Readwise Reader.")
    end
    if document.is_local_present ~= true then
        return nil, domainError("not_local", "The managed Reader document is not recorded as local.")
    end
    if document.local_format ~= "epub"
        and document.local_format ~= "html"
        and document.local_format ~= "pdf" then
        return nil, domainError(
            "format",
            "Reader highlight import supports managed EPUB/HTML/PDF documents only."
        )
    end
    return document
end

function Import:isRemoteLinked(reader_highlight_document_id)
    return self.annotations:getByReaderRemoteId(reader_highlight_document_id)
end

function Import:getLocalLink(local_annotation_id)
    return self.annotations:getById(local_annotation_id)
end

function Import:normalizeLocal(local_path, local_annotation)
    local document, document_err = self:getDocument(local_path)
    if not document then return nil, document_err end

    local normalized, normalize_err = self.adapter:normalize(
        document.reader_id,
        local_annotation
    )
    if not normalized then
        return nil, domainError(
            "annotation",
            "KOReader highlight could not be normalized: " .. tostring(normalize_err)
        )
    end
    return normalized, document
end

function Import:linkPersisted(local_path, remote, local_annotation)
    if type(remote) ~= "table"
        or type(remote.id) ~= "string" or remote.id == ""
        or type(remote.parent_id) ~= "string" or remote.parent_id == "" then
        return nil, domainError("remote", "Reader highlight identity is incomplete.")
    end

    local document, document_err = self:getDocument(local_path)
    if not document then return nil, document_err end
    if remote.parent_id ~= document.reader_id then
        return nil, domainError("parent", "Reader highlight belongs to a different document.")
    end

    local already = self.annotations:getByReaderRemoteId(remote.id)
    if already then
        return {
            status = "already_linked",
            local_annotation_id = already.local_annotation_id,
            link = already,
        }
    end

    local normalized, normalize_err = self.adapter:normalize(
        document.reader_id,
        local_annotation
    )
    if not normalized then
        return nil, domainError(
            "annotation",
            "Created KOReader highlight could not be normalized: " .. tostring(normalize_err)
        )
    end

    local scan_method = document.local_format == "pdf"
        and self.adapter.scanFlushed or self.adapter.scan
    local scan, scan_err = scan_method(
        self.adapter,
        document.local_path,
        document.reader_id
    )
    if not scan then return nil, scan_err end
    if not scan.authoritative then
        return nil, domainError("sidecar", "KOReader sidecar is not authoritative after save.")
    end

    local persisted
    for _, item in ipairs(scan.annotations or {}) do
        if item.local_annotation_id == normalized.local_annotation_id then
            persisted = item
            break
        end
    end

    -- Keep deterministic local ID as the primary lookup. If PDF serialization
    -- changes non-identity fields, fall back only to KOReader's own native
    -- paging match contract (ReaderAnnotation:getMatchFunc): datetime when
    -- present, page, pos0 x/y, pos1 x/y. Exactly one candidate is required.
    if not persisted and document.local_format == "pdf" then
        local candidates = {}
        for _, item in ipairs(scan.annotations or {}) do
            if pdfNativeMatch(normalized, item) then
                candidates[#candidates + 1] = item
            end
        end
        if #candidates == 1 then
            persisted = candidates[1]
        elseif #candidates > 1 then
            return nil, domainError(
                "sidecar_ambiguous",
                "Created PDF highlight matched multiple persisted sidecar annotations by KOReader native paging identity."
            )
        end
    end

    if not persisted then
        if document.local_format == "pdf" then
            local stats = pdfCandidateStats(normalized, scan.annotations)
            return nil, domainError(
                "sidecar_lookup",
                string.format(
                    "Created PDF highlight was not found by KOReader native paging identity (scanned=%d, same_page=%d, same_datetime=%d, same_pos0=%d, same_pos1=%d).",
                    stats.scanned,
                    stats.same_page,
                    stats.same_datetime,
                    stats.same_pos0,
                    stats.same_pos1
                )
            )
        end
        return nil, domainError(
            "sidecar_lookup",
            "Created KOReader highlight was not found in the persisted sidecar."
        )
    end

    -- The persisted native match must still carry the same normalized content
    -- we just created. Identity is positional; content equality is a safety
    -- check before binding the pre-existing Reader child ID.
    if document.local_format == "pdf"
        and (persisted.text_hash ~= normalized.text_hash
            or persisted.note_hash ~= normalized.note_hash) then
        return nil, domainError(
            "sidecar_content",
            "Persisted PDF highlight position matched, but its text/note content differed."
        )
    end

    local ok, linked_or_err = pcall(
        self.annotations.linkImported,
        self.annotations,
        {
            local_annotation_id = persisted.local_annotation_id,
            reader_document_id = document.reader_id,
            reader_highlight_document_id = remote.id,
            local_created_at = persisted.datetime,
            locator_fingerprint = persisted.locator_fingerprint,
            original_text_hash = persisted.text_hash,
            last_text_hash = persisted.text_hash,
            last_note_hash = persisted.note_hash,
            text = persisted.text,
            note = persisted.note,
            remote_updated_marker = remote.updated_at,
        }
    )
    if not ok or not linked_or_err then
        return nil, domainError(
            "db",
            ok
                and "Imported highlight link returned no durable row."
                or "Imported highlight database transaction failed."
        )
    end
    local linked = linked_or_err

    return {
        status = "linked",
        local_annotation_id = persisted.local_annotation_id,
        link = linked,
        text = persisted.text,
        note = persisted.note,
    }
end

Import._pdfCandidateStats = pdfCandidateStats
Import._pdfNativeMatch = pdfNativeMatch
Import._samePagingPos = samePagingPos

return Import
