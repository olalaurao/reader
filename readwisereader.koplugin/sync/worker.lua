-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = {}

local NETWORK_UNAVAILABLE_KINDS = {
    offline = true,
    timeout = true,
    tls = true,
    unknown = true,
}

local function isNetworkUnavailable(err)
    return err ~= nil and NETWORK_UNAVAILABLE_KINDS[err.kind] == true
end

local function probeReader(reader)
    local reachable, probe_err = reader:validateToken()
    if reachable == true then
        return true
    end
    return false, probe_err or {
        kind = "unknown",
        retryable = true,
        message = "Readwise reachability probe failed without a classified error.",
    }
end

local function annotationQueueStatus(local_queue_report, offline)
    local_queue_report = local_queue_report or {}
    if (local_queue_report.documents_authoritative or 0) <= 0 then
        return nil
    end
    local partial = (local_queue_report.scan_errors or 0) > 0
        or (local_queue_report.queue_errors or 0) > 0
        or (local_queue_report.documents_skipped or 0) > 0
    if offline then
        return partial and "queued_offline_partial" or "queued_offline"
    end
    return partial and "queued_remote_unavailable_partial"
        or "queued_remote_unavailable"
end

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
    local AnnotationsRepository = require("storage/annotations")
    local DocumentsRepository = require("storage/documents")
    local QueueRepository = require("storage/queue")
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
    local Readwise = require("api/readwise")
    local DocumentsSync = require("sync/documents")
    local AnnotationSync = require("sync/annotations")
    local AnnotationUpload = require("sync/annotation_upload")
    local AnnotationBacklog = require("sync/annotation_backlog")
    local AnnotationMutations = require("sync/annotation_mutations")
    local Archive = require("sync/archive")
    local KOReaderAnnotations = require("koreader/annotations")
    local KOReaderStatus = require("koreader/status")
    local logger = require("logger")
    local util = require("util")

    local config = Config:new()
    local db
    local stage = "bootstrap"

    local ok, report, err = pcall(function()
        stage = "db_open"
        -- Trapper's child process must not manipulate UIManager or KOReader
        -- settings/cache owned by the parent. It may perform network work,
        -- atomic file installs and durable SQLite writes.
        db = DB:new()
        local repository = DocumentsRepository:new{ db = db }
        local annotations_repository = AnnotationsRepository:new{ db = db }
        local queue_repository = QueueRepository:new{ db = db }
        local sync_meta = SyncMeta:new{ db = db }
        local http = Http:new()
        local reader = Reader:new{
            http = http,
            config = config,
        }
        local readwise = Readwise:new{
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

        -- Phase O: local annotation discovery and durable queueing happen
        -- before any remote document request. This makes Sync now useful while
        -- offline and guarantees a reboot cannot erase a queued annotation.
        queue_repository:recoverStaleInFlight(os.time())

        local archive_enabled = config:getArchiveFinished()
        local archive_status = KOReaderStatus:new()
        local archiver = Archive:new{
            documents = repository,
            queue = queue_repository,
            status = archive_status,
            reader = reader,
            hasher = Hash,
        }
        local archive_local_report = {
            status = archive_enabled and "not_run" or "disabled",
            documents_seen = 0,
            finished_detected = 0,
            queued = 0,
            already_archived = 0,
            cancelled = 0,
            skipped = 0,
            scan_errors = 0,
        }
        if archive_enabled then
            stage = "archive_discovery"
            archive_local_report = archiver:queueAll()
        end

        local adapter = KOReaderAnnotations:new{ hasher = Hash }
        local scanner = AnnotationSync:new{
            documents = repository,
            annotations = annotations_repository,
            adapter = adapter,
        }
        local uploader = AnnotationUpload:new{
            documents = repository,
            annotations = annotations_repository,
            queue = queue_repository,
            adapter = adapter,
            reader = reader,
            hasher = Hash,
        }

        -- Phase O closes the staging limitation from Phases L/N: discover
        -- new create work across every locally-present Reader-managed document,
        -- not only whichever document happens to be open when Sync now runs.
        -- Destructive/note mutations remain bounded to the current document.
        local backlog = AnnotationBacklog:new{
            documents = repository,
            scanner = scanner,
            uploader = uploader,
        }
        stage = "annotation_backlog"
        local local_queue_report = backlog:queueAll(options.current_path)
        local annotation_sync_status = local_queue_report.status or "ok"
        local current_managed = local_queue_report.current_managed == true
        local current_scan_authoritative =
            local_queue_report.current_scan_authoritative == true

        local function applyAnnotationDefaults(sync_report)
            sync_report.annotation_documents_scanned =
                local_queue_report.documents_seen or 0
            sync_report.annotation_documents_authoritative =
                local_queue_report.documents_authoritative or 0
            sync_report.annotation_documents_skipped =
                local_queue_report.documents_skipped or 0
            sync_report.annotation_scan_errors =
                local_queue_report.scan_errors or 0
            sync_report.annotation_scan_exceptions =
                local_queue_report.scan_exceptions or 0
            sync_report.annotation_normalize_exceptions =
                local_queue_report.normalize_exceptions or 0
            sync_report.annotation_queue_errors =
                local_queue_report.queue_errors or 0
            sync_report.annotation_queue_exceptions =
                local_queue_report.queue_exceptions or 0
            sync_report.annotation_repository_source =
                local_queue_report.repository_source or "unknown"
            sync_report.annotation_repository_fallback =
                local_queue_report.repository_fallback == true
            sync_report.annotation_current_status =
                local_queue_report.current_status or "unknown"
            sync_report.annotation_scanned = local_queue_report.scanned or 0
            sync_report.highlights_created = 0
            sync_report.highlights_reconciled = 0
            sync_report.highlights_already_linked =
                local_queue_report.already_linked or 0
            sync_report.highlights_unmatched = local_queue_report.unmatched or 0
            sync_report.highlight_creates_blocked = local_queue_report.blocked or 0
            sync_report.highlight_marker_verified = 0
            sync_report.highlight_creates_queued = local_queue_report.queued or 0
            sync_report.highlight_queue_processed = 0
            sync_report.highlight_create_deferred = 0
            sync_report.highlight_create_auth_waiting = 0
            sync_report.highlight_queue_waiting =
                queue_repository:countCreateWaiting()
            sync_report.notes_updated = 0
            sync_report.notes_reconciled = 0
            sync_report.note_conflicts = 0
            sync_report.annotation_mutations_blocked = 0
            sync_report.local_deletions_detected = 0
            sync_report.remote_deletions = 0
            sync_report.deletions_retained = 0
            sync_report.annotation_remote_errors = 0
            sync_report.legacy_annotation_links_accepted = 0
            sync_report.durable_link_without_marker_accepted = 0
            sync_report.v2_annotation_pages_scanned = 0
            sync_report.v2_annotation_mappings_resolved = 0
            sync_report.v2_remote_note_reads = 0
            sync_report.v2_note_updates = 0
            sync_report.reader_note_verification_reads = 0
            sync_report.reader_note_propagation_misses = 0
            sync_report.reader_v3_note_repairs = 0
            sync_report.reader_note_repairs = 0
            sync_report.delete_cross_api_identity_verified = 0
            sync_report.reader_delete_verification_reads = 0
            sync_report.reader_deletions_verified = 0
            sync_report.delete_verification_pending = 0
            sync_report.annotation_sync_status = annotation_sync_status

            sync_report.archive_enabled = archive_enabled
            sync_report.archive_documents_scanned =
                archive_local_report.documents_seen or 0
            sync_report.archive_finished_detected =
                archive_local_report.finished_detected or 0
            sync_report.archive_intents_queued =
                archive_local_report.queued or 0
            sync_report.archive_already_archived =
                archive_local_report.already_archived or 0
            sync_report.archive_cancelled =
                archive_local_report.cancelled or 0
            sync_report.archive_documents_skipped =
                archive_local_report.skipped or 0
            sync_report.archive_scan_errors =
                archive_local_report.scan_errors or 0
            sync_report.archive_queue_processed = 0
            sync_report.documents_archived = 0
            sync_report.archive_reconciled = 0
            sync_report.archive_blocked = 0
            sync_report.archive_deferred = 0
            sync_report.archive_auth_waiting = 0
            sync_report.archive_remote_errors = 0
            sync_report.archive_queue_waiting =
                queue_repository:countArchiveWaiting()
            sync_report.content_refresh_pending_total =
                sync_report.content_refresh_pending_total
                or repository:countContentRefreshPending()
        end

        local function localQueueOnlyReport(preflight_err)
            local offline = options.network_available == false
                or isNetworkUnavailable(preflight_err)
            local local_report = {
                mode = offline and "offline" or "remote_unavailable",
                errors = 0,
                metadata_pages = 0,
                content_pages = 0,
                duplicates_ignored = 0,
                postprocess = {},
                watermark_advanced = false,
                network_available = false,
                remote_preflight = preflight_err and preflight_err.kind
                    or (options.network_available == false and "local_offline_hint" or "unknown"),
                storage_available_before =
                    storage_before and storage_before.available or nil,
            }
            applyAnnotationDefaults(local_report)
            local queue_status = annotationQueueStatus(local_queue_report, offline)
            if queue_status then
                local_report.annotation_sync_status = queue_status
            end
            local storage_after = util.diskUsage(config:getDownloadDirectory())
            local_report.storage_available_after =
                storage_after and storage_after.available or nil
            return local_report
        end

        if options.network_available == false then
            return localQueueOnlyReport(nil)
        end

        -- The target PW3 can report stale/incorrect local network state while
        -- native Kindle Airplane Mode is active. Before any queue processing,
        -- mutation, or document request, prove real Readwise reachability with
        -- the existing read-only auth endpoint. A failed probe leaves all local
        -- annotation work durably queued and performs no remote write.
        stage = "remote_preflight"
        local reachable, preflight_err = probeReader(reader)
        if not reachable then
            return localQueueOnlyReport(preflight_err)
        end

        -- Process every durable create, including work left by a previous
        -- KOReader process, before the document feed. New local work from all
        -- authoritative managed sidecars was already queued above.
        stage = "create_queue_processing"
        local queue_report = uploader:processQueue()

        stage = "document_sync"
        local sync_report, sync_err = syncer:sync{
            full_rescan = options.full_rescan == true,
            defer_watermark = true,
        }
        if not sync_report then
            return nil, sync_err
        end

        applyAnnotationDefaults(sync_report)
        sync_report.remote_preflight = "passed"
        sync_report.network_available = true
        sync_report.highlights_created = queue_report.created or 0
        sync_report.highlights_reconciled = queue_report.reconciled or 0
        sync_report.highlights_unmatched =
            sync_report.highlights_unmatched + (queue_report.unmatched or 0)
        sync_report.highlight_creates_blocked =
            sync_report.highlight_creates_blocked + (queue_report.blocked or 0)
        sync_report.highlight_marker_verified = queue_report.marker_verified or 0
        sync_report.highlight_queue_processed = queue_report.processed or 0
        sync_report.highlight_create_deferred = queue_report.deferred or 0
        sync_report.highlight_create_auth_waiting = queue_report.auth_waiting or 0
        sync_report.highlight_queue_waiting = queue_report.waiting_after
            or queue_repository:countCreateWaiting()
        sync_report.annotation_remote_errors = queue_report.remote_errors or 0

        if current_managed and current_scan_authoritative then
            stage = "annotation_mutations"
            local mutations = AnnotationMutations:new{
                documents = repository,
                annotations = annotations_repository,
                adapter = adapter,
                reader = reader,
                readwise = readwise,
                propagate_deletions = config:getPropagateHighlightDeletions(),
            }
            local mutation_report, mutation_err = mutations:syncPath(options.current_path)
            if not mutation_report then
                sync_report.annotation_sync_status = "mutation_error"
                sync_report.annotation_error_kind = mutation_err
                    and mutation_err.kind or "unknown"
                sync_report.annotation_remote_errors =
                    sync_report.annotation_remote_errors + 1
            else
                sync_report.notes_updated = mutation_report.notes_updated or 0
                sync_report.notes_reconciled = mutation_report.notes_reconciled or 0
                sync_report.note_conflicts = mutation_report.conflicts or 0
                sync_report.annotation_mutations_blocked = mutation_report.blocked or 0
                sync_report.local_deletions_detected =
                    mutation_report.deletions_detected or 0
                sync_report.remote_deletions =
                    (mutation_report.deletions_remote or 0)
                    + (mutation_report.deletions_already_remote or 0)
                sync_report.deletions_retained =
                    mutation_report.deletions_retained or 0
                sync_report.annotation_remote_errors =
                    sync_report.annotation_remote_errors
                    + (mutation_report.remote_errors or 0)
                sync_report.legacy_annotation_links_accepted =
                    mutation_report.legacy_identity_accepted or 0
                sync_report.durable_link_without_marker_accepted =
                    mutation_report.durable_link_identity_accepted or 0
                sync_report.v2_annotation_pages_scanned =
                    mutation_report.v2_pages_scanned or 0
                sync_report.v2_annotation_mappings_resolved =
                    mutation_report.v2_mappings_resolved or 0
                sync_report.v2_remote_note_reads =
                    mutation_report.v2_remote_note_reads or 0
                sync_report.v2_note_updates =
                    mutation_report.v2_note_updates or 0
                sync_report.reader_note_verification_reads =
                    mutation_report.reader_note_verification_reads or 0
                sync_report.reader_note_propagation_misses =
                    mutation_report.reader_note_propagation_misses or 0
                sync_report.reader_v3_note_repairs =
                    mutation_report.reader_v3_note_repairs or 0
                sync_report.reader_note_repairs =
                    mutation_report.reader_note_repairs or 0
                sync_report.delete_cross_api_identity_verified =
                    mutation_report.delete_cross_api_identity_verified or 0
                sync_report.reader_delete_verification_reads =
                    mutation_report.reader_delete_verification_reads or 0
                sync_report.reader_deletions_verified =
                    mutation_report.reader_deletions_verified or 0
                sync_report.delete_verification_pending =
                    mutation_report.delete_verification_pending or 0
            end
        end

        if archive_enabled then
            stage = "archive_queue_processing"
            local archive_report = archiver:processQueue()
            sync_report.archive_queue_processed = archive_report.processed or 0
            sync_report.documents_archived = archive_report.archived or 0
            sync_report.archive_reconciled = archive_report.already_archived or 0
            sync_report.archive_cancelled =
                sync_report.archive_cancelled + (archive_report.cancelled or 0)
            sync_report.archive_blocked = archive_report.blocked or 0
            sync_report.archive_deferred = archive_report.deferred or 0
            sync_report.archive_auth_waiting = archive_report.auth_waiting or 0
            sync_report.archive_remote_errors = archive_report.remote_errors or 0
            sync_report.archive_queue_waiting = archive_report.waiting_after
                or queue_repository:countArchiveWaiting()

            for _, update in ipairs(archive_report.location_updates or {}) do
                if type(update.path) == "string" and update.path ~= "" then
                    postprocess(update.path).location = update.location
                end
            end
        end

        stage = "finalize_report"
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
        logger.warn("ReadwiseReader: [SYNC] worker failed safely at stage", stage)
        return nil, {
            kind = "worker",
            stage = stage,
            retryable = true,
            message = "Document sync worker failed safely.",
        }
    end
    return report, err
end

Worker._copyMetadata = copyMetadata
Worker._isNetworkUnavailable = isNetworkUnavailable
Worker._probeReader = probeReader
Worker._annotationQueueStatus = annotationQueueStatus

return Worker
