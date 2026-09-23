-- SPDX-License-Identifier: AGPL-3.0-only

local DocumentsSync = {}
DocumentsSync.__index = DocumentsSync

local DEFAULT_OVERLAP_SECONDS = 300
local HTML_PAGE_LIMIT = 25
local METADATA_PROJECTION_VERSION = "reader-tags-v2"
local SUPPORTED_CATEGORIES = { article = true }
local PERMANENT_MATERIALIZATION_ERRORS = {
    content = true,
    exists = true,
}

local function shouldRetryMissing(existing, remote_document)
    if not existing then return true end
    if not PERMANENT_MATERIALIZATION_ERRORS[existing.last_sync_error] then
        return true
    end
    -- Permanent failures are tied to the remote revision that produced them.
    -- Do not retry them on every no-op incremental sync. A later Reader
    -- revision is allowed to retry because its content/path may now differ.
    return remote_document ~= nil
        and existing.remote_updated_at ~= remote_document.updated_at
end

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

function DocumentsSync:_hasRecordedLocal(existing)
    return existing
        and existing.is_local_present == true
        and type(existing.local_path) == "string"
        and existing.local_path ~= ""
end

function DocumentsSync:_hasLocal(existing)
    return self:_hasRecordedLocal(existing)
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

function DocumentsSync:_updateExistingMetadata(existing, document, seen_at, report, force_metadata, projection_backfill)
    local changed = force_metadata == true or metadataChanged(existing, document)
    local moved = existing.location ~= document.location
    local remote_changed = existing.remote_updated_at ~= nil
        and existing.remote_updated_at ~= document.updated_at
    local current = self.repository:upsertRemote(document, seen_at)

    -- A projection backfill can touch hundreds of already-managed rows. On
    -- slow e-ink storage, stat'ing every local file dominates an otherwise
    -- metadata-only sync. Trust durable is_local_present for unchanged rows;
    -- still verify the filesystem whenever we are about to write metadata,
    -- move a Collection, or react to a new remote revision.
    local verify_disk = not projection_backfill
        or force_metadata == true
        or moved
        or remote_changed
    local has_local = verify_disk
        and self:_hasLocal(existing)
        or self:_hasRecordedLocal(existing)

    if has_local then
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
        -- The one-time metadata projection backfill touches every managed
        -- document. Rewriting an unchanged Collection for every one of those
        -- files adds hundreds of unnecessary settings writes on a Kindle.
        -- Preserve normal collection-repair behavior outside the backfill,
        -- while still applying any real Reader-side location move we discover.
        if moved or not projection_backfill then
            self:_syncCollection(existing, document, report)
        end
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
        local stage = err and err.stage or (err and err.kind) or "unknown"
        local detail = err and err.detail
        local bucket = detail and (stage .. "/" .. detail) or stage
        report.retryable_error_stages[bucket] = (report.retryable_error_stages[bucket] or 0) + 1
        return false
    end

    if result.existing then
        report.unchanged = report.unchanged + 1
    else
        report.downloaded = report.downloaded + 1
    end
    local images = result.image_report
    if images then
        report.images_downloaded = report.images_downloaded + (images.downloaded or 0)
        report.images_reused = report.images_reused + (images.reused or 0)
        report.images_failed = report.images_failed + (images.failed or 0)
        report.images_skipped = report.images_skipped + (images.skipped or 0)
        report.image_bytes = report.image_bytes + (images.bytes or 0)
    end
    if result.metadata_warning then report.errors = report.errors + 1 end

    local collection_ok = self.collections:syncLocation(result.path, document.location)
    if not collection_ok then report.errors = report.errors + 1 end
    return true
end

function DocumentsSync:_scanMetadata(watermark, filters, managed_by_id, pending_new, report, seen_at, force_metadata)
    local scan, err = self.reader:iterateDocuments({
        updated_after = watermark,
        -- Projection backfills only need currently-supported reading
        -- documents. Filtering server-side excludes highlight/note child
        -- records and cuts the one-time tag repair from the whole Reader
        -- corpus to the article subset.
        category = force_metadata and "article" or nil,
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
            local force_document_metadata = force_metadata
                and type(document.tags) == "table"
                and #document.tags > 0
            local current = self:_updateExistingMetadata(
                existing,
                document,
                seen_at,
                report,
                force_document_metadata,
                force_metadata
            )
            managed_by_id[document.id] = current
            local has_local = force_metadata
                and self:_hasRecordedLocal(existing)
                or self:_hasLocal(existing)
            if not has_local
                and self:_isEligible(document, filters)
                and shouldRetryMissing(existing, document) then
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
    local previous_metadata_projection = self.sync_meta:get("metadata_projection_version")
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
    local metadata_projection_changed =
        previous_metadata_projection ~= METADATA_PROJECTION_VERSION
    local query_watermark
    if not full_scan then
        query_watermark = previous_query_after or previous_watermark
    end
    -- A projection-version change needs a metadata-only backfill so already
    -- downloaded documents receive newly-supported fields (currently Reader
    -- tags -> KOReader keywords). Do not turn that into a full HTML/content
    -- rescan: the metadata LIST already contains the required tag values.
    local metadata_query_watermark = query_watermark
    if metadata_projection_changed then
        metadata_query_watermark = nil
    end

    local report = {
        mode = full_scan and "full" or "incremental",
        started_at = started_at,
        previous_watermark = previous_watermark,
        filter_scope = current_filter_scope,
        filter_scope_changed = filter_scope_changed,
        metadata_projection_version = METADATA_PROJECTION_VERSION,
        metadata_projection_backfill = metadata_projection_changed,
        metadata_pages = 0,
        content_pages = 0,
        metadata_seen = 0,
        child_records = 0,
        duplicates_ignored = 0,
        downloaded = 0,
        unchanged = 0,
        images_downloaded = 0,
        images_reused = 0,
        images_failed = 0,
        images_skipped = 0,
        image_bytes = 0,
        metadata_updated = 0,
        metadata_invalidate_paths = {},
        location_moved = 0,
        content_refresh_deferred = 0,
        filtered_out = 0,
        unsupported_categories = 0,
        nonretryable_skipped = 0,
        retryable_item_errors = 0,
        retryable_error_stages = {},
        errors = 0,
        watermark_advanced = false,
    }

    self.sync_meta:set("document_scan_started_at", started_at)

    local managed_by_id, pending_new = {}, {}
    for _, existing in ipairs(self.repository:listManaged()) do
        managed_by_id[existing.reader_id] = existing
        -- Incremental syncs trust the durable local-presence bit and verify
        -- only documents that actually changed. Full scans remain the explicit
        -- repair path that checks every managed path on disk.
        local has_local = full_scan
            and self:_hasLocal(existing)
            or self:_hasRecordedLocal(existing)
        if not has_local
            and filters.locations[existing.location]
            and filters.categories[existing.category]
            and SUPPORTED_CATEGORIES[existing.category]
            and shouldRetryMissing(existing, nil) then
            pending_new[existing.reader_id] = true
        end
    end

    local metadata_ok, metadata_err = self:_scanMetadata(
        metadata_query_watermark,
        filters,
        managed_by_id,
        pending_new,
        report,
        started_epoch,
        metadata_projection_changed
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
        report.proposed_metadata_projection_version = METADATA_PROJECTION_VERSION
        report.watermark = watermark
        report.query_after = query_after
        report.watermark_advanced = previous_watermark ~= watermark
        if options.defer_watermark ~= true then
            self.sync_meta:set("document_watermark", watermark)
            self.sync_meta:set("document_query_after", query_after)
            self.sync_meta:set("document_filter_scope", current_filter_scope)
            self.sync_meta:set("metadata_projection_version", METADATA_PROJECTION_VERSION)
            self.sync_meta:set("last_successful_sync_at", completed_at)
            if full_scan then self.sync_meta:set("last_full_scan_at", completed_at) end
        end
    end

    return report
end

DocumentsSync.DEFAULT_OVERLAP_SECONDS = DEFAULT_OVERLAP_SECONDS
DocumentsSync.HTML_PAGE_LIMIT = HTML_PAGE_LIMIT
DocumentsSync.METADATA_PROJECTION_VERSION = METADATA_PROJECTION_VERSION
DocumentsSync.SUPPORTED_CATEGORIES = SUPPORTED_CATEGORIES
DocumentsSync._metadataChanged = metadataChanged
DocumentsSync._filterScope = filterScope
DocumentsSync._shouldRetryMissing = shouldRetryMissing

return DocumentsSync
