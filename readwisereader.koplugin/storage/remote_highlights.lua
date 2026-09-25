-- SPDX-License-Identifier: AGPL-3.0-only

local RemoteHighlights = {}
RemoteHighlights.__index = RemoteHighlights

local function rowToHighlight(row)
    if not row then return nil end
    local notes = row[4]
    return {
        id = row[1],
        parent_id = row[2],
        content = row[3],
        notes = notes,
        note_present = type(notes) == "string" and notes ~= "",
        created_at = row[5],
        updated_at = row[6],
        highlight_offset = row[7],
        highlight_location = row[8],
        last_seen_at = tonumber(row[9]),
    }
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

function RemoteHighlights:new(options)
    options = options or {}
    return setmetatable({
        db = assert(options.db, "db is required"),
    }, self)
end

function RemoteHighlights:upsertMany(highlights, seen_at)
    highlights = highlights or {}
    seen_at = tonumber(seen_at) or os.time()

    return self.db:transaction(function(conn)
        local stmt = conn:prepare([[
            INSERT INTO remote_highlights(
                reader_highlight_document_id, reader_document_id,
                content, notes, created_at, updated_at,
                highlight_offset, highlight_location, last_seen_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(reader_highlight_document_id) DO UPDATE SET
                reader_document_id = excluded.reader_document_id,
                content = excluded.content,
                notes = excluded.notes,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                highlight_offset = excluded.highlight_offset,
                highlight_location = excluded.highlight_location,
                last_seen_at = excluded.last_seen_at;
        ]])

        local written = 0
        for _, remote in ipairs(highlights) do
            if type(remote) == "table"
                and type(remote.id) == "string" and remote.id ~= ""
                and type(remote.parent_id) == "string"
                and remote.parent_id ~= "" then
                stmt:reset():clearbind():bind(
                    remote.id,
                    remote.parent_id,
                    remote.content,
                    remote.notes,
                    remote.created_at,
                    remote.updated_at,
                    remote.highlight_offset,
                    remote.highlight_location,
                    seen_at
                ):step()
                written = written + 1
            end
        end
        stmt:close()
        return written
    end)
end

function RemoteHighlights:listByParent(reader_document_id)
    if type(reader_document_id) ~= "string" or reader_document_id == "" then
        return {}
    end

    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        SELECT
            reader_highlight_document_id, reader_document_id,
            content, notes, created_at, updated_at,
            highlight_offset, highlight_location, last_seen_at
        FROM remote_highlights
        WHERE reader_document_id = ?;
    ]])
    local result = {}
    stmt:bind(reader_document_id)
    while true do
        local row = stmt:step()
        if not row then break end
        result[#result + 1] = rowToHighlight(row)
    end
    stmt:close()
    table.sort(result, stableSort)
    return result
end

function RemoteHighlights:count()
    local conn = self.db:getConnection()
    return tonumber(conn:rowexec("SELECT count(*) FROM remote_highlights;")) or 0
end

return RemoteHighlights
