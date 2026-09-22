-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = {}

function Worker:run(options)
    options = options or {}

    local Config = require("config")
    local DB = require("storage/db")
    local DocumentsRepository = require("storage/documents")
    local SyncMeta = require("storage/sync_meta")
    local Filenames = require("content/filenames")
    local FirstArticle = require("sync/first_article")
    local Hash = require("content/hash")
    local Html = require("content/html")
    local Http = require("api/http")
    local Installer = require("content/installer")
    local KOReaderCollections = require("koreader/collections")
    local KOReaderDocuments = require("koreader/documents")
    local Reader = require("api/reader")
    local DocumentsSync = require("sync/documents")
    local logger = require("logger")

    local config = Config:new()
    local db

    local ok, report, err = pcall(function()
        -- The long-running sync executes inside Trapper's child process.
        -- Open a fresh SQLite connection here instead of using the parent's
        -- inherited connection after fork.
        db = DB:new()
        local repository = DocumentsRepository:new{ db = db }
        local sync_meta = SyncMeta:new{ db = db }
        local http = Http:new()
        local reader = Reader:new{
            http = http,
            config = config,
        }
        local koreader_documents = KOReaderDocuments:new()
        local collections = KOReaderCollections:new()
        local materializer = FirstArticle:new{
            reader = reader,
            repository = repository,
            html = Html,
            filenames = Filenames,
            installer = Installer:new(),
            hasher = Hash,
            koreader_documents = koreader_documents,
            download_root = config:getDownloadDirectory(),
        }
        local syncer = DocumentsSync:new{
            reader = reader,
            repository = repository,
            sync_meta = sync_meta,
            materializer = materializer,
            collections = collections,
            koreader_documents = koreader_documents,
            config = config,
        }
        return syncer:sync{
            full_rescan = options.full_rescan == true,
        }
    end)

    if db then
        pcall(function() db:close() end)
    end
    if config then
        pcall(function() config:close() end)
    end

    if not ok then
        -- Do not copy the thrown error to the UI/log: it can contain a local
        -- filename derived from private Reader metadata.
        logger.warn("ReadwiseReader: [SYNC] worker failed safely")
        return nil, {
            kind = "worker",
            retryable = true,
            message = "Document sync worker failed.",
        }
    end
    return report, err
end

return Worker
