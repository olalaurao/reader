-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = {}

local function copyMetadata(document)
    local tags
    if type(document.tags) == "table" then
        tags = {}
        for i, tag in ipairs(document.tags) do tags[i] = tag end
    end
    return {
        title = document.title,
        author = document.author,
        summary = document.summary,
        site_name = document.site_name,
        tags = tags,
    }
end

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
    local Images = require("content/images")
    local Http = require("api/http")
    local Installer = require("content/installer")
    local RawSource = require("content/raw_source")
    local Reader = require("api/reader")
    local DocumentsSync = require("sync/documents")
    local logger = require("logger")
    local util = require("util")

    local config = Config:new()
    local db

    local ok, report, err = pcall(function()
        -- Trapper's child process must not manipulate UIManager or KOReader
        -- settings/cache owned by the parent. It may perform network work,
        -- atomic file installs and durable SQLite writes.
        db = DB:new()
        local repository = DocumentsRepository:new{ db = db }
        local sync_meta = SyncMeta:new{ db = db }
        local http = Http:new()
        local reader = Reader:new{
            http = http,
            config = config,
        }

        local postprocess_by_path = {}
        local function postprocess(path)
            local item = postprocess_by_path[path]
            if not item then
                item = { path = path }
                postprocess_by_path[path] = item
            end
            return item
        end

        local deferred_documents = {
            writeMetadata = function(_, path, document)
                postprocess(path).metadata = copyMetadata(document)
                return true
            end,
        }
        local deferred_collections = {
            syncLocation = function(_, path, location)
                postprocess(path).location = location
                return true
            end,
        }

        local storage_before = util.diskUsage(config:getDownloadDirectory())
        local installer = Installer:new()
        local image_localizer = Images:new{
            http = http,
            installer = installer,
            enabled = config:getDownloadImages(),
            per_image_max = config:getMaxImageBytes(),
            total_max = config:getMaxArticleImageBytes(),
            max_images = config:getMaxImagesPerArticle(),
        }
        local raw_source = RawSource:new{
            http = http,
            installer = installer,
            download_root = config:getDownloadDirectory(),
            max_bytes = config:getMaxRawSourceBytes(),
            min_free_bytes = config:getMinRawSourceFreeBytes(),
        }
        local materializer = FirstArticle:new{
            reader = reader,
            repository = repository,
            html = Html,
            images = image_localizer,
            raw_source = raw_source,
            filenames = Filenames,
            installer = installer,
            hasher = Hash,
            koreader_documents = deferred_documents,
            download_root = config:getDownloadDirectory(),
        }
        local syncer = DocumentsSync:new{
            reader = reader,
            repository = repository,
            sync_meta = sync_meta,
            materializer = materializer,
            collections = deferred_collections,
            koreader_documents = deferred_documents,
            config = config,
        }

        local sync_report, sync_err = syncer:sync{
            full_rescan = options.full_rescan == true,
            defer_watermark = true,
        }
        if not sync_report then
            return nil, sync_err
        end

        local paths = {}
        for path in pairs(postprocess_by_path) do
            paths[#paths + 1] = path
        end
        table.sort(paths)
        sync_report.postprocess = {}
        for _, path in ipairs(paths) do
            sync_report.postprocess[#sync_report.postprocess + 1] = postprocess_by_path[path]
        end
        -- Cache invalidation is performed implicitly by parent metadata writes.
        sync_report.metadata_invalidate_paths = nil
        local storage_after = util.diskUsage(config:getDownloadDirectory())
        sync_report.storage_available_before = storage_before and storage_before.available or nil
        sync_report.storage_available_after = storage_after and storage_after.available or nil
        return sync_report
    end)

    if db then
        pcall(function() db:close() end)
    end
    if config then
        pcall(function() config:close() end)
    end

    if not ok then
        logger.warn("ReadwiseReader: [SYNC] worker failed safely")
        return nil, {
            kind = "worker",
            retryable = true,
            message = "Document sync worker failed.",
        }
    end
    return report, err
end

Worker._copyMetadata = copyMetadata

return Worker
