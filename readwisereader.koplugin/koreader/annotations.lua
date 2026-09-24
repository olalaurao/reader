-- SPDX-License-Identifier: AGPL-3.0-only

local KOReaderAnnotations = {}
KOReaderAnnotations.__index = KOReaderAnnotations

local function defaultDocSettings()
    return require("docsettings")
end

local function canonical(value, seen)
    local kind = type(value)
    if kind == "nil" then
        return "n"
    elseif kind == "boolean" then
        return value and "b1" or "b0"
    elseif kind == "number" then
        -- %g follows the process locale on some libc builds. Normalize the
        -- decimal separator so the same PDF coordinates hash identically.
        local encoded = string.format("%.17g", value):gsub(",", ".")
        return "d" .. encoded
    elseif kind == "string" then
        return "s" .. tostring(#value) .. ":" .. value
    elseif kind ~= "table" then
        return "x" .. kind .. ":" .. tostring(value)
    end

    seen = seen or {}
    if seen[value] then
        error("annotation locator contains a cycle")
    end
    seen[value] = true

    local entries = {}
    for key, item in pairs(value) do
        local encoded_key = canonical(key, seen)
        entries[#entries + 1] = {
            key = encoded_key,
            value = canonical(item, seen),
        }
    end
    table.sort(entries, function(a, b)
        if a.key == b.key then return a.value < b.value end
        return a.key < b.key
    end)

    local out = { "t{" }
    for _, entry in ipairs(entries) do
        out[#out + 1] = entry.key
        out[#out + 1] = "="
        out[#out + 1] = entry.value
        out[#out + 1] = ";"
    end
    out[#out + 1] = "}"
    seen[value] = nil
    return table.concat(out)
end

local function locatorPayload(annotation)
    return {
        page = annotation.page,
        pos0 = annotation.pos0,
        pos1 = annotation.pos1,
        ext = annotation.ext,
    }
end

local function hashOptional(hasher, value)
    if value == nil then
        return hasher.sha256("\0nil")
    end
    return hasher.sha256("\1" .. tostring(value))
end

local function isHighlight(annotation)
    return type(annotation) == "table" and annotation.drawer ~= nil
end

local function sortMarker(annotation)
    return tostring(annotation.datetime_updated or annotation.datetime or "")
end

function KOReaderAnnotations:new(options)
    options = options or {}
    return setmetatable({
        doc_settings = options.doc_settings or defaultDocSettings(),
        hasher = assert(options.hasher, "hasher is required"),
    }, self)
end

function KOReaderAnnotations:identity(reader_document_id, annotation)
    assert(type(reader_document_id) == "string" and reader_document_id ~= "", "reader_document_id is required")
    assert(type(annotation) == "table", "annotation is required")

    local locator = canonical(locatorPayload(annotation))
    local locator_fingerprint = self.hasher.sha256(locator)
    local datetime = annotation.datetime
    local quality = "strong"
    local identity_payload
    if type(datetime) == "string" and datetime ~= "" then
        identity_payload = reader_document_id .. "\n" .. datetime .. "\n" .. locator
    else
        quality = "degraded"
        identity_payload = reader_document_id
            .. "\n<missing-datetime>\n"
            .. locator
            .. "\n"
            .. hashOptional(self.hasher, annotation.text)
    end
    local local_annotation_id = "ko-" .. self.hasher.sha256(identity_payload)
    return local_annotation_id, locator_fingerprint, quality
end

function KOReaderAnnotations:normalize(reader_document_id, annotation)
    if not isHighlight(annotation) then
        return nil, "not_highlight"
    end
    if type(annotation.text) ~= "string" or annotation.text == "" then
        return nil, "missing_text"
    end
    if annotation.note ~= nil and type(annotation.note) ~= "string" then
        return nil, "invalid_note"
    end

    local local_annotation_id, locator_fingerprint, identity_quality = self:identity(reader_document_id, annotation)
    return {
        local_annotation_id = local_annotation_id,
        locator_fingerprint = locator_fingerprint,
        identity_quality = identity_quality,
        datetime = annotation.datetime,
        datetime_updated = annotation.datetime_updated,
        text = annotation.text,
        note = annotation.note,
        text_hash = hashOptional(self.hasher, annotation.text),
        note_hash = hashOptional(self.hasher, annotation.note),
        page = annotation.page,
        pos0 = annotation.pos0,
        pos1 = annotation.pos1,
        drawer = annotation.drawer,
        color = annotation.color,
        chapter = annotation.chapter,
        pageno = annotation.pageno,
        pageref = annotation.pageref,
        ext = annotation.ext,
        sort_marker = sortMarker(annotation),
    }
end

function KOReaderAnnotations:scan(local_path, reader_document_id)
    if type(local_path) ~= "string" or local_path == "" then
        return nil, {
            kind = "path",
            retryable = false,
            message = "Managed document path is missing.",
        }
    end

    local ok, settings = pcall(self.doc_settings.open, self.doc_settings, local_path)
    if not ok or not settings then
        return nil, {
            kind = "sidecar",
            retryable = true,
            message = "KOReader sidecar could not be opened safely.",
        }
    end

    if not settings.source_candidate then
        return {
            authoritative = false,
            status = "no_sidecar",
            annotations = {},
            malformed = 0,
        }
    end

    local annotations
    local read_ok, read_result = pcall(settings.readSetting, settings, "annotations")
    if read_ok then annotations = read_result end
    if not read_ok then
        return nil, {
            kind = "sidecar",
            retryable = true,
            message = "KOReader annotations could not be read safely.",
        }
    end
    if type(annotations) ~= "table" then
        return {
            authoritative = false,
            status = "annotations_missing",
            source_candidate = settings.source_candidate,
            annotations = {},
            malformed = 0,
        }
    end

    local normalized = {}
    local malformed = 0
    local normalize_exceptions = 0
    for _, annotation in ipairs(annotations) do
        local normalize_ok, item, reason = pcall(
            self.normalize,
            self,
            reader_document_id,
            annotation
        )
        if not normalize_ok then
            malformed = malformed + 1
            normalize_exceptions = normalize_exceptions + 1
        elseif item then
            normalized[#normalized + 1] = item
        elseif reason ~= "not_highlight" then
            malformed = malformed + 1
        end
    end
    table.sort(normalized, function(a, b)
        if a.sort_marker == b.sort_marker then
            return a.local_annotation_id < b.local_annotation_id
        end
        return a.sort_marker > b.sort_marker
    end)

    return {
        authoritative = true,
        status = "ok",
        source_candidate = settings.source_candidate,
        annotations = normalized,
        malformed = malformed,
        normalize_exceptions = normalize_exceptions,
    }
end

KOReaderAnnotations._canonical = canonical
KOReaderAnnotations._locatorPayload = locatorPayload
KOReaderAnnotations._hashOptional = hashOptional

return KOReaderAnnotations
