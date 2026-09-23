-- SPDX-License-Identifier: AGPL-3.0-only

local FirstArticle = {}
FirstArticle.__index = FirstArticle

function FirstArticle:new(options)
    options = options or {}
    return setmetatable({
        reader = assert(options.reader, "reader is required"),
        repository = assert(options.repository, "repository is required"),
        html = assert(options.html, "html is required"),
        images = options.images,
        raw_source = options.raw_source,
        filenames = assert(options.filenames, "filenames is required"),
        installer = assert(options.installer, "installer is required"),
        hasher = assert(options.hasher, "hasher is required"),
        koreader_documents = assert(options.koreader_documents, "koreader_documents is required"),
        download_root = assert(options.download_root, "download_root is required"),
        now = options.now or os.time,
        file_exists = options.file_exists or function(path)
            return require("libs/libkoreader-lfs").attributes(path, "mode") == "file"
        end,
    }, self)
end

function FirstArticle:listCandidates(limit)
    local page, err = self.reader:listDocuments{
        category = "article",
        limit = tonumber(limit) or 100,
        with_html_content = false,
        with_raw_source_url = false,
    }
    if not page then
        return nil, err
    end

    local candidates = {}
    for _, document in ipairs(page.results) do
        if document.parent_id == nil and document.category == "article" then
            candidates[#candidates + 1] = {
                id = document.id,
                title = document.title,
                author = document.author,
                location = document.location,
            }
        end
    end
    return candidates
end

function FirstArticle:fetchDocument(reader_id)
    local document, err = self.reader:getDocument(reader_id, true, false)
    if not document then
        return nil, err
    end
    if document.parent_id ~= nil then
        return nil, {
            kind = "content",
            retryable = false,
            message = "The selected Reader record is a child record, not an article.",
        }
    end
    if document.category ~= "article" then
        return nil, {
            kind = "content",
            retryable = false,
            message = "The selected Reader record is not an article.",
        }
    end
    if type(document.html_content) ~= "string" or document.html_content:match("^%s*$") then
        return nil, {
            kind = "content",
            retryable = false,
            message = "Reader did not provide processed HTML content for this article.",
        }
    end
    return document
end

function FirstArticle:getExistingPath(reader_id)
    local existing = self.repository:getById(reader_id)
    if existing and existing.local_path and self.file_exists(existing.local_path) then
        return existing.local_path
    end
end

local RAW_CATEGORIES = { pdf = true, epub = true }

local function folderFor(document)
    if document.category == "pdf" then return "PDFs" end
    if document.category == "epub" then return "EPUBs" end
    return "Articles"
end

function FirstArticle:_finalPath(document, extension)
    local filename = self.filenames.build(document.title, document.id, extension)
    return self.filenames.joinUnderRoot(
        self.download_root,
        folderFor(document),
        filename
    )
end

function FirstArticle:_fallbackPath(document, extension)
    local filename = self.filenames.build(nil, document.id, extension)
    return self.filenames.joinUnderRoot(
        self.download_root,
        folderFor(document),
        filename
    )
end

function FirstArticle:_recordLocal(document, state)
    self.repository:setLocalState(document.id, {
        local_path = state.path,
        local_format = state.format,
        download_strategy = state.strategy,
        local_content_hash = state.content_hash,
        remote_content_fingerprint = state.remote_fingerprint,
        is_local_present = true,
        last_materialized_at = self.now(),
        last_sync_error = nil,
    })

    local metadata_ok, metadata_err = self.koreader_documents:writeMetadata(state.path, document)
    return {
        path = state.path,
        existing = false,
        durability_warning = state.durability_warning,
        metadata_warning = metadata_ok and nil or metadata_err,
        image_report = state.image_report,
        raw_source_used = state.strategy == "reader_raw_source",
        raw_fallback_used = state.strategy == "reader_html_fallback",
        raw_bytes = state.raw_bytes,
    }
end

function FirstArticle:_installHtml(document, strategy)
    if type(document.html_content) ~= "string" or document.html_content:match("^%s*$") then
        return nil, {
            kind = "content",
            retryable = false,
            message = "Reader did not provide usable processed HTML content for this document.",
        }
    end

    local final_path = self:_finalPath(document, "html")
    local render_document = document
    local image_report
    if self.images then
        local article_dir = final_path:match("^(.*)/[^/]+$")
        local asset_dir = self.filenames.assetDirectory(document.id)
        local localized_html
        localized_html, image_report = self.images:localize(
            document,
            article_dir .. "/" .. asset_dir,
            asset_dir
        )
        render_document = {}
        for key, value in pairs(document) do render_document[key] = value end
        render_document.html_content = localized_html
    end

    local rendered, render_err = self.html.build(render_document)
    if not rendered then
        if self.images and image_report then self.images:cleanup(image_report.new_paths) end
        return nil, render_err
    end

    local installed, install_err = self.installer:install(rendered, final_path)
    if not installed
        and install_err
        and install_err.kind == "io"
        and install_err.stage == "open"
        and install_err.detail == "invalid_name" then
        local fallback_path = self:_fallbackPath(document, "html")
        if fallback_path ~= final_path then
            installed, install_err = self.installer:install(rendered, fallback_path)
            if installed then final_path = fallback_path end
        end
    end

    if not installed then
        if self.images and image_report then self.images:cleanup(image_report.new_paths) end
        return nil, install_err
    end

    local content_hash = self.hasher.digest(rendered)
    local fingerprint_input = tostring(document.updated_at or "") .. "\n" .. content_hash
    return self:_recordLocal(document, {
        path = final_path,
        format = "html",
        strategy = strategy or "reader_html",
        content_hash = content_hash,
        remote_fingerprint = self.hasher.digest(fingerprint_input),
        durability_warning = installed.durability_warning,
        image_report = image_report,
    })
end

function FirstArticle:_installRaw(document)
    if not self.raw_source then
        return nil, {
            kind = "raw_unavailable",
            retryable = false,
            message = "Raw source downloader is not configured.",
        }
    end

    local extension = document.category
    local final_path = self:_finalPath(document, extension)
    local installed, install_err = self.raw_source:download(document, final_path)

    if not installed
        and install_err
        and install_err.kind == "io"
        and install_err.stage == "open"
        and install_err.detail == "invalid_name" then
        local fallback_path = self:_fallbackPath(document, extension)
        if fallback_path ~= final_path then
            installed, install_err = self.raw_source:download(document, fallback_path)
            if installed then final_path = fallback_path end
        end
    end

    if not installed then return nil, install_err end

    local remote_fingerprint = self.hasher.digest(
        tostring(document.updated_at or "")
            .. "\nraw:"
            .. tostring(document.category)
            .. ":"
            .. tostring(installed.bytes or 0)
    )
    return self:_recordLocal(document, {
        path = final_path,
        format = installed.format,
        strategy = installed.download_strategy,
        content_hash = nil,
        remote_fingerprint = remote_fingerprint,
        durability_warning = installed.durability_warning,
        raw_bytes = installed.bytes,
    })
end

function FirstArticle:installDocument(document)
    assert(type(document) == "table", "document is required")
    assert(type(document.id) == "string" and document.id ~= "", "document.id is required")

    local existing_path = self:getExistingPath(document.id)
    if existing_path then
        return {
            path = existing_path,
            existing = true,
        }
    end

    self.repository:upsertRemote(document, self.now())

    if RAW_CATEGORIES[document.category] then
        local raw_result, raw_err = self:_installRaw(document)
        if raw_result then return raw_result end

        if self.raw_source and self.raw_source:isFallbackEligible(raw_err)
            and type(document.html_content) == "string"
            and not document.html_content:match("^%s*$") then
            local fallback, fallback_err = self:_installHtml(document, "reader_html_fallback")
            if fallback then
                fallback.raw_warning = raw_err
                return fallback
            end
            raw_err = fallback_err or raw_err
        end

        self.repository:setLocalState(document.id, {
            is_local_present = false,
            last_sync_error = raw_err and raw_err.kind or "content",
        })
        return nil, raw_err
    end

    local result, err = self:_installHtml(document, "reader_html")
    if not result then
        self.repository:setLocalState(document.id, {
            is_local_present = false,
            last_sync_error = err and err.kind or "content",
        })
    end
    return result, err
end
return FirstArticle
