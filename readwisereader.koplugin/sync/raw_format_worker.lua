-- SPDX-License-Identifier: AGPL-3.0-only

local RawFormatWorker = {}

local function metadataPayload(document)
    local tags = {}
    for i, tag in ipairs(document.tags or {}) do tags[i] = tag end
    return {
        title = document.title,
        author = document.author,
        summary = document.summary,
        site_name = document.site_name,
        tags = tags,
    }
end

local function buildMaterializer(config, http, repository, deferred_documents)
    local Filenames = require("content/filenames")
    local FirstArticle = require("sync/first_article")
    local Hash = require("content/hash")
    local Html = require("content/html")
    local Images = require("content/images")
    local Installer = require("content/installer")
    local RawSource = require("content/raw_source")
    local Reader = require("api/reader")

    local installer = Installer:new()
    local reader = Reader:new{ http = http, config = config }
    local images = Images:new{
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
    return reader, FirstArticle:new{
        reader = reader,
        repository = repository,
        html = Html,
        images = images,
        raw_source = raw_source,
        filenames = Filenames,
        installer = installer,
        hasher = Hash,
        koreader_documents = deferred_documents,
        download_root = config:getDownloadDirectory(),
    }
end

function RawFormatWorker:listCandidates(category)
    local Config = require("config")
    local Http = require("api/http")
    local Reader = require("api/reader")
    local config = Config:new()

    local ok, result, err = pcall(function()
        local reader = Reader:new{ http = Http:new(), config = config }
        local page, list_err = reader:listDocuments{
            category = category,
            limit = 100,
            with_html_content = false,
            with_raw_source_url = false,
        }
        if not page then return nil, list_err end
        local out = {}
        for _, document in ipairs(page.results) do
            if document.parent_id == nil and document.category == category then
                out[#out + 1] = {
                    id = document.id,
                    title = document.title,
                    author = document.author,
                    category = document.category,
                    location = document.location,
                }
            end
        end
        return out
    end)
    pcall(function() config:close() end)
    if not ok then
        return nil, {
            kind = "worker",
            retryable = true,
            message = "Raw format candidate scan failed safely.",
        }
    end
    return result, err
end

function RawFormatWorker:run(reader_id, category)
    local Config = require("config")
    local DB = require("storage/db")
    local DocumentsRepository = require("storage/documents")
    local Http = require("api/http")
    local config = Config:new()
    local db

    local ok, result, err = pcall(function()
        db = DB:new()
        local repository = DocumentsRepository:new{ db = db }
        local deferred_metadata
        local deferred_documents = {
            writeMetadata = function(_, path, document)
                deferred_metadata = {
                    path = path,
                    metadata = metadataPayload(document),
                }
                return true
            end,
        }
        local reader, materializer = buildMaterializer(
            config, Http:new(), repository, deferred_documents
        )

        local existing = materializer:getExistingPath(reader_id)
        if existing then
            local row = repository:getById(reader_id)
            return {
                path = existing,
                existing = true,
                location = row and row.location or nil,
            }
        end

        local document, fetch_err = reader:getDocument(reader_id, true, true)
        if not document then return nil, fetch_err end
        if document.parent_id ~= nil or document.category ~= category then
            return nil, {
                kind = "content",
                retryable = false,
                message = "Reader returned a different document category.",
            }
        end

        local installed, install_err = materializer:installDocument(document)
        if not installed then return nil, install_err end
        return {
            path = installed.path,
            existing = installed.existing == true,
            raw_source_used = installed.raw_source_used == true,
            raw_fallback_used = installed.raw_fallback_used == true,
            raw_bytes = installed.raw_bytes,
            location = document.location,
            metadata = deferred_metadata,
        }
    end)

    if db then pcall(function() db:close() end) end
    pcall(function() config:close() end)

    if not ok then
        return nil, {
            kind = "worker",
            retryable = true,
            message = "Raw format download failed safely.",
        }
    end
    return result, err
end

RawFormatWorker._metadataPayload = metadataPayload

return RawFormatWorker
