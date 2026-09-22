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
    testTransactionRollback()
    testMigrationRollbackSignal()
end
