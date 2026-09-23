-- SPDX-License-Identifier: AGPL-3.0-only

local TextMatch = require("sync/text_match")

local Upload = {}
Upload.__index = Upload

function Upload:new(options)
    options = options or {}
    return setmetatable({
        documents = assert(options.documents, "documents repository is required"),
        annotations = assert(options.annotations, "annotations repository is required"),
        adapter = assert(options.adapter, "annotation adapter is required"),
        reader = assert(options.reader, "Reader API is required"),
        hasher = assert(options.hasher, "hasher is required"),
        matcher = options.matcher or TextMatch,
        file_exists = options.file_exists or function(path)
            return require("libs/libkoreader-lfs").attributes(path, "mode") == "file"
        end,
    }, self)
end

local function err(kind, message, retryable)
    return { kind = kind, message = message, retryable = retryable == true }
end

function Upload:uploadOne(local_path)
    local document = self.documents:getByLocalPath(local_path)
    if not document or document.is_managed ~= true then
        return nil, err("not_managed", "The current document is not managed by Readwise Reader.")
    end
    if document.is_local_present ~= true or not self.file_exists(document.local_path) then
        return nil, err("local_missing", "The managed Reader file is missing.")
    end

    local scan, scan_err = self.adapter:scan(document.local_path, document.reader_id)
    if not scan then return nil, scan_err end
    if not scan.authoritative then
        return nil, err("sidecar", "KOReader annotations are not authoritative yet.")
    end

    local candidate
    for _, item in ipairs(scan.annotations or {}) do
        local link = self.annotations:getById(item.local_annotation_id)
        if link and link.created_remote then
            -- Already linked: never create it again.
        elseif link and link.sync_state == "local_only" then
            candidate = item
            break
        end
    end
    if not candidate then
        return { uploaded = 0, status = "nothing_to_upload" }
    end

    local parent, parent_err = self.reader:getDocument(document.reader_id, true, false)
    if not parent then return nil, parent_err end
    local exact, match = self.matcher.findExactSubstring(parent.html_content, candidate.text)
    if not exact then
        return nil, match
    end

    local created, create_err = self.reader:createHighlight(
        document.reader_id,
        exact,
        candidate.note
    )
    if not created then
        -- A failed POST can be ambiguous after a transport timeout. We do not
        -- retry automatically here: the durable link is written only after a
        -- confirmed Reader response, preventing a blind duplicate.
        return nil, create_err
    end

    self.annotations:setReaderRemoteLink(candidate.local_annotation_id, created.id, {
        text = candidate.text,
        note = candidate.note,
        text_hash = candidate.text_hash,
        note_hash = candidate.note_hash,
        sync_state = "synced",
    })

    return {
        uploaded = 1,
        status = "created",
        local_annotation_id = candidate.local_annotation_id,
        reader_highlight_document_id = created.id,
        match_mode = match.mode,
        note_preserved = candidate.note,
    }
end

return Upload
