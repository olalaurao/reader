-- SPDX-License-Identifier: AGPL-3.0-only

local Import = {}
Import.__index = Import

local function domainError(kind, message)
    return { kind = kind, retryable = false, message = message }
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
    if document.local_format ~= "epub" and document.local_format ~= "html" then
        return nil, domainError("format", "Reader highlight import currently supports EPUB/HTML only.")
    end
    return document
end

function Import:isRemoteLinked(reader_highlight_document_id)
    return self.annotations:getByReaderRemoteId(reader_highlight_document_id)
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

    local normalized, normalize_err = self.adapter:normalize(document.reader_id, local_annotation)
    if not normalized then
        return nil, domainError("annotation", "Created KOReader highlight could not be normalized: " .. tostring(normalize_err))
    end

    local scan, scan_err = self.adapter:scan(document.local_path, document.reader_id)
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
    if not persisted then
        return nil, domainError("sidecar", "Created KOReader highlight was not found in the persisted sidecar.")
    end

    local ok, linked = pcall(
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
    if not ok or not linked then
        return nil, domainError("db", "Imported highlight could not be linked durably.")
    end

    return {
        status = "linked",
        local_annotation_id = persisted.local_annotation_id,
        link = linked,
        text = persisted.text,
        note = persisted.note,
    }
end

return Import
