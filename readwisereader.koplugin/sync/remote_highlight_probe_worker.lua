-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = {}

function Worker:run(local_path)
    local Config = require("config")
    local DB = require("storage/db")
    local Documents = require("storage/documents")
    local Http = require("api/http")
    local Reader = require("api/reader")
    local Probe = require("sync/remote_highlight_probe")

    local config = Config:new()
    local db
    local ok, report, domain_err = pcall(function()
        db = DB:new()
        local probe = Probe:new{
            documents = Documents:new{ db = db },
            reader = Reader:new{
                http = Http:new(),
                config = config,
            },
        }
        return probe:run(local_path)
    end)

    if db then pcall(function() db:close() end) end
    pcall(function() config:close() end)

    if not ok then
        return nil, {
            kind = "worker",
            retryable = true,
            message = "Gate 17A Reader-highlight probe failed safely.",
        }
    end
    return report, domain_err
end

return Worker
