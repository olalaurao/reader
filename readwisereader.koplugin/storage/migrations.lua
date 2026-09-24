-- SPDX-License-Identifier: AGPL-3.0-only

local Migrations = {}

Migrations.SCHEMA_VERSION = 2

Migrations.SCHEMA_V1 = [[
CREATE TABLE IF NOT EXISTS documents (
    reader_id TEXT PRIMARY KEY,
    parent_id TEXT,
    category TEXT,
    location TEXT,
    title TEXT,
    author TEXT,
    site_name TEXT,
    source_url TEXT,
    local_path TEXT UNIQUE,
    local_format TEXT,
    download_strategy TEXT,
    remote_updated_at TEXT,
    remote_saved_at TEXT,
    remote_last_moved_at TEXT,
    local_content_hash TEXT,
    remote_content_fingerprint TEXT,
    raw_source_available INTEGER NOT NULL DEFAULT 0,
    is_managed INTEGER NOT NULL DEFAULT 1,
    is_local_present INTEGER NOT NULL DEFAULT 0,
    last_materialized_at INTEGER,
    last_seen_remote_at INTEGER,
    last_sync_error TEXT
);

CREATE TABLE IF NOT EXISTS annotation_links (
    local_annotation_id TEXT PRIMARY KEY,
    reader_document_id TEXT NOT NULL,
    reader_highlight_document_id TEXT,
    readwise_v2_highlight_id INTEGER,
    created_remote INTEGER NOT NULL DEFAULT 0,
    local_created_at TEXT,
    locator_fingerprint TEXT NOT NULL,
    original_text_hash TEXT,
    last_text_hash TEXT,
    last_note_hash TEXT,
    last_synced_text TEXT,
    last_synced_note TEXT,
    remote_updated_marker TEXT,
    local_deleted_at INTEGER,
    sync_state TEXT NOT NULL DEFAULT 'local_only',
    last_sync_error TEXT,
    FOREIGN KEY(reader_document_id) REFERENCES documents(reader_id)
);

CREATE TABLE IF NOT EXISTS queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    idempotency_key TEXT NOT NULL UNIQUE,
    operation TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    local_annotation_id TEXT,
    reader_document_id TEXT,
    reader_highlight_document_id TEXT,
    readwise_v2_highlight_id INTEGER,
    payload_json TEXT NOT NULL,
    payload_hash TEXT NOT NULL,
    status TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    available_after INTEGER,
    last_attempt_at INTEGER,
    last_error_kind TEXT,
    last_error_message TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sync_meta (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE INDEX IF NOT EXISTS idx_documents_location ON documents(location);
CREATE INDEX IF NOT EXISTS idx_documents_category ON documents(category);
CREATE INDEX IF NOT EXISTS idx_documents_updated ON documents(remote_updated_at);
CREATE INDEX IF NOT EXISTS idx_annotation_links_document ON annotation_links(reader_document_id);
CREATE INDEX IF NOT EXISTS idx_queue_status_available ON queue(status, available_after);
CREATE INDEX IF NOT EXISTS idx_queue_document ON queue(reader_document_id);
]]

Migrations.SCHEMA_V2 = [[
ALTER TABLE documents ADD COLUMN materialized_remote_updated_at TEXT;
ALTER TABLE documents ADD COLUMN content_refresh_pending INTEGER NOT NULL DEFAULT 0;
ALTER TABLE documents ADD COLUMN content_refresh_remote_updated_at TEXT;
ALTER TABLE documents ADD COLUMN content_refresh_detected_at INTEGER;
CREATE INDEX IF NOT EXISTS idx_documents_refresh_pending
    ON documents(content_refresh_pending);
]]

function Migrations.currentVersion(conn)
    return tonumber(conn:rowexec("PRAGMA user_version;")) or 0
end

function Migrations.apply(conn, from_version)
    from_version = tonumber(from_version) or 0
    if from_version > Migrations.SCHEMA_VERSION then
        error(string.format(
            "database schema %d is newer than supported schema %d",
            from_version,
            Migrations.SCHEMA_VERSION
        ))
    end
    if from_version == Migrations.SCHEMA_VERSION then
        return false
    end

    conn:exec("BEGIN IMMEDIATE;")
    local ok, err = pcall(function()
        if from_version < 1 then
            conn:exec(Migrations.SCHEMA_V1)
        end
        if from_version < 2 then
            conn:exec(Migrations.SCHEMA_V2)
        end
        conn:exec(string.format("PRAGMA user_version=%d;", Migrations.SCHEMA_VERSION))
    end)

    if ok then
        conn:exec("COMMIT;")
        return true
    end

    pcall(conn.exec, conn, "ROLLBACK;")
    error(err)
end

return Migrations
