-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = {}

function Worker:run(local_path)
    if type(local_path) ~= "string" or local_path == "" then
        return nil, {
            kind = "client",
            retryable = false,
            message = "Open a Readwise-managed document first.",
        }
    end

    local Config = require("config")
    local DB = require("storage/db")
    local DocumentsRepository = require("storage/documents")
    local Hash = require("content/hash")
    local Http = require("api/http")
    local KOReaderAnnotations = require("koreader/annotations")
    local Probe = require("sync/text_match_probe")
    local Reader = require("api/reader")

    local config = Config:new()
    local db
    local ok, result, probe_err = pcall(function()
        db = DB:new()
        local probe = Probe:new{
            documents = DocumentsRepository:new{ db = db },
            adapter = KOReaderAnnotations:new{ hasher = Hash },
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
            message = "Gate 9 text-match diagnostic failed safely.",
        }
    end
    return result, probe_err
end

return Worker
