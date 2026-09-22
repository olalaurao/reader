-- SPDX-License-Identifier: AGPL-3.0-only

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Worker = require("sync/worker")
local _ = require("gettext")

local SyncUI = {}
SyncUI.__index = SyncUI

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
    end
    return _("Document sync failed safely. Existing local documents were kept.")
end

local function summaryText(report)
    local mode = report.mode == "full" and _("full") or _("incremental")
    local lines = {
        _("Readwise document sync complete"),
        "",
        string.format(_("Mode: %s"), mode),
        string.format(_("Downloaded: %d"), report.downloaded or 0),
        string.format(_("Already local / unchanged: %d"), report.unchanged or 0),
        string.format(_("Metadata updated: %d"), report.metadata_updated or 0),
        string.format(_("Reader location changes: %d"), report.location_moved or 0),
        string.format(_("Content refresh deferred safely: %d"), report.content_refresh_deferred or 0),
        string.format(_("Filtered out: %d"), report.filtered_out or 0),
        string.format(_("Errors: %d"), report.errors or 0),
        "",
        string.format(_("Metadata pages: %d"), report.metadata_pages or 0),
        string.format(_("Content pages: %d"), report.content_pages or 0),
        string.format(_("Duplicate API records ignored: %d"), report.duplicates_ignored or 0),
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
        worker = options.worker or Worker,
    }, self)
end

function SyncUI:getSyncMenuItem()
    return {
        text = _("Sync now (Gate 4)"),
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
    -- Deliberately inspect connectivity only; V1 never controls Wi-Fi.
    if not NetworkMgr:isOnline() then
        UIManager:show(InfoMessage:new{
            text = _("No internet connection. Turn Wi-Fi on outside the plugin and try again."),
        })
        return false
    end
    return true
end

function SyncUI:syncNow(full_rescan)
    if not self:_preflight() then
        return
    end
    if full_rescan or self.sync_meta:get("document_watermark") == nil then
        self:confirmAndRun(full_rescan)
        return
    end
    self:_run(full_rescan)
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
        text = _([[This is the first document sync. It will download every supported article matching the current Documents filters.

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
    Trapper:wrap(function()
        local completed, report, err = Trapper:dismissableRunInSubprocess(function()
            return self.worker:run{
                full_rescan = full_rescan == true,
            }
        end, _([[Syncing Reader documents…

Tap to cancel. Completed files are installed atomically; the incremental watermark is committed only after a successful sync.]]))

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

        -- The child process updates collection.lua. Reload the parent's
        -- in-memory ReadCollection view after it exits.
        self.collections:refresh()
        for _, filepath in ipairs(report.metadata_invalidate_paths or {}) do
            self.koreader_documents:invalidateMetadata(filepath)
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
    local lines = {
        _("Readwise document sync status"),
        "",
        string.format(_("Last successful sync: %s"), last_success or _("never")),
        string.format(_("Last full scan: %s"), last_full or _("never")),
        string.format(_("Incremental watermark: %s"), watermark or _("not set")),
    }
    UIManager:show(InfoMessage:new{
        text = table.concat(lines, "\n"),
    })
end

SyncUI._errorText = errorText
SyncUI._summaryText = summaryText

return SyncUI
