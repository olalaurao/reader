-- SPDX-License-Identifier: AGPL-3.0-only

local Migrations = require("storage/migrations")

local DB = {}
DB.__index = DB

local function defaultDependencies()
    local DataStorage = require("datastorage")
    local Device = require("device")
    local SQ3 = require("lua-ljsqlite3/init")
    local ffiUtil = require("ffi/util")
    return {
        path = DataStorage:getSettingsDir() .. "/readwisereader.sqlite3",
        device = Device,
        sq3 = SQ3,
        copy_file = ffiUtil.copyFile,
    }
end

function DB:new(options)
    options = options or {}
    local defaults
    if not options.path or not options.device or not options.sq3 then
        defaults = defaultDependencies()
    end

    return setmetatable({
        path = options.path or defaults.path,
        device = options.device or defaults.device,
        sq3 = options.sq3 or defaults.sq3,
        copy_file = options.copy_file or (defaults and defaults.copy_file),
        conn = nil,
    }, self)
end

function DB:_configure(conn)
    if self.device:canUseWAL() then
        conn:exec("PRAGMA journal_mode=WAL;")
    else
        conn:exec("PRAGMA journal_mode=TRUNCATE;")
    end
    conn:exec("PRAGMA foreign_keys=ON;")
    conn:exec("PRAGMA busy_timeout=5000;")
end

function DB:_backupBeforeMigration(conn, from_version)
    if from_version <= 0 or from_version >= Migrations.SCHEMA_VERSION then
        return
    end
    if not self.copy_file then
        error("database backup helper is unavailable")
    end

    -- If this device uses WAL, a byte-copy of only the main database file can
    -- otherwise omit committed pages still resident in the WAL file. Startup
    -- migration runs before plugin repositories begin writing, so checkpoint
    -- the open connection first and abort the migration if that checkpoint
    -- cannot be completed.
    local journal_mode = tostring(conn:rowexec("PRAGMA journal_mode;") or ""):lower()
    if journal_mode == "wal" then
        conn:exec("PRAGMA wal_checkpoint(FULL);")
    end

    -- KOReader ffiUtil.copyFile returns nil on success and an error string on
    -- failure. The backup intentionally captures the pre-migration schema so a
    -- downgrade can restore it alongside the older plugin.
    local copy_err = self.copy_file(self.path, self.path .. ".bak")
    if copy_err ~= nil then
        error("database backup failed: " .. tostring(copy_err))
    end
end

function DB:open()
    if self.conn then
        return self.conn
    end

    local conn = self.sq3.open(self.path)
    local ok, err = pcall(function()
        self:_configure(conn)
        local version = Migrations.currentVersion(conn)
        if version > Migrations.SCHEMA_VERSION then
            error(string.format(
                "database schema %d is newer than supported schema %d",
                version,
                Migrations.SCHEMA_VERSION
            ))
        end
        self:_backupBeforeMigration(conn, version)
        Migrations.apply(conn, version)
    end)

    if not ok then
        pcall(conn.close, conn)
        error(err)
    end

    self.conn = conn
    return conn
end

function DB:getConnection()
    return self:open()
end

function DB:getSchemaVersion()
    return Migrations.currentVersion(self:open())
end

function DB:transaction(callback)
    local conn = self:open()
    conn:exec("BEGIN IMMEDIATE;")
    local ok, result = pcall(callback, conn)
    if ok then
        conn:exec("COMMIT;")
        return result
    end
    pcall(conn.exec, conn, "ROLLBACK;")
    error(result)
end

function DB:close()
    if self.conn then
        self.conn:close()
        self.conn = nil
    end
end

return DB
