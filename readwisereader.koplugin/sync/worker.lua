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
    local AnnotationMutations = require("sync/annotation_mutations")
    local KOReaderAnnotations = require("koreader/annotations")
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

        local sync_report, sync_err = syncer:sync{
            full_rescan = options.full_rescan == true,
            defer_watermark = true,
        }
        if not sync_report then
            return nil, sync_err
        end

        -- Phase L intentionally scans only the currently-open managed Reader
        -- document. This keeps manual Sync now responsive on the PW3 and avoids
        -- unexpectedly uploading historical local highlights from the whole
        -- library. Durable queued creates are reconciled before any retry.
        queue_repository:recoverStaleInFlight(os.time())
        sync_report.annotation_scanned = 0
        sync_report.highlights_created = 0
        sync_report.highlights_reconciled = 0
        sync_report.highlights_already_linked = 0
        sync_report.highlights_unmatched = 0
        sync_report.highlight_creates_blocked = 0
        sync_report.highlight_marker_verified = 0
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
        sync_report.annotation_sync_status = "no_current_document"

        if type(options.current_path) == "string" and options.current_path ~= "" then
            local current = repository:getByLocalPath(options.current_path)
            if current and current.is_managed == true and current.is_local_present == true then
                local adapter = KOReaderAnnotations:new{ hasher = Hash }
                local scanner = AnnotationSync:new{
                    documents = repository,
                    annotations = annotations_repository,
                    adapter = adapter,
                }
                local scan_report, annotation_scan_err = scanner:scanPath(options.current_path)
                if not scan_report then
                    sync_report.annotation_sync_status = "scan_error"
                    sync_report.annotation_error_kind = annotation_scan_err
                        and annotation_scan_err.kind or "unknown"
                elseif not scan_report.authoritative then
                    sync_report.annotation_sync_status = scan_report.status or "sidecar_not_authoritative"
                else
                    local uploader = AnnotationUpload:new{
                        documents = repository,
                        annotations = annotations_repository,
                        queue = queue_repository,
                        adapter = adapter,
                        reader = reader,
                        hasher = Hash,
                    }
                    local upload_report, upload_err = uploader:syncPath(options.current_path)
                    if not upload_report then
                        sync_report.annotation_sync_status = "upload_error"
                        sync_report.annotation_error_kind = upload_err
                            and upload_err.kind or "unknown"
                    else
                        sync_report.annotation_sync_status = upload_report.status or "ok"
                        sync_report.annotation_scanned = upload_report.scanned or 0
                        sync_report.highlights_created = upload_report.created or 0
                        sync_report.highlights_reconciled = upload_report.reconciled or 0
                        sync_report.highlights_already_linked = upload_report.already_linked or 0
                        sync_report.highlights_unmatched = upload_report.unmatched or 0
                        sync_report.highlight_creates_blocked = upload_report.blocked or 0
                        sync_report.highlight_marker_verified = upload_report.marker_verified or 0
                        sync_report.annotation_remote_errors = upload_report.remote_errors or 0

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
                        end
                    end
                end
            else
                sync_report.annotation_sync_status = "current_document_not_managed"
            end
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
