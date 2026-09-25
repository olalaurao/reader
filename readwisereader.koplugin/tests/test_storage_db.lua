-- SPDX-License-Identifier: AGPL-3.0-only

local DB = require("storage/db")
local Migrations = require("storage/migrations")
local SQ3 = require("tests.support.lsqlite3_compat")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected truthy value")
    end
end

local function newMemoryDB()
    return DB:new{
        path = ":memory:",
        sq3 = SQ3,
        device = {
            canUseWAL = function()
                return false
            end,
        },
    }
end

local function testFreshSchema()
    local db = newMemoryDB()
    local conn = db:open()

    assertEqual(db:getSchemaVersion(), Migrations.SCHEMA_VERSION, "fresh schema version")
    assertEqual(tonumber(conn:rowexec("PRAGMA foreign_keys;")), 1, "foreign keys enabled")

    for _, table_name in ipairs({
        "documents", "annotation_links", "queue", "sync_meta", "remote_highlights",
    }) do
        local stmt = conn:prepare("SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?;")
        local row = stmt:reset():bind(table_name):step()
        stmt:close()
        assertEqual(tonumber(row[1]), 1, "missing table " .. table_name)
    end

    db:close()
end

local function testQueueUniquenessAndForeignKey()
    local db = newMemoryDB()
    local conn = db:open()

    local doc = conn:prepare("INSERT INTO documents(reader_id) VALUES (?);")
    doc:reset():bind("doc-1"):step()
    doc:close()

    local insert = conn:prepare([[
        INSERT INTO queue(
            idempotency_key, operation, entity_type, reader_document_id,
            payload_json, payload_hash, status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
    ]])
    insert:reset():bind("same-key", "noop", "document", "doc-1", "{}", "hash", "pending", 1, 1):step()
    local ok_duplicate = pcall(function()
        insert:reset():clearbind():bind("same-key", "noop", "document", "doc-1", "{}", "hash", "pending", 1, 1):step()
    end)
    insert:close()
    assertEqual(ok_duplicate, false, "queue idempotency key must be unique")

    local ann = conn:prepare([[
        INSERT INTO annotation_links(local_annotation_id, reader_document_id, locator_fingerprint)
        VALUES (?, ?, ?);
    ]])
    local ok_fk = pcall(function()
        ann:reset():bind("ann-1", "missing-doc", "loc"):step()
    end)
    ann:close()
    assertEqual(ok_fk, false, "annotation link must enforce document foreign key")

    db:close()
end

local function testV1ToCurrentMigration()
    local db = newMemoryDB()
    local conn = db.sq3.open(":memory:")
    db:_configure(conn)
    conn:exec(Migrations.SCHEMA_V1)
    conn:exec("PRAGMA user_version=1;")
    conn:exec([[
        INSERT INTO documents(
            reader_id, category, location, remote_updated_at,
            local_path, local_format, is_local_present
        ) VALUES (
            'doc-old', 'article', 'new', 'u-old',
            '/Readwise/old.html', 'html', 1
        );
    ]])

    local changed = Migrations.apply(conn, 1)
    assertEqual(changed, true)
    assertEqual(
        tonumber(conn:rowexec("PRAGMA user_version;")),
        Migrations.SCHEMA_VERSION,
        "v1 database must migrate to the current schema"
    )

    local stmt = conn:prepare([[
        SELECT materialized_remote_updated_at,
               content_refresh_pending,
               content_refresh_remote_updated_at,
               content_refresh_detected_at
        FROM documents WHERE reader_id='doc-old';
    ]])
    local row = stmt:step()
    stmt:close()
    assertEqual(row[1], nil,
        "migration must not invent a materialized revision for legacy files")
    assertEqual(tonumber(row[2]), 0)
    assertEqual(row[3], nil)
    assertEqual(row[4], nil)
    assertEqual(tonumber(conn:rowexec([[
        SELECT count(*) FROM sqlite_master
        WHERE type='table' AND name='remote_highlights';
    ]])), 1, "v1 migration must create the v3 remote highlight cache")
    conn:close()
end

local function testV2ToV3MigrationPreservesData()
    local db = newMemoryDB()
    local conn = db.sq3.open(":memory:")
    db:_configure(conn)
    conn:exec(Migrations.SCHEMA_V1)
    conn:exec(Migrations.SCHEMA_V2)
    conn:exec("PRAGMA user_version=2;")
    conn:exec([[
        INSERT INTO documents(
            reader_id, category, location, local_path,
            local_format, is_local_present
        ) VALUES (
            'doc-v2', 'epub', 'later', '/Readwise/v2.epub', 'epub', 1
        );
    ]])
    conn:exec([[
        INSERT INTO sync_meta(key, value)
        VALUES ('document_watermark', 'keep-me');
    ]])

    local changed = Migrations.apply(conn, 2)
    assertEqual(changed, true)
    assertEqual(
        tonumber(conn:rowexec("PRAGMA user_version;")),
        Migrations.SCHEMA_VERSION,
        "v2 database must migrate to v3"
    )
    assertEqual(tonumber(conn:rowexec(
        "SELECT count(*) FROM documents WHERE reader_id='doc-v2';"
    )), 1, "v2 document rows must survive v3 migration")
    assertEqual(conn:rowexec(
        "SELECT value FROM sync_meta WHERE key='document_watermark';"
    ), "keep-me", "v2 sync metadata must survive v3 migration")
    assertEqual(tonumber(conn:rowexec([[
        SELECT count(*) FROM sqlite_master
        WHERE type='table' AND name='remote_highlights';
    ]])), 1, "v3 cache table must exist after v2 migration")
    conn:close()
end

local function testBackupCopySemantics()
    local copied_from, copied_to
    local checkpoint_calls = 0
    local wal_conn = {
        rowexec = function(_, sql)
            assertEqual(sql, "PRAGMA journal_mode;")
            return "wal"
        end,
        exec = function(_, sql)
            assertEqual(sql, "PRAGMA wal_checkpoint(FULL);")
            checkpoint_calls = checkpoint_calls + 1
        end,
    }
    local db = DB:new{
        path = "/tmp/readwisereader.sqlite3",
        sq3 = SQ3,
        device = { canUseWAL = function() return true end },
        copy_file = function(from, to)
            assertEqual(checkpoint_calls, 1,
                "WAL checkpoint must complete before migration backup copy")
            copied_from, copied_to = from, to
            -- KOReader ffiUtil.copyFile returns nil on success.
            return nil
        end,
    }
    local ok, err = pcall(function()
        db:_backupBeforeMigration(wal_conn, 2)
    end)
    assertEqual(ok, true,
        "nil from KOReader copyFile must mean backup success")
    assertEqual(err, nil)
    assertEqual(checkpoint_calls, 1)
    assertEqual(copied_from, "/tmp/readwisereader.sqlite3")
    assertEqual(copied_to, "/tmp/readwisereader.sqlite3.bak")

    local truncate_checkpoint_calls = 0
    local truncate_conn = {
        rowexec = function() return "truncate" end,
        exec = function()
            truncate_checkpoint_calls = truncate_checkpoint_calls + 1
        end,
    }
    db:_backupBeforeMigration(truncate_conn, 2)
    assertEqual(truncate_checkpoint_calls, 0,
        "non-WAL migration backup must not issue a WAL checkpoint")

    local failing = DB:new{
        path = "/tmp/readwisereader.sqlite3",
        sq3 = SQ3,
        device = { canUseWAL = function() return false end },
        copy_file = function()
            return "synthetic copy failure"
        end,
    }
    local failed, message = pcall(function()
        failing:_backupBeforeMigration(truncate_conn, 2)
    end)
    assertEqual(failed, false,
        "non-nil KOReader copyFile return must be treated as failure")
    assertTrue(tostring(message):find("synthetic copy failure", 1, true) ~= nil)

    local checkpoint_failure = DB:new{
        path = "/tmp/readwisereader.sqlite3",
        sq3 = SQ3,
        device = { canUseWAL = function() return true end },
        copy_file = function()
            error("backup copy must not run after checkpoint failure")
        end,
    }
    local checkpoint_ok, checkpoint_err = pcall(function()
        checkpoint_failure:_backupBeforeMigration({
            rowexec = function() return "wal" end,
            exec = function() error("synthetic checkpoint failure") end,
        }, 2)
    end)
    assertEqual(checkpoint_ok, false,
        "failed WAL checkpoint must abort migration backup")
    assertTrue(tostring(checkpoint_err):find(
        "synthetic checkpoint failure", 1, true
    ) ~= nil)
end


local function testInterruptedMigrationRollback()
    local db = newMemoryDB()
    local conn = db.sq3.open(":memory:")
    db:_configure(conn)
    conn:exec(Migrations.SCHEMA_V1)
    conn:exec("PRAGMA user_version=1;")
    conn:exec("INSERT INTO documents(reader_id, title) VALUES ('survivor', 'before');")

    local original_exec = conn.exec
    local injected = false
    conn.exec = function(self, sql)
        if not injected and sql == Migrations.SCHEMA_V2 then
            injected = true
            error("synthetic power-loss migration failure")
        end
        return original_exec(self, sql)
    end

    local ok = pcall(Migrations.apply, conn, 1)
    assertEqual(ok, false, "interrupted migration must fail")
    conn.exec = original_exec
    assertEqual(tonumber(conn:rowexec("PRAGMA user_version;")), 1,
        "failed migration must preserve previous schema version")
    assertEqual(tonumber(conn:rowexec(
        "SELECT count(*) FROM documents WHERE reader_id='survivor' AND title='before';"
    )), 1, "failed migration must preserve pre-existing rows")
    local column = conn:prepare(
        "SELECT count(*) FROM pragma_table_info('documents') WHERE name='materialized_remote_updated_at';"
    )
    local row = column:step()
    column:close()
    assertEqual(tonumber(row[1]), 0,
        "failed migration must roll back partially-added v2 columns")
    conn:close()
end


local function testInterruptedV3MigrationRollback()
    local db = newMemoryDB()
    local conn = db.sq3.open(":memory:")
    db:_configure(conn)
    conn:exec(Migrations.SCHEMA_V1)
    conn:exec(Migrations.SCHEMA_V2)
    conn:exec("PRAGMA user_version=2;")
    conn:exec("INSERT INTO documents(reader_id, title) VALUES ('v2-survivor', 'before-v3');")

    local original_exec = conn.exec
    local injected = false
    conn.exec = function(self, sql)
        if not injected and sql == Migrations.SCHEMA_V3 then
            injected = true
            error("synthetic v3 migration failure")
        end
        return original_exec(self, sql)
    end

    local ok = pcall(Migrations.apply, conn, 2)
    assertEqual(ok, false, "interrupted v3 migration must fail")
    conn.exec = original_exec
    assertEqual(tonumber(conn:rowexec("PRAGMA user_version;")), 2,
        "failed v3 migration must preserve schema version 2")
    assertEqual(tonumber(conn:rowexec(
        "SELECT count(*) FROM documents WHERE reader_id='v2-survivor' AND title='before-v3';"
    )), 1, "failed v3 migration must preserve existing rows")
    assertEqual(tonumber(conn:rowexec([[
        SELECT count(*) FROM sqlite_master
        WHERE type='table' AND name='remote_highlights';
    ]])), 0, "failed v3 migration must roll back the cache table")
    conn:close()
end

local function testTransactionRollback()
    local db = newMemoryDB()
    local conn = db:open()

    local ok = pcall(function()
        db:transaction(function(tx)
            tx:exec("INSERT INTO sync_meta(key, value) VALUES ('rolled-back', 'yes');")
            error("force rollback")
        end)
    end)
    assertEqual(ok, false, "transaction should propagate callback error")
    assertEqual(tonumber(conn:rowexec("SELECT count(*) FROM sync_meta WHERE key='rolled-back';")), 0, "rollback should remove write")

    db:close()
end

local function testMigrationRollbackSignal()
    local calls = {}
    local fake = {
        rowexec = function()
            return 0
        end,
        exec = function(_, sql)
            calls[#calls + 1] = sql
            if sql == Migrations.SCHEMA_V1 then
                error("synthetic migration failure")
            end
            return true
        end,
    }

    local ok = pcall(Migrations.apply, fake, 0)
    assertEqual(ok, false, "migration failure should propagate")
    assertEqual(calls[1], "BEGIN IMMEDIATE;", "migration should start transaction")
    assertEqual(calls[#calls], "ROLLBACK;", "migration should roll back")
end

return function()
    assertTrue(Migrations.SCHEMA_VERSION >= 1)
    testFreshSchema()
    testQueueUniquenessAndForeignKey()
    testV1ToCurrentMigration()
    testV2ToV3MigrationPreservesData()
    testBackupCopySemantics()
    testInterruptedMigrationRollback()
    testInterruptedV3MigrationRollback()
    testTransactionRollback()
    testMigrationRollbackSignal()
end
