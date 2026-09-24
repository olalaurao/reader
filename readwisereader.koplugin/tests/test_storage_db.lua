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

    for _, table_name in ipairs({ "documents", "annotation_links", "queue", "sync_meta" }) do
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

local function testV1ToV2Migration()
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
        2,
        "v1 database must migrate to v2"
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
    conn:close()
end

local function testBackupCopySemantics()
    local copied_from, copied_to
    local db = DB:new{
        path = "/tmp/readwisereader.sqlite3",
        sq3 = SQ3,
        device = { canUseWAL = function() return false end },
        copy_file = function(from, to)
            copied_from, copied_to = from, to
            -- KOReader ffiUtil.copyFile returns nil on success.
            return nil
        end,
    }
    local ok, err = pcall(function()
        db:_backupBeforeMigration(1)
    end)
    assertEqual(ok, true,
        "nil from KOReader copyFile must mean backup success")
    assertEqual(err, nil)
    assertEqual(copied_from, "/tmp/readwisereader.sqlite3")
    assertEqual(copied_to, "/tmp/readwisereader.sqlite3.bak")

    local failing = DB:new{
        path = "/tmp/readwisereader.sqlite3",
        sq3 = SQ3,
        device = { canUseWAL = function() return false end },
        copy_file = function()
            return "synthetic copy failure"
        end,
    }
    local failed, message = pcall(function()
        failing:_backupBeforeMigration(1)
    end)
    assertEqual(failed, false,
        "non-nil KOReader copyFile return must be treated as failure")
    assertTrue(tostring(message):find("synthetic copy failure", 1, true) ~= nil)
end

local function copyFileForTest(from, to)
    local source = assert(io.open(from, "rb"))
    local bytes = source:read("*a")
    source:close()
    local target = assert(io.open(to, "wb"))
    assert(target:write(bytes))
    target:close()
    -- Match KOReader ffiUtil.copyFile: nil means success.
    return nil
end

local function testFileBackedMigrationBackup()
    local path = os.tmpname()
    os.remove(path)
    os.remove(path .. ".bak")

    -- Seed a real v1 file and close it, as an older installed plugin would.
    local seed = SQ3.open(path)
    seed:exec(Migrations.SCHEMA_V1)
    seed:exec("PRAGMA user_version=1;")
    seed:exec([[
        INSERT INTO documents(
            reader_id, category, location, title, remote_updated_at,
            local_path, local_format, is_local_present
        ) VALUES (
            'persisted-v1', 'article', 'new', 'Before migration', 'u1',
            '/Readwise/persisted.html', 'html', 1
        );
    ]])
    seed:close()

    local db = DB:new{
        path = path,
        sq3 = SQ3,
        device = { canUseWAL = function() return false end },
        copy_file = copyFileForTest,
    }
    assertEqual(db:getSchemaVersion(), Migrations.SCHEMA_VERSION)
    local migrated = db:getConnection()
    assertEqual(
        tonumber(migrated:rowexec(
            "SELECT count(*) FROM documents WHERE reader_id='persisted-v1';"
        )),
        1,
        "migration must preserve existing document rows"
    )
    db:close()

    -- The backup is a rollback point from immediately before schema mutation.
    local backup = SQ3.open(path .. ".bak")
    assertEqual(
        tonumber(backup:rowexec("PRAGMA user_version;")),
        1,
        "migration backup must retain the old schema version"
    )
    assertEqual(
        tonumber(backup:rowexec(
            "SELECT count(*) FROM documents WHERE reader_id='persisted-v1';"
        )),
        1,
        "migration backup must retain pre-migration data"
    )
    backup:close()

    os.remove(path)
    os.remove(path .. ".bak")
    os.remove(path .. "-journal")
    os.remove(path .. ".bak-journal")
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
    testV1ToV2Migration()
    testBackupCopySemantics()
    testFileBackedMigrationBackup()
    testTransactionRollback()
    testMigrationRollbackSignal()
end
