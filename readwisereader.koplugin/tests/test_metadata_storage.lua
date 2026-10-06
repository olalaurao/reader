-- SPDX-License-Identifier: AGPL-3.0-only

local DB = require("storage/db")
local Migrations = require("storage/migrations")
local Documents = require("storage/documents")
local AnnotationMetadata = require("storage/annotation_metadata")
local RemoteHighlights = require("storage/remote_highlights")
local SQ3 = require("tests.support.lsqlite3_compat")

local function newDB()
    return DB:new{
        path=":memory:", sq3=SQ3,
        device={ canUseWAL=function() return false end },
    }
end

local function v3ToV4()
    local db = newDB()
    local conn = db.sq3.open(":memory:")
    db:_configure(conn)
    conn:exec(Migrations.SCHEMA_V1)
    conn:exec(Migrations.SCHEMA_V2)
    conn:exec(Migrations.SCHEMA_V3)
    conn:exec("PRAGMA user_version=3;")
    conn:exec("INSERT INTO documents(reader_id,title) VALUES ('doc-1','kept');")
    assert(Migrations.apply(conn, 3) == true)
    assert(tonumber(conn:rowexec("PRAGMA user_version;")) == 4)
    assert(conn:rowexec("SELECT title FROM documents WHERE reader_id='doc-1';") == "kept")
    assert(tonumber(conn:rowexec([[SELECT count(*) FROM sqlite_master WHERE type='table' AND name='annotation_metadata';]])) == 1)
    conn:close()
end

local function interruptedV4RollsBack()
    local db = newDB()
    local conn = db.sq3.open(":memory:")
    db:_configure(conn)
    conn:exec(Migrations.SCHEMA_V1)
    conn:exec(Migrations.SCHEMA_V2)
    conn:exec(Migrations.SCHEMA_V3)
    conn:exec("PRAGMA user_version=3;")
    conn:exec("INSERT INTO documents(reader_id,title) VALUES ('survivor','before-v4');")

    local original_exec = conn.exec
    local injected = false
    conn.exec = function(self, sql)
        if not injected and sql == Migrations.SCHEMA_V4 then
            injected = true
            error("synthetic v4 migration failure")
        end
        return original_exec(self, sql)
    end
    local ok = pcall(Migrations.apply, conn, 3)
    conn.exec = original_exec
    assert(ok == false)
    assert(tonumber(conn:rowexec("PRAGMA user_version;")) == 3)
    assert(conn:rowexec("SELECT title FROM documents WHERE reader_id='survivor';") == "before-v4")
    assert(tonumber(conn:rowexec([[SELECT count(*) FROM sqlite_master WHERE type='table' AND name='annotation_metadata';]])) == 0)
    local stmt = conn:prepare("SELECT count(*) FROM pragma_table_info('documents') WHERE name='remote_notes';")
    local row = stmt:step(); stmt:close()
    assert(tonumber(row[1]) == 0)
    conn:close()
end

local function repositoriesRoundTrip()
    local db = newDB(); db:open()
    local docs = Documents:new{db=db}
    local stored = docs:upsertRemote({
        id="doc-1", category="article", location="later", title="Title",
        notes="document note", tags={"beta","alpha"}, raw_source_available=false,
    }, 1)
    assert(stored.remote_notes == "document note")
    assert(table.concat(stored.remote_tags,"|") == "alpha|beta")

    local conn = db:getConnection()
    conn:exec([[
        INSERT INTO annotation_links(local_annotation_id, reader_document_id, locator_fingerprint)
        VALUES ('ann-1','doc-1','loc');
    ]])
    local meta = AnnotationMetadata:new{db=db}
    meta:setPendingTags("ann-1", {"alpha"}, {"alpha","kindle"}, 2)
    local pending = meta:getById("ann-1")
    assert(table.concat(pending.last_synced_tags,"|") == "alpha")
    assert(table.concat(pending.pending_tags,"|") == "alpha|kindle")
    meta:markTagsSynced("ann-1", {"alpha","kindle"}, 3)
    assert(meta:getById("ann-1").pending_tags == nil)

    local remote = RemoteHighlights:new{db=db}
    assert(remote:upsertMany({{
        id="hl-1", parent_id="doc-1", content="text", notes="note", tags={"z","a"},
    }}, 4) == 1)
    local hl = remote:getByRemoteId("hl-1")
    assert(table.concat(hl.tags,"|") == "a|z")
    db:close()
end

return function()
    v3ToV4()
    interruptedV4RollsBack()
    repositoriesRoundTrip()
end
