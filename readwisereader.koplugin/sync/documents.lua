-- SPDX-License-Identifier: AGPL-3.0-only

local DocumentsSync = {}
DocumentsSync.__index = DocumentsSync

local DEFAULT_OVERLAP_SECONDS = 300
local HTML_PAGE_LIMIT = 25
local SUPPORTED_CATEGORIES = { article = true }

local function asSet(values)
    local set = {}
    for _, value in ipairs(values or {}) do set[value] = true end
    return set
end

local function sortedKeys(set)
    local keys = {}
    for key in pairs(set or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function filterScope(filters)
    return "locations=" .. table.concat(sortedKeys(filters.locations), ",")
        .. ";categories=" .. table.concat(sortedKeys(filters.categories), ",")
end

local function defaultFormatTime(epoch)
    return os.date("!%Y-%m-%dT%H:%M:%SZ", epoch)
end

local function metadataChanged(existing, document)
    return existing and (
        existing.title ~= document.title
        or existing.author ~= document.author
        or existing.site_name ~= document.site_name
        or existing.location ~= document.location
        or existing.remote_updated_at ~= document.updated_at
    ) or false
end

function DocumentsSync:new(options)
    options = options or {}
    return setmetatable({
        reader = assert(options.reader, "reader is required"),
        repository = assert(options.repository, "repository is required"),
        sync_meta = assert(options.sync_meta, "sync_meta is required"),
        materializer = assert(options.materializer, "materializer is required"),
        collections = assert(options.collections, "collections is required"),
        koreader_documents = assert(options.koreader_documents, "koreader_documents is required"),
        config = assert(options.config, "config is required"),
        now = options.now or os.time,
        format_time = options.format_time or defaultFormatTime,
        overlap_seconds = options.overlap_seconds or DEFAULT_OVERLAP_SECONDS,
        file_exists = options.file_exists or function(path)
            return require("libs/libkoreader-lfs").attributes(path, "mode") == "file"
        end,
    }, self)
end

function DocumentsSync:_filters()
    return {
        locations = asSet(self.config:getSyncLocations()),
        categories = asSet(self.config:getSyncCategories()),
    }
end

function DocumentsSync:_isEligible(document, filters)
    return document
        and document.parent_id == nil
        and filters.locations[document.location] == true
        and filters.categories[document.category] == true
        and SUPPORTED_CATEGORIES[document.category] == true
end

function DocumentsSync:_hasLocal(existing)
    return existing
        and type(existing.local_path) == "string"
        and existing.local_path ~= ""
        and self.file_exists(existing.local_path)
end

function DocumentsSync:_syncCollection(existing, document, report)
    if not self:_hasLocal(existing) then return true end
    local ok = self.collections:syncLocation(existing.local_path, document.location)
    if not ok then
        report.errors = report.errors + 1
        return false
    end
    return true
end

function DocumentsSync:_updateExistingMetadata(existing, document, seen_at, report)
    local changed = metadataChanged(existing, document)
    local moved = existing.location ~= document.location
    local remote_changed = existing.remote_updated_at ~= nil
        and existing.remote_updated_at ~= document.updated_at
    local current = self.repository:upsertRemote(document, seen_at)

    if self:_hasLocal(existing) then
        if changed then
            local ok = self.koreader_documents:writeMetadata(existing.local_path, document)
            if not ok then
                report.errors = report.errors + 1
            else
                report.metadata_updated = report.metadata_updated + 1
                report.metadata_invalidate_paths[#report.metadata_invalidate_paths + 1] = existing.local_path
            end
        end
        if moved then report.location_moved = report.location_moved + 1 end
        self:_syncCollection(existing, document, report)
        if remote_changed then
            -- Content replacement is intentionally deferred to Phase Q.
            report.content_refresh_deferred = report.content_refresh_deferred + 1
        end
    end
    return current
end

function DocumentsSync:_install(document, report)
    local result, err = self.materializer:installDocument(document)
    if not result then
        local kind = err and err.kind or "unknown"
        self.repository:setLastSyncError(document.id, kind)
        -- A document that Reader itself cannot materialize (for example an
        -- article with no processed HTML) is a permanent per-item skip for
        -- this remote revision, not a failed sync transaction. Counting it as
        -- fatal strands the global watermark and forces every later sync back
        -- through the entire library. If Reader changes the document later,
        -- updatedAfter will surface it again and we can retry.
        if err and err.retryable == false then
            report.nonretryable_skipped = report.nonretryable_skipped + 1
            return false
        end
        report.errors = report.errors + 1
        report.retryable_item_errors = report.retryable_item_errors + 1
        return false
    end

    if result.existing then
        report.unchanged = report.unchanged + 1
    else
        report.downloaded = report.downloaded + 1
    end
    if result.metadata_warning then report.errors = report.errors + 1 end

    local collection_ok = self.collections:syncLocation(result.path, document.location)
    if not collection_ok then report.errors = report.errors + 1 end
    return true
end

function DocumentsSync:_scanMetadata(watermark, filters, managed_by_id, pending_new, report, seen_at)
    local scan, err = self.reader:iterateDocuments({
        updated_after = watermark,
        limit = 100,
        with_html_content = false,
        with_raw_source_url = false,
    }, function(document)
        if document.parent_id ~= nil then
            report.child_records = report.child_records + 1
            return
        end

        report.metadata_seen = report.metadata_seen + 1
        local existing = managed_by_id[document.id]
        if existing then
            local current = self:_updateExistingMetadata(existing, document, seen_at, report)
            managed_by_id[document.id] = current
            if not self:_hasLocal(existing) and self:_isEligible(document, filters) then
                pending_new[document.id] = true
            end
        elseif self:_isEligible(document, filters) then
            local current = self.repository:upsertRemote(document, seen_at)
            managed_by_id[document.id] = current
            pending_new[document.id] = true
        else
            report.filtered_out = report.filtered_out + 1
        end
    end)

    if not scan then return nil, err end
    report.metadata_pages = report.metadata_pages + scan.pages
    report.duplicates_ignored = report.duplicates_ignored + scan.duplicates
    return true
end

function DocumentsSync:_fullMaterialization(filters, report, seen_at)
    local seen = {}
    for _, category in ipairs(sortedKeys(filters.categories)) do
        if SUPPORTED_CATEGORIES[category] then
            for _, location in ipairs(sortedKeys(filters.locations)) do
                local scan, err = self.reader:iterateDocuments({
                    location = location,
                    category = category,
                    limit = HTML_PAGE_LIMIT,
                    with_html_content = true,
                    with_raw_source_url = false,
                }, function(document)
                    if document.parent_id ~= nil or seen[document.id] then return end
                    seen[document.id] = true
                    if not self:_isEligible(document, filters) then return end

                    local existing = self.repository:getById(document.id)
                    self.repository:upsertRemote(document, seen_at)
                    if self:_hasLocal(existing) then
                        report.unchanged = report.unchanged + 1
                        local ok = self.collections:syncLocation(existing.local_path, document.location)
                        if not ok then report.errors = report.errors + 1 end
                    else
                        self:_install(document, report)
                    end
                end)
                if not scan then return nil, err end
                report.content_pages = report.content_pages + scan.pages
                report.duplicates_ignored = report.duplicates_ignored + scan.duplicates
            end
        else
            report.unsupported_categories = report.unsupported_categories + 1
        end
    end
    return true
end

function DocumentsSync:_incrementalMaterialization(filters, pending_new, report, seen_at)
    for _, reader_id in ipairs(sortedKeys(pending_new)) do
        local document, err = self.reader:getDocument(reader_id, true, false)
        if not document then
            report.errors = report.errors + 1
            self.repository:setLastSyncError(reader_id, err and err.kind or "unknown")
        elseif not self:_isEligible(document, filters) then
            self.repository:upsertRemote(document, seen_at)
            report.filtered_out = report.filtered_out + 1
        else
            self.repository:upsertRemote(document, seen_at)
            self:_install(document, report)
        end
    end
    return true
end

function DocumentsSync:sync(options)
    options = options or {}
    local started_epoch = self.now()
    local started_at = self.format_time(started_epoch)
    local previous_watermark = self.sync_meta:get("document_watermark")
    local previous_query_after = self.sync_meta:get("document_query_after")
    local previous_filter_scope = self.sync_meta:get("document_filter_scope")
    local filters = self:_filters()
    local current_filter_scope = filterScope(filters)
    -- Incremental updatedAfter can only discover documents changed since the
    -- watermark. If the enabled filter scope changes, especially when a
    -- location is newly enabled, historical documents in that scope require
    -- a backfill. Treat a missing scope marker from older 0.1.3 builds the
    -- same way so a stale watermark cannot strand the first Gate 4 library.
    local filter_scope_changed = previous_filter_scope ~= current_filter_scope
    local full_scan = options.full_rescan == true
        or previous_watermark == nil
        or filter_scope_changed
    local query_watermark
    if not full_scan then
        query_watermark = previous_query_after or previous_watermark
    end

    local report = {
        mode = full_scan and "full" or "incremental",
        started_at = started_at,
        previous_watermark = previous_watermark,
        filter_scope = current_filter_scope,
        filter_scope_changed = filter_scope_changed,
        metadata_pages = 0,
        content_pages = 0,
        metadata_seen = 0,
        child_records = 0,
        duplicates_ignored = 0,
        downloaded = 0,
        unchanged = 0,
        metadata_updated = 0,
        metadata_invalidate_paths = {},
        location_moved = 0,
        content_refresh_deferred = 0,
        filtered_out = 0,
        unsupported_categories = 0,
        nonretryable_skipped = 0,
        retryable_item_errors = 0,
        errors = 0,
        watermark_advanced = false,
    }

    self.sync_meta:set("document_scan_started_at", started_at)

    local managed_by_id, pending_new = {}, {}
    for _, existing in ipairs(self.repository:listManaged()) do
        managed_by_id[existing.reader_id] = existing
        if not self:_hasLocal(existing)
            and filters.locations[existing.location]
            and filters.categories[existing.category]
            and SUPPORTED_CATEGORIES[existing.category] then
            pending_new[existing.reader_id] = true
        end
    end

    local metadata_ok, metadata_err = self:_scanMetadata(
        query_watermark, filters, managed_by_id, pending_new, report, started_epoch
    )
    if not metadata_ok then return nil, metadata_err end

    local content_ok, content_err
    if full_scan then
        content_ok, content_err = self:_fullMaterialization(filters, report, started_epoch)
    else
        content_ok, content_err = self:_incrementalMaterialization(filters, pending_new, report, started_epoch)
    end
    if not content_ok then return nil, content_err end

    local completed_epoch = self.now()
    local completed_at = self.format_time(completed_epoch)
    report.completed_at = completed_at
    self.sync_meta:set("document_scan_completed_at", completed_at)

    if report.errors == 0 then
        -- Canonical watermark is the scan start. Keep the precomputed
        -- overlap lower bound separately so we do not need timezone-sensitive
        -- ISO parsing on the Kindle.
        local watermark = started_at
        local query_after = self.format_time(math.max(0, started_epoch - self.overlap_seconds))
        if previous_watermark and previous_watermark > watermark then
            watermark = previous_watermark
            query_after = previous_query_after or previous_watermark
        end
        report.proposed_watermark = watermark
        report.proposed_query_after = query_after
        report.proposed_filter_scope = current_filter_scope
        report.watermark = watermark
        report.query_after = query_after
        report.watermark_advanced = previous_watermark ~= watermark
        if options.defer_watermark ~= true then
            self.sync_meta:set("document_watermark", watermark)
            self.sync_meta:set("document_query_after", query_after)
            self.sync_meta:set("document_filter_scope", current_filter_scope)
            self.sync_meta:set("last_successful_sync_at", completed_at)
            if full_scan then self.sync_meta:set("last_full_scan_at", completed_at) end
        end
    end

    return report
end

DocumentsSync.DEFAULT_OVERLAP_SECONDS = DEFAULT_OVERLAP_SECONDS
DocumentsSync.HTML_PAGE_LIMIT = HTML_PAGE_LIMIT
DocumentsSync.SUPPORTED_CATEGORIES = SUPPORTED_CATEGORIES
DocumentsSync._metadataChanged = metadataChanged
DocumentsSync._filterScope = filterScope

return DocumentsSync
