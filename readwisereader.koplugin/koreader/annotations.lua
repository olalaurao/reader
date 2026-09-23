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
        return "d" .. string.format("%.17g", value)
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
        return hasher.digest("\0nil")
    end
    return hasher.digest("\1" .. tostring(value))
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

    local locator_fingerprint = self.hasher.digest(canonical(locatorPayload(annotation)))
    local local_annotation_id = "ko-" .. self.hasher.digest(
        reader_document_id
            .. "\n"
            .. tostring(annotation.datetime or "")
            .. "\n"
            .. locator_fingerprint
    )
    return local_annotation_id, locator_fingerprint
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

    local local_annotation_id, locator_fingerprint = self:identity(reader_document_id, annotation)
    return {
        local_annotation_id = local_annotation_id,
        locator_fingerprint = locator_fingerprint,
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
    for _, annotation in ipairs(annotations) do
        local item, reason = self:normalize(reader_document_id, annotation)
        if item then
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
    }
end

KOReaderAnnotations._canonical = canonical
KOReaderAnnotations._locatorPayload = locatorPayload
KOReaderAnnotations._hashOptional = hashOptional

return KOReaderAnnotations
