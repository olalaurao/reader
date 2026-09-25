-- SPDX-License-Identifier: AGPL-3.0-only

local Import = {}
Import.__index = Import

local function domainError(kind, message)
    return { kind = kind, retryable = false, message = message }
end


local function samePdfBoxes(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b or #a == 0 then
        return false
    end
    for index = 1, #a do
        local left, right = a[index], b[index]
        if type(left) ~= "table" or type(right) ~= "table"
            or left.x ~= right.x or left.y ~= right.y
            or left.w ~= right.w or left.h ~= right.h then
            return false
        end
    end
    return true
end

local function pdfPersistedCandidate(normalized, item)
    return item.page == normalized.page
        and samePdfBoxes(item.pboxes, normalized.pboxes)
        and item.text_hash == normalized.text_hash
        and item.note_hash == normalized.note_hash
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

    -- PDF sidecars may serialize native position context (for example zoom or
    -- rotation fields) differently from the in-memory item even though the
    -- durable native page boxes are unchanged. Keep the normal deterministic
    -- ID lookup first. Only when that fails for a PDF, accept exactly one
    -- sidecar annotation whose page + pboxes + text/note hashes all match the
    -- just-created item. This fallback is verification-only; Reader child ID
    -- remains the remote identity and no fuzzy text matching is introduced.
    if not persisted and document.local_format == "pdf" then
        local candidates = {}
        for _, item in ipairs(scan.annotations or {}) do
            if pdfPersistedCandidate(normalized, item) then
                candidates[#candidates + 1] = item
            end
        end
        if #candidates == 1 then
            persisted = candidates[1]
        elseif #candidates > 1 then
            return nil, domainError(
                "sidecar_ambiguous",
                "Created PDF highlight matched multiple persisted sidecar annotations."
            )
        end
    end

    if not persisted then
        return nil, domainError(
            "sidecar_lookup",
            document.local_format == "pdf"
                and "Created PDF highlight was not found uniquely in the persisted sidecar."
                or "Created KOReader highlight was not found in the persisted sidecar."
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

Import._pdfPersistedCandidate = pdfPersistedCandidate
Import._samePdfBoxes = samePdfBoxes

return Import
