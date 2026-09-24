-- SPDX-License-Identifier: AGPL-3.0-only

local Documents = {}
Documents.__index = Documents

local SELECT_COLUMNS = [[
reader_id, parent_id, category, location, title, author, site_name, source_url,
local_path, local_format, download_strategy, remote_updated_at, remote_saved_at,
remote_last_moved_at, local_content_hash, remote_content_fingerprint,
raw_source_available, is_managed, is_local_present, last_materialized_at,
last_seen_remote_at, last_sync_error, materialized_remote_updated_at,
content_refresh_pending, content_refresh_remote_updated_at,
content_refresh_detected_at
]]

local function rowToDocument(row)
    if not row then
        return nil
    end
    return {
        reader_id = row[1],
        parent_id = row[2],
        category = row[3],
        location = row[4],
        title = row[5],
        author = row[6],
        site_name = row[7],
        source_url = row[8],
        local_path = row[9],
        local_format = row[10],
        download_strategy = row[11],
        remote_updated_at = row[12],
        remote_saved_at = row[13],
        remote_last_moved_at = row[14],
        local_content_hash = row[15],
        remote_content_fingerprint = row[16],
        raw_source_available = tonumber(row[17]) == 1,
        is_managed = tonumber(row[18]) == 1,
        is_local_present = tonumber(row[19]) == 1,
        last_materialized_at = row[20],
        last_seen_remote_at = row[21],
        last_sync_error = row[22],
        materialized_remote_updated_at = row[23],
        content_refresh_pending = tonumber(row[24]) == 1,
        content_refresh_remote_updated_at = row[25],
        content_refresh_detected_at = row[26],
    }
end

function Documents:new(options)
    options = options or {}
    return setmetatable({
        db = assert(options.db, "db is required"),
    }, self)
end

function Documents:upsertRemote(document, seen_at)
    assert(type(document) == "table", "document is required")
    assert(type(document.id) == "string" and document.id ~= "", "document.id is required")

    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        INSERT INTO documents(
            reader_id, parent_id, category, location, title, author, site_name,
            source_url, remote_updated_at, remote_saved_at, remote_last_moved_at,
            raw_source_available, last_seen_remote_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(reader_id) DO UPDATE SET
            parent_id = excluded.parent_id,
            category = excluded.category,
            location = excluded.location,
            title = excluded.title,
            author = excluded.author,
            site_name = excluded.site_name,
            source_url = excluded.source_url,
            remote_updated_at = excluded.remote_updated_at,
            remote_saved_at = excluded.remote_saved_at,
            remote_last_moved_at = excluded.remote_last_moved_at,
            raw_source_available = excluded.raw_source_available,
            last_seen_remote_at = excluded.last_seen_remote_at;
    ]])

    stmt:bind(
        document.id,
        document.parent_id,
        document.category,
        document.location,
        document.title,
        document.author,
        document.site_name,
        document.source_url,
        document.updated_at,
        document.saved_at,
        document.last_moved_at,
        document.raw_source_available and 1 or 0,
        seen_at
    ):step()
    stmt:close()
    return self:getById(document.id)
end

function Documents:getById(reader_id)
    local conn = self.db:getConnection()
    local stmt = conn:prepare("SELECT " .. SELECT_COLUMNS .. " FROM documents WHERE reader_id = ?;")
    local row = stmt:bind(reader_id):step()
    stmt:close()
    return rowToDocument(row)
end

function Documents:getByLocalPath(local_path)
    if type(local_path) ~= "string" or local_path == "" then return nil end
    local conn = self.db:getConnection()
    local stmt = conn:prepare("SELECT " .. SELECT_COLUMNS .. " FROM documents WHERE local_path = ?;")
    local row = stmt:bind(local_path):step()
    stmt:close()
    return rowToDocument(row)
end

function Documents:setLocalState(reader_id, state)
    state = state or {}
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE documents SET
            local_path = ?,
            local_format = ?,
            download_strategy = ?,
            local_content_hash = ?,
            remote_content_fingerprint = ?,
            is_local_present = ?,
            last_materialized_at = ?,
            last_sync_error = ?,
            materialized_remote_updated_at = ?,
            content_refresh_pending = ?,
            content_refresh_remote_updated_at = ?,
            content_refresh_detected_at = ?
        WHERE reader_id = ?;
    ]])
    stmt:bind(
        state.local_path,
        state.local_format,
        state.download_strategy,
        state.local_content_hash,
        state.remote_content_fingerprint,
        state.is_local_present and 1 or 0,
        state.last_materialized_at,
        state.last_sync_error,
        state.materialized_remote_updated_at,
        state.content_refresh_pending and 1 or 0,
        state.content_refresh_remote_updated_at,
        state.content_refresh_detected_at,
        reader_id
    ):step()
    stmt:close()
end

function Documents:markContentRefreshPending(reader_id, remote_updated_at, detected_at)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE documents SET
            content_refresh_pending = 1,
            content_refresh_remote_updated_at = ?,
            content_refresh_detected_at = ?
        WHERE reader_id = ?;
    ]])
    stmt:bind(remote_updated_at, detected_at, reader_id):step()
    stmt:close()
    return self:getById(reader_id)
end

function Documents:clearContentRefreshPending(reader_id)
    local conn = self.db:getConnection()
    local stmt = conn:prepare([[
        UPDATE documents SET
            content_refresh_pending = 0,
            content_refresh_remote_updated_at = NULL,
            content_refresh_detected_at = NULL
        WHERE reader_id = ?;
    ]])
    stmt:bind(reader_id):step()
    stmt:close()
    return self:getById(reader_id)
end

function Documents:countContentRefreshPending()
    local conn = self.db:getConnection()
    return tonumber(conn:rowexec(
        "SELECT count(*) FROM documents WHERE content_refresh_pending = 1;"
    )) or 0
end

function Documents:listContentRefreshPending()
    local conn = self.db:getConnection()
    local stmt = conn:prepare(
        "SELECT " .. SELECT_COLUMNS
        .. " FROM documents WHERE content_refresh_pending = 1"
        .. " ORDER BY content_refresh_detected_at, reader_id;"
    )
    local documents = {}
    while true do
        local row = stmt:step()
        if not row then break end
        documents[#documents + 1] = rowToDocument(row)
    end
    stmt:close()
    return documents
end

function Documents:setLocation(reader_id, location)
    local conn = self.db:getConnection()
    local stmt = conn:prepare("UPDATE documents SET location = ? WHERE reader_id = ?;")
    stmt:bind(location, reader_id):step()
    stmt:close()
    return self:getById(reader_id)
end

function Documents:setLastSyncError(reader_id, error_kind)
    local conn = self.db:getConnection()
    local stmt = conn:prepare("UPDATE documents SET last_sync_error = ? WHERE reader_id = ?;")
    stmt:bind(error_kind, reader_id):step()
    stmt:close()
end

function Documents:listManaged()
    local conn = self.db:getConnection()
    local stmt = conn:prepare(
        "SELECT " .. SELECT_COLUMNS .. " FROM documents WHERE is_managed = 1 ORDER BY reader_id;"
    )
    local documents = {}
    while true do
        local row = stmt:step()
        if not row then break end
        documents[#documents + 1] = rowToDocument(row)
    end
    stmt:close()
    return documents
end

function Documents:listManagedLocal()
    local conn = self.db:getConnection()
    local stmt = conn:prepare(
        "SELECT " .. SELECT_COLUMNS
        .. " FROM documents"
        .. " WHERE is_managed = 1"
        .. " AND is_local_present = 1"
        .. " AND local_path IS NOT NULL"
        .. " AND local_path <> ''"
        .. " ORDER BY reader_id;"
    )
    local documents = {}
    while true do
        local row = stmt:step()
        if not row then break end
        documents[#documents + 1] = rowToDocument(row)
    end
    stmt:close()
    return documents
end

function Documents:count()
    return tonumber(self.db:getConnection():rowexec("SELECT count(*) FROM documents;")) or 0
end

Documents._rowToDocument = rowToDocument

return Documents
