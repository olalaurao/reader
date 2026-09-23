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

    local filename = self.filenames.build(document.title, document.id, "html")
    local final_path = self.filenames.joinUnderRoot(
        self.download_root,
        "Articles",
        filename
    )

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

    self.repository:upsertRemote(document, self.now())

    local installed, install_err = self.installer:install(rendered, final_path)

    -- Some Kindle/VFAT paths reject otherwise valid-looking Unicode/title
    -- filenames with EINVAL. Reader ID is the ownership identity, so retry
    -- only that specific filename/path failure with an ASCII-safe title while
    -- preserving the real title in KOReader metadata.
    if not installed
        and install_err
        and install_err.kind == "io"
        and install_err.stage == "open"
        and install_err.detail == "invalid_name" then
        local fallback_filename = self.filenames.build(nil, document.id, "html")
        local fallback_path = self.filenames.joinUnderRoot(
            self.download_root,
            "Articles",
            fallback_filename
        )
        if fallback_path ~= final_path then
            installed, install_err = self.installer:install(rendered, fallback_path)
            if installed then
                final_path = fallback_path
            end
        end
    end

    if not installed then
        if self.images and image_report then self.images:cleanup(image_report.new_paths) end
        self.repository:setLocalState(document.id, {
            is_local_present = false,
            last_sync_error = install_err and install_err.kind or "io",
        })
        return nil, install_err
    end

    local content_hash = self.hasher.digest(rendered)
    local fingerprint_input = tostring(document.updated_at or "") .. "\n" .. content_hash
    local remote_fingerprint = self.hasher.digest(fingerprint_input)
    local materialized_at = self.now()

    self.repository:setLocalState(document.id, {
        local_path = final_path,
        local_format = "html",
        download_strategy = "reader_html",
        local_content_hash = content_hash,
        remote_content_fingerprint = remote_fingerprint,
        is_local_present = true,
        last_materialized_at = materialized_at,
        last_sync_error = nil,
    })

    local metadata_ok, metadata_err = self.koreader_documents:writeMetadata(final_path, document)
    return {
        path = final_path,
        existing = false,
        durability_warning = installed.durability_warning,
        metadata_warning = metadata_ok and nil or metadata_err,
        image_report = image_report,
    }
end

return FirstArticle
