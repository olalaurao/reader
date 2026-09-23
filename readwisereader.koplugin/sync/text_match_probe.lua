-- SPDX-License-Identifier: AGPL-3.0-only

local TextMatch = require("sync/text_match")

local Probe = {}
Probe.__index = Probe

local function err(kind, message, retryable)
    return {
        kind = kind,
        message = message,
        retryable = retryable == true,
    }
end

function Probe:new(options)
    options = options or {}
    return setmetatable({
        documents = assert(options.documents, "documents repository is required"),
        adapter = assert(options.adapter, "annotation adapter is required"),
        reader = assert(options.reader, "Reader API is required"),
        matcher = options.matcher or TextMatch,
        file_exists = options.file_exists or function(path)
            return require("libs/libkoreader-lfs").attributes(path, "mode") == "file"
        end,
    }, self)
end

function Probe:run(local_path)
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
        if type(item.text) == "string" and item.text ~= "" then
            candidate = item
            break
        end
    end
    if not candidate then
        return nil, err("annotation", "No local highlight with text was found in the current document.")
    end

    local parent, parent_err = self.reader:getDocument(document.reader_id, true, false)
    if not parent then return nil, parent_err end
    if type(parent.html_content) ~= "string" or parent.html_content == "" then
        return nil, err("content", "Reader did not return HTML content for this document.")
    end

    local exact, match = self.matcher.findExactSubstring(parent.html_content, candidate.text)
    if not exact then
        return {
            matched = false,
            status = match and match.kind or "unmatched",
            message = match and match.message or "Highlight could not be matched safely.",
            local_annotation_id = candidate.local_annotation_id,
            local_text = candidate.text,
            remote_writes = 0,
        }
    end

    return {
        matched = true,
        status = "matched",
        mode = match and match.mode or "unknown",
        local_annotation_id = candidate.local_annotation_id,
        local_text = candidate.text,
        reader_exact_text = exact,
        remote_writes = 0,
    }
end

return Probe
