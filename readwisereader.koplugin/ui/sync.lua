-- SPDX-License-Identifier: AGPL-3.0-only

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Worker = require("sync/worker")
local _ = require("gettext")

local SyncUI = {}
SyncUI.__index = SyncUI

local function megabytes(bytes)
    local value = tonumber(bytes)
    if not value then return _("unknown") end
    return string.format("%.1f MB", value / 1024 / 1024)
end

local function retryableStagesText(stages)
    local keys = {}
    for key, count in pairs(stages or {}) do
        if tonumber(count) and count > 0 then keys[#keys + 1] = key end
    end
    table.sort(keys)
    if #keys == 0 then return _("none") end
    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = string.format("%s=%d", key, stages[key])
    end
    return table.concat(parts, ",")
end

local function errorText(err)
    if not err then
        return _("Document sync failed safely.")
    elseif err.kind == "auth" then
        return _("Readwise rejected the access token. Check Account settings and try again.")
    elseif err.kind == "offline" then
        return _("The network is unavailable. Turn Wi-Fi on outside the plugin and try again.")
    elseif err.kind == "timeout" then
        return _("The Reader sync timed out. Nothing incomplete replaced a valid local document.")
    elseif err.kind == "tls" then
        return _("A secure TLS connection to Readwise could not be established.")
    elseif err.kind == "rate_limit" then
        return _("Readwise rate limit reached. Try the sync again later.")
    elseif err.kind == "pagination" then
        return _("Reader pagination became inconsistent, so the sync stopped without advancing its watermark.")
    elseif err.kind == "cancelled" then
        return _("Document sync cancelled. Completed files were kept; the watermark was not advanced.")
    elseif err.kind == "worker" then
        return string.format(
            _("Document sync failed safely at stage: %s. Local documents and queued work were preserved."),
            err.stage or _("unknown")
        )
    end
    return _("Document sync failed safely. Existing local documents were kept.")
end

local function summaryText(report)
    local mode
    if report.mode == "full" then
        mode = _("full")
    elseif report.mode == "offline" then
        mode = _("offline / local queue")
    elseif report.mode == "remote_unavailable" then
        mode = _("local queue / remote unavailable")
    else
        mode = _("incremental")
    end
    local lines = {
        _("Readwise document sync complete"),
        "",
        string.format(_("Mode: %s"), mode),
        string.format(_("Downloaded: %d"), report.downloaded or 0),
        string.format(_("Already local / unchanged: %d"), report.unchanged or 0),
        string.format(_("Image candidates found: %d"), report.image_candidates or 0),
        string.format(_("Responsive images promoted: %d"), report.image_responsive_promoted or 0),
        string.format(_("Images downloaded: %d"), report.images_downloaded or 0),
        string.format(_("Images reused: %d"), report.images_reused or 0),
        string.format(_("Images skipped by limits/settings: %d"), report.images_skipped or 0),
        string.format(_("Images unavailable/unsupported: %d"), report.images_failed or 0),
        string.format(_("Image bytes cached: %s"), megabytes(report.image_bytes or 0)),
        string.format(_("Raw PDF/EPUB downloaded: %d"), report.raw_sources_downloaded or 0),
        string.format(_("Raw-source HTML fallbacks: %d"), report.raw_html_fallbacks or 0),
        string.format(_("Raw bytes downloaded: %s"), megabytes(report.raw_source_bytes or 0)),
        string.format(_("Metadata updated: %d"), report.metadata_updated or 0),
        string.format(
            _("Reader tag metadata backfill: %s"),
            report.metadata_projection_backfill and _("yes") or _("no")
        ),
        string.format(_("Reader location changes: %d"), report.location_moved or 0),
        string.format(_("Content refresh deferred safely: %d"), report.content_refresh_deferred or 0),
        string.format(_("Filtered out: %d"), report.filtered_out or 0),
        string.format(_("Metadata documents seen: %d"), report.metadata_seen or 0),
        string.format(_("Active filters: %s"), report.filter_scope or _("unknown")),
        string.format(_("Skipped (not materializable): %d"), report.nonretryable_skipped or 0),
        string.format(_("Retryable item errors: %d"), report.retryable_item_errors or 0),
        string.format(_("Retryable stages: %s"), retryableStagesText(report.retryable_error_stages)),
        string.format(_("Storage available after sync: %s"), megabytes(report.storage_available_after)),
        string.format(_("Errors: %d"), report.errors or 0),
        string.format(_("Metadata write errors: %d"), report.postprocess_metadata_errors or 0),
        string.format(_("Collection write errors: %d"), report.postprocess_collection_errors or 0),
        "",
        string.format(_("Metadata pages: %d"), report.metadata_pages or 0),
        string.format(_("Content pages: %d"), report.content_pages or 0),
        string.format(_("Duplicate API records ignored: %d"), report.duplicates_ignored or 0),
        "",
        string.format(_("Remote preflight: %s"), report.remote_preflight or _("not run")),
        string.format(_("Annotation sync: %s"), report.annotation_sync_status or _("not run")),
        string.format(_("Managed annotation documents scanned: %d"), report.annotation_documents_scanned or 0),
        string.format(_("Authoritative annotation sidecars: %d"), report.annotation_documents_authoritative or 0),
        string.format(_("Annotation documents skipped safely: %d"), report.annotation_documents_skipped or 0),
        string.format(_("Annotation scan errors: %d"), report.annotation_scan_errors or 0),
        string.format(_("Annotation scan exceptions isolated: %d"), report.annotation_scan_exceptions or 0),
        string.format(_("Annotation normalize exceptions isolated: %d"), report.annotation_normalize_exceptions or 0),
        string.format(_("Annotation queue errors: %d"), report.annotation_queue_errors or 0),
        string.format(_("Annotation queue exceptions isolated: %d"), report.annotation_queue_exceptions or 0),
        string.format(_("Annotation repository source: %s"), report.annotation_repository_source or _("unknown")),
        string.format(
            _("Annotation repository fallback: %s"),
            report.annotation_repository_fallback and _("yes") or _("no")
        ),
        string.format(_("Current annotation document status: %s"), report.annotation_current_status or _("unknown")),
        string.format(_("Managed-document highlights scanned: %d"), report.annotation_scanned or 0),
        string.format(_("Highlights created: %d"), report.highlights_created or 0),
        string.format(_("Highlights reconciled safely: %d"), report.highlights_reconciled or 0),
        string.format(_("Highlights already linked: %d"), report.highlights_already_linked or 0),
        string.format(_("Highlights unmatched/ambiguous: %d"), report.highlights_unmatched or 0),
        string.format(_("Highlight creates blocked safely: %d"), report.highlight_creates_blocked or 0),
        string.format(_("Highlight creates queued durably: %d"), report.highlight_creates_queued or 0),
        string.format(_("Create queue items processed: %d"), report.highlight_queue_processed or 0),
        string.format(_("Create retries deferred: %d"), report.highlight_create_deferred or 0),
        string.format(_("Create auth waits: %d"), report.highlight_create_auth_waiting or 0),
        string.format(_("Create queue waiting after sync: %d"), report.highlight_queue_waiting or 0),
        string.format(_("Reconciliation markers verified: %d"), report.highlight_marker_verified or 0),
        string.format(_("Notes updated: %d"), report.notes_updated or 0),
        string.format(_("Note updates reconciled: %d"), report.notes_reconciled or 0),
        string.format(_("Note conflicts blocked: %d"), report.note_conflicts or 0),
        string.format(_("Annotation mutations blocked safely: %d"), report.annotation_mutations_blocked or 0),
        string.format(_("Local highlight deletions detected: %d"), report.local_deletions_detected or 0),
        string.format(_("Remote highlight deletions: %d"), report.remote_deletions or 0),
        string.format(_("Deletions retained remotely (propagation off): %d"), report.deletions_retained or 0),
        string.format(_("Legacy linked highlights accepted safely: %d"), report.legacy_annotation_links_accepted or 0),
        string.format(_("Durable linked highlights accepted without marker: %d"), report.durable_link_without_marker_accepted or 0),
        string.format(_("Readwise v2 annotation pages scanned: %d"), report.v2_annotation_pages_scanned or 0),
        string.format(_("Readwise v2 mappings resolved: %d"), report.v2_annotation_mappings_resolved or 0),
        string.format(_("Readwise v2 remote-note reads: %d"), report.v2_remote_note_reads or 0),
        string.format(_("Readwise v2 note updates: %d"), report.v2_note_updates or 0),
        string.format(_("Reader note verification reads: %d"), report.reader_note_verification_reads or 0),
        string.format(_("Reader propagation misses: %d"), report.reader_note_propagation_misses or 0),
        string.format(_("Reader v3 repair PATCHes: %d"), report.reader_v3_note_repairs or 0),
        string.format(_("Reader note repairs completed: %d"), report.reader_note_repairs or 0),
        string.format(_("Delete cross-API identity verified: %d"), report.delete_cross_api_identity_verified or 0),
        string.format(_("Reader delete verification reads: %d"), report.reader_delete_verification_reads or 0),
        string.format(_("Reader deletions verified: %d"), report.reader_deletions_verified or 0),
        string.format(_("Delete verification pending: %d"), report.delete_verification_pending or 0),
        string.format(_("Annotation remote errors: %d"), report.annotation_remote_errors or 0),
        "",
        string.format(
            _("Archive finished documents: %s"),
            report.archive_enabled == false and _("off") or _("on")
        ),
        string.format(_("Finished documents scanned: %d"), report.archive_documents_scanned or 0),
        string.format(_("Finished status detected: %d"), report.archive_finished_detected or 0),
        string.format(_("Archive intents queued durably: %d"), report.archive_intents_queued or 0),
        string.format(_("Archive queue items processed: %d"), report.archive_queue_processed or 0),
        string.format(_("Reader documents archived: %d"), report.documents_archived or 0),
        string.format(_("Archive state reconciled remotely: %d"), report.archive_reconciled or 0),
        string.format(_("Already archived locally known: %d"), report.archive_already_archived or 0),
        string.format(_("Archive intents cancelled safely: %d"), report.archive_cancelled or 0),
        string.format(_("Archive documents skipped safely: %d"), report.archive_documents_skipped or 0),
        string.format(_("Archive status scan errors: %d"), report.archive_scan_errors or 0),
        string.format(_("Archive operations blocked safely: %d"), report.archive_blocked or 0),
        string.format(_("Archive retries deferred: %d"), report.archive_deferred or 0),
        string.format(_("Archive auth waits: %d"), report.archive_auth_waiting or 0),
        string.format(_("Archive queue waiting after sync: %d"), report.archive_queue_waiting or 0),
        string.format(_("Archive remote errors: %d"), report.archive_remote_errors or 0),
    }

    if report.errors and report.errors > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = _("The incremental watermark was not advanced because at least one item failed.")
    elseif report.watermark_advanced then
        lines[#lines + 1] = ""
        lines[#lines + 1] = _("Incremental watermark updated.")
    end
    return table.concat(lines, "\n")
end

function SyncUI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        sync_meta = assert(options.sync_meta, "sync_meta is required"),
        collections = assert(options.collections, "collections is required"),
        koreader_documents = assert(options.koreader_documents, "koreader_documents is required"),
        get_current_path = options.get_current_path or function() return nil end,
        worker = options.worker or Worker,
    }, self)
end

function SyncUI:getSyncMenuItem()
    return {
        text = _("Sync now"),
        keep_menu_open = true,
        callback = function()
            self:syncNow(false)
        end,
    }
end

function SyncUI:getFullRescanMenuItem()
    return {
        text = _("Full document rescan"),
        keep_menu_open = true,
        callback = function()
            self:confirmAndRun(true)
        end,
    }
end

function SyncUI:getStatusMenuItem()
    return {
        text = _("Sync status"),
        keep_menu_open = true,
        callback = function()
            self:showStatus()
        end,
    }
end

function SyncUI:_preflight()
    if not self.config:hasAccessToken() then
        UIManager:show(InfoMessage:new{ text = _("No access token is configured.") })
        return false
    end
    return true
end

function SyncUI:syncNow(full_rescan)
    if not self:_preflight() then
        return
    end

    if full_rescan then
        self:confirmAndRun(true)
        return
    end

    if self.sync_meta:get("document_watermark") == nil then
        self:confirmAndRun(false)
        return
    end
    self:_run(false)
end

function SyncUI:confirmAndRun(full_rescan)
    if not self:_preflight() then
        return
    end
    local text
    if full_rescan then
        text = _([[Run a full document rescan using the current Documents filters?

Existing managed files will not be blindly overwritten. This may take a while.]])
    else
        text = _([[This is the first document sync. It will download every supported document matching the current Documents filters.

Review Settings → Documents first if you want a smaller initial sync.

Continue?]])
    end
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = _("Continue"),
        ok_callback = function()
            self:_run(full_rescan)
        end,
    })
end

function SyncUI:_run(full_rescan)
    local current_path = self.get_current_path()
    Trapper:wrap(function()
        local completed, report, err = Trapper:dismissableRunInSubprocess(function()
            return self.worker:run{
                full_rescan = full_rescan == true,
                current_path = current_path,
            }
        end, _([[Syncing Reader documents…

Tap to cancel. Local annotations are queued first. Readwise reachability is then verified read-only before any remote write; the incremental watermark is committed only after a successful remote sync.]]))

        if not completed then
            UIManager:show(InfoMessage:new{
                text = _("Document sync cancelled. Completed files were kept; the watermark was not advanced."),
            })
            return
        end
        if not report then
            UIManager:show(InfoMessage:new{ text = errorText(err) })
            return
        end

        -- Trapper child work deliberately avoids KOReader settings/cache.
        -- Apply metadata and collections in the parent before committing the
        -- incremental watermark.
        -- Collections keep an in-memory cache. The child may have run for minutes,
        -- so refresh it once before applying a large parent-side postprocess batch.
        -- Without this, stale collection state can turn harmless idempotent writes
        -- into per-item failures after a full materialization.
        if #(report.postprocess or {}) > 0 then
            local collection_refresh_ok = pcall(self.collections.refresh, self.collections)
            if not collection_refresh_ok then
                report.errors = (report.errors or 0) + 1
            end
        end

        report.postprocess_metadata_errors = 0
        report.postprocess_collection_errors = 0
        local metadata_writes_succeeded = 0
        for _, item in ipairs(report.postprocess or {}) do
            if item.metadata then
                local call_ok, metadata_ok = pcall(
                    self.koreader_documents.writeMetadata,
                    self.koreader_documents,
                    item.path,
                    item.metadata
                )
                if not call_ok or not metadata_ok then
                    report.errors = (report.errors or 0) + 1
                    report.postprocess_metadata_errors = report.postprocess_metadata_errors + 1
                else
                    metadata_writes_succeeded = metadata_writes_succeeded + 1
                end
            end
            if item.location then
                local call_ok, collection_ok = pcall(
                    self.collections.syncLocation,
                    self.collections,
                    item.path,
                    item.location
                )
                if not call_ok or not collection_ok then
                    report.errors = (report.errors or 0) + 1
                    report.postprocess_collection_errors = report.postprocess_collection_errors + 1
                end
            end
        end

        if metadata_writes_succeeded > 0
            and type(self.koreader_documents.refreshExternalMetadataCaches) == "function" then
            local cache_ok, refreshed = pcall(
                self.koreader_documents.refreshExternalMetadataCaches,
                self.koreader_documents
            )
            if not cache_ok or refreshed == false then
                report.errors = (report.errors or 0) + 1
                report.postprocess_metadata_errors = report.postprocess_metadata_errors + 1
            end
        end

        if (report.errors or 0) == 0 and report.proposed_watermark then
            local final_meta = {
                document_watermark = report.proposed_watermark,
                document_query_after = report.proposed_query_after,
                document_filter_scope = report.proposed_filter_scope,
                metadata_projection_version = report.proposed_metadata_projection_version,
                last_successful_sync_at = report.completed_at,
            }
            if report.mode == "full" then
                final_meta.last_full_scan_at = report.completed_at
            end
            local committed = pcall(self.sync_meta.setMany, self.sync_meta, final_meta)
            if not committed then
                report.errors = (report.errors or 0) + 1
                report.watermark_advanced = false
            end
        else
            report.watermark_advanced = false
        end

        UIManager:show(InfoMessage:new{
            text = summaryText(report),
        })
    end)
end

function SyncUI:showStatus()
    local watermark = self.sync_meta:get("document_watermark")
    local last_success = self.sync_meta:get("last_successful_sync_at")
    local last_full = self.sync_meta:get("last_full_scan_at")
    local projection = self.sync_meta:get("metadata_projection_version")
    local lines = {
        _("Readwise document sync status"),
        "",
        string.format(_("Last successful sync: %s"), last_success or _("never")),
        string.format(_("Last full scan: %s"), last_full or _("never")),
        string.format(_("Incremental watermark: %s"), watermark or _("not set")),
        string.format(_("Metadata projection: %s"), projection or _("not applied")),
    }
    UIManager:show(InfoMessage:new{
        text = table.concat(lines, "\n"),
    })
end

SyncUI._errorText = errorText
SyncUI._summaryText = summaryText

return SyncUI
