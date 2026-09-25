-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = {}

local function formatTime(epoch)
    return os.date("!%Y-%m-%dT%H:%M:%SZ", epoch)
end

function Worker:run(local_path, options)
    options = options or {}

    local Config = require("config")
    local Constants = require("constants")
    local DB = require("storage/db")
    local Documents = require("storage/documents")
    local Http = require("api/http")
    local Reader = require("api/reader")
    local Probe = require("sync/remote_highlight_probe")

    local config = Config:new()
    local db
    local started_epoch = os.time()
    local ok, report, domain_err = pcall(function()
        db = DB:new()
        local probe = Probe:new{
            documents = Documents:new{ db = db },
            reader = Reader:new{
                http = Http:new(),
                config = config,
            },
        }
        return probe:run(local_path, {
            updated_after = options.updated_after,
        })
    end)

    if db then pcall(function() db:close() end) end
    pcall(function() config:close() end)

    if not ok then
        return nil, {
            kind = "worker",
            retryable = true,
            message = "Reader-highlight fetch failed safely.",
        }
    end
    if report then
        report.scan_started_at = formatTime(started_epoch)
        report.proposed_query_after = formatTime(math.max(
            0,
            started_epoch - (Constants.REMOTE_HIGHLIGHT_IMPORT_OVERLAP_SECONDS or 300)
        ))
    end
    return report, domain_err
end

return Worker
