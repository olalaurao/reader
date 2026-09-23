-- SPDX-License-Identifier: AGPL-3.0-only

local ApiInteropWorker = {}

local ALLOWED = {
    create = true,
    probe_v3 = true,
    update_v2 = true,
    delete_cleanup = true,
    cleanup = true,
}

function ApiInteropWorker:run(action)
    if not ALLOWED[action] then
        return nil, {
            kind = "client",
            retryable = false,
            message = "Unknown Gate 8 action.",
        }
    end

    local Config = require("config")
    local DB = require("storage/db")
    local Http = require("api/http")
    local Reader = require("api/reader")
    local Readwise = require("api/readwise")
    local SyncMeta = require("storage/sync_meta")
    local ApiInterop = require("sync/api_interop")

    local config = Config:new()
    local db
    local ok, result, err = pcall(function()
        db = DB:new()
        local http = Http:new()
        local interop = ApiInterop:new{
            reader = Reader:new{
                http = http,
                config = config,
            },
            readwise = Readwise:new{
                http = http,
                config = config,
            },
            meta = SyncMeta:new{ db = db },
        }

        if action == "create" then
            return interop:create()
        elseif action == "probe_v3" then
            return interop:probeAndUpdateV3()
        elseif action == "update_v2" then
            return interop:updateViaV2()
        elseif action == "delete_cleanup" then
            return interop:deleteAndCleanup()
        elseif action == "cleanup" then
            return interop:cleanup()
        end
    end)

    if db then pcall(function() db:close() end) end
    pcall(function() config:close() end)

    if not ok then
        return nil, {
            kind = "worker",
            retryable = true,
            message = "Gate 8 interoperability worker failed safely.",
        }
    end
    return result, err
end

return ApiInteropWorker
