-- SPDX-License-Identifier: AGPL-3.0-only

local Probe = {}
Probe.__index = Probe

local function domainError(kind, message)
    return { kind = kind, retryable = false, message = message }
end

local function stableSort(a, b)
    local ao, bo = tonumber(a.highlight_offset), tonumber(b.highlight_offset)
    if ao and bo and ao ~= bo then return ao < bo end
    if ao and not bo then return true end
    if bo and not ao then return false end
    local ac, bc = tostring(a.created_at or ""), tostring(b.created_at or "")
    if ac ~= bc then return ac < bc end
    return tostring(a.id or "") < tostring(b.id or "")
end

function Probe:new(options)
    options = options or {}
    return setmetatable({
        documents = assert(options.documents, "documents repository is required"),
        reader = assert(options.reader, "Reader API is required"),
        file_exists = options.file_exists or function(path)
            return require("libs/libkoreader-lfs").attributes(path, "mode") == "file"
        end,
    }, self)
end

function Probe:run(local_path, options)
    options = options or {}
    if type(local_path) ~= "string" or local_path == "" then
        return nil, domainError("document", "Open a Readwise-managed PDF first.")
    end

    local document = self.documents:getByLocalPath(local_path)
    if not document or document.is_managed ~= true then
        return nil, domainError(
            "not_managed",
            "The current PDF is not managed by Readwise Reader."
        )
    end
    if document.is_local_present ~= true
        or not self.file_exists(document.local_path) then
        return nil, domainError("local_missing", "The managed Reader PDF is missing.")
    end
    if document.local_format ~= "pdf" then
        return nil, domainError(
            "format",
            "Gate 17D probes original paging PDF documents only."
        )
    end

    local highlights = {}
    local parent_records = 0
    local highlights_with_notes = 0
    local scan, err = self.reader:iterateDocuments({
        category = "highlight",
        updated_after = options.updated_after,
        limit = 100,
        with_html_content = false,
        with_raw_source_url = false,
    }, function(remote)
        if remote.parent_id ~= document.reader_id then return end
        parent_records = parent_records + 1
        if type(remote.content) ~= "string" or remote.content == "" then return end
        local note_present =
            type(remote.notes) == "string" and remote.notes ~= ""
        if note_present then
            highlights_with_notes = highlights_with_notes + 1
        end
        highlights[#highlights + 1] = {
            id = remote.id,
            parent_id = remote.parent_id,
            content = remote.content,
            notes = remote.notes,
            note_present = note_present,
            created_at = remote.created_at,
            updated_at = remote.updated_at,
            highlight_offset = remote.highlight_offset,
            highlight_location = remote.highlight_location,
        }
    end)
    if not scan then return nil, err end

    table.sort(highlights, stableSort)
    return {
        reader_document_id = document.reader_id,
        local_format = document.local_format,
        remote_highlights = highlights,
        parent_highlight_records = parent_records,
        highlights_with_text = #highlights,
        highlights_with_notes = highlights_with_notes,
        pages = scan.pages or 0,
        records_scanned = scan.unique or 0,
        duplicate_records_ignored = scan.duplicates or 0,
        remote_writes = 0,
        local_writes = 0,
        updated_after = options.updated_after,
    }
end

return Probe
