-- SPDX-License-Identifier: AGPL-3.0-only

local Filenames = {}

local DEFAULT_MAX_FILENAME_BYTES = 180

local function truncateUtf8Bytes(value, max_bytes)
    value = tostring(value or "")
    max_bytes = math.max(tonumber(max_bytes) or 0, 0)
    if #value <= max_bytes then
        return value
    end

    local index = 1
    local last_complete = 0
    while index <= #value do
        local byte = value:byte(index)
        local length = 1
        if byte >= 0xC2 and byte <= 0xDF then
            length = 2
        elseif byte >= 0xE0 and byte <= 0xEF then
            length = 3
        elseif byte >= 0xF0 and byte <= 0xF4 then
            length = 4
        end

        if index + length - 1 > max_bytes then
            break
        end

        local valid = true
        for offset = 1, length - 1 do
            local continuation = value:byte(index + offset)
            if not continuation or continuation < 0x80 or continuation > 0xBF then
                valid = false
                break
            end
        end
        if not valid then
            length = 1
        end

        last_complete = index + length - 1
        index = last_complete + 1
    end

    return value:sub(1, last_complete)
end

local function normalizeTitle(title)
    title = type(title) == "string" and title or ""
    title = title:gsub("[%z\1-\31\127]", " ")
    title = title:gsub("[\\/:*?\"<>|]", "_")
    title = title:gsub("%.%.+", "_")
    title = title:gsub("%s+", " ")
    title = title:gsub("^%s+", ""):gsub("[%s%.]+$", "")
    if title == "" then
        return "Untitled"
    end
    return title
end

local function idFingerprint(reader_id)
    local hash = 0
    for index = 1, #reader_id do
        hash = (hash * 131 + reader_id:byte(index)) % 4294967296
    end
    local high = math.floor(hash / 65536)
    local low = hash % 65536
    return string.format("%04x%04x", high, low)
end

local function idLabel(reader_id)
    local safe = reader_id:gsub("[^A-Za-z0-9_-]", "")
    if safe == "" then
        safe = "id"
    end
    return safe:sub(1, 12) .. "-" .. idFingerprint(reader_id)
end

function Filenames.build(title, reader_id, extension, max_bytes)
    assert(type(reader_id) == "string" and reader_id ~= "", "reader_id is required")
    extension = tostring(extension or "html"):lower():gsub("[^a-z0-9]", "")
    if extension == "" then
        extension = "html"
    end

    max_bytes = tonumber(max_bytes) or DEFAULT_MAX_FILENAME_BYTES
    local suffix = "--rw-" .. idLabel(reader_id) .. "." .. extension
    local title_budget = math.max(max_bytes - #suffix, 1)
    local safe_title = truncateUtf8Bytes(normalizeTitle(title), title_budget)
    safe_title = safe_title:gsub("[%s%.]+$", "")
    if safe_title == "" then
        safe_title = "Untitled"
        safe_title = truncateUtf8Bytes(safe_title, title_budget)
    end

    return safe_title .. suffix
end

function Filenames.joinUnderRoot(root, subdirectory, filename)
    assert(type(root) == "string" and root ~= "", "root is required")
    assert(type(subdirectory) == "string" and subdirectory ~= "", "subdirectory is required")
    assert(type(filename) == "string" and filename ~= "", "filename is required")
    assert(not subdirectory:find("/", 1, true) and not subdirectory:find("\\", 1, true), "subdirectory must be one path component")
    assert(not filename:find("/", 1, true) and not filename:find("\\", 1, true), "filename must be one path component")

    root = root:gsub("/+$", "")
    return root .. "/" .. subdirectory .. "/" .. filename
end

Filenames.DEFAULT_MAX_FILENAME_BYTES = DEFAULT_MAX_FILENAME_BYTES
Filenames._truncateUtf8Bytes = truncateUtf8Bytes
Filenames._normalizeTitle = normalizeTitle
Filenames._idFingerprint = idFingerprint

return Filenames
