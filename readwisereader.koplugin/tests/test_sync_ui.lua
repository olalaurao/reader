-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubbedSyncUI(run, options)
    options = options or {}
    local module_names = {
        "ui/sync",
        "ui/widget/confirmbox",
        "ui/widget/infomessage",
        "ui/network/manager",
        "ui/trapper",
        "ui/uimanager",
        "sync/worker",
        "gettext",
    }
    local saved_loaded, saved_preload = {}, {}
    for _, name in ipairs(module_names) do
        saved_loaded[name] = package.loaded[name]
        saved_preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    local state = {
        shown = {},
        online = options.online ~= false,
        wrap_calls = 0,
        subprocess_calls = 0,
        refresh_calls = 0,
        metadata_writes = {},
        metadata_consumer_refreshes = 0,
        collection_writes = {},
        meta_writes = {},
        worker_calls = {},
    }

    package.preload["gettext"] = function()
        return function(value) return value end
    end
    package.preload["ui/widget/infomessage"] = function()
        return { new = function(_, value) value.kind = "info" return value end }
    end
    package.preload["ui/widget/confirmbox"] = function()
        return { new = function(_, value) value.kind = "confirm" return value end }
    end
    package.preload["ui/network/manager"] = function()
        return { isOnline = function() return state.online end }
    end
    package.preload["ui/uimanager"] = function()
        return {
            show = function(_, widget) state.shown[#state.shown + 1] = widget end,
        }
    end
    package.preload["ui/trapper"] = function()
        return {
            wrap = function(_, callback)
                state.wrap_calls = state.wrap_calls + 1
                callback()
                return true
            end,
            dismissableRunInSubprocess = function(_, task)
                state.subprocess_calls = state.subprocess_calls + 1
                if options.cancelled then return false end
                return true, task()
            end,
        }
    end
    package.preload["sync/worker"] = function()
        return {}
    end

    local ok, err = pcall(function()
        local SyncUI = require("ui/sync")
        run(SyncUI, state)
    end)

    for _, name in ipairs(module_names) do
        package.loaded[name] = saved_loaded[name]
        package.preload[name] = saved_preload[name]
    end
    if not ok then error(err) end
end

local function newUI(SyncUI, state, watermark, report, ui_options)
    ui_options = ui_options or {}
    return SyncUI:new{
        config = { hasAccessToken = function() return true end },
        sync_meta = {
            get = function(_, key)
                if key == "document_watermark" then return watermark end
                return nil
            end,
            set = function(_, key, value)
                state.meta_writes[key] = value
            end,
            setMany = function(_, values)
                if ui_options.meta_commit_ok == false then
                    error("simulated sync_meta commit failure")
                end
                for key, value in pairs(values) do
                    state.meta_writes[key] = value
                end
            end,
        },
        collections = {
            syncLocation = function(_, path, location)
                state.collection_writes[#state.collection_writes + 1] = {
                    path = path,
                    location = location,
                }
                return ui_options.collection_ok ~= false
            end,
            refresh = function()
                state.refresh_calls = state.refresh_calls + 1
                return true
            end,
        },
        koreader_documents = {
            writeMetadata = function(_, path, metadata)
                state.metadata_writes[#state.metadata_writes + 1] = {
                    path = path,
                    metadata = metadata,
                }
                return ui_options.metadata_ok ~= false
            end,
            refreshExternalMetadataCaches = function()
                state.metadata_consumer_refreshes = state.metadata_consumer_refreshes + 1
                return ui_options.metadata_cache_ok ~= false
            end,
        },
        get_current_path = function()
            return ui_options.current_path or "/Readwise/current.html"
        end,
        worker = {
            run = function(_, options)
                state.worker_calls[#state.worker_calls + 1] = options
                return report or {
                    mode = "incremental",
                    downloaded = 2,
                    unchanged = 3,
                    metadata_updated = 1,
                    location_moved = 1,
                    content_refresh_deferred = 0,
                    filtered_out = 4,
                    errors = 0,
                    metadata_pages = 1,
                    content_pages = 2,
                    duplicates_ignored = 0,
                    watermark_advanced = true,
                    proposed_watermark = "2026-09-22T20:00:00Z",
                    proposed_query_after = "2026-09-22T19:55:00Z",
                    completed_at = "2026-09-22T20:01:00Z",
                    postprocess = {
                        {
                            path = "/Readwise/a.html",
                            location = "later",
                            metadata = { title = "A" },
                        },
                    },
                }
            end,
        },
    }
end

return function()
    withStubbedSyncUI(function(SyncUI, state)
        local ui = newUI(SyncUI, state, "2026-09-22T20:00:00Z")
        ui:syncNow(false)
        assert(state.wrap_calls == 1)
        assert(state.subprocess_calls == 1)
        assert(#state.worker_calls == 1)
        assert(state.worker_calls[1].full_rescan == false)
        assert(state.worker_calls[1].current_path == "/Readwise/current.html")
        assert(state.worker_calls[1].network_available == true)
        assert(#state.metadata_writes == 1)
        assert(state.metadata_consumer_refreshes == 1)
        assert(#state.collection_writes == 1)
        assert(state.meta_writes.document_watermark == "2026-09-22T20:00:00Z")
        assert(state.meta_writes.document_query_after == "2026-09-22T19:55:00Z")
        assert(state.shown[#state.shown].text:find("Downloaded: 2", 1, true))
        assert(state.shown[#state.shown].text:find("Highlights created: 0", 1, true))
        assert(state.shown[#state.shown].text:find("Notes updated: 0", 1, true))
        assert(state.shown[#state.shown].text:find("Remote highlight deletions: 0", 1, true))
    end)

    withStubbedSyncUI(function(SyncUI, state)
        local ui = newUI(SyncUI, state, "watermark", {
            mode = "incremental",
            downloaded = 0,
            unchanged = 0,
            metadata_updated = 0,
            location_moved = 0,
            content_refresh_deferred = 0,
            filtered_out = 0,
            errors = 0,
            metadata_pages = 1,
            content_pages = 0,
            duplicates_ignored = 0,
            proposed_watermark = "2026-09-22T20:00:00Z",
            proposed_query_after = "2026-09-22T19:55:00Z",
            proposed_filter_scope = "locations=later,new;categories=article",
            proposed_metadata_projection_version = "reader-tags-v2",
            completed_at = "2026-09-22T20:01:00Z",
            postprocess = {},
        })
        ui:syncNow(false)
        assert(state.refresh_calls == 0, "no-op sync must not refresh Collections")
        assert(#state.metadata_writes == 0)
        assert(state.metadata_consumer_refreshes == 0)
        assert(#state.collection_writes == 0)
    end)

    withStubbedSyncUI(function(SyncUI, state)
        local ui = newUI(SyncUI, state, nil)
        ui:syncNow(false)
        assert(state.wrap_calls == 0)
        assert(state.shown[#state.shown].kind == "confirm")
        state.shown[#state.shown].ok_callback()
        assert(state.wrap_calls == 1)
        assert(#state.worker_calls == 1)
    end)

    withStubbedSyncUI(function(SyncUI, state)
        local ui = newUI(SyncUI, state, "watermark", nil, { collection_ok = false })
        ui:syncNow(false)
        assert(next(state.meta_writes) == nil, "parent postprocess failure must not advance watermark")
        assert(state.shown[#state.shown].text:find("Errors: 1", 1, true))
        assert(state.shown[#state.shown].text:find("not advanced", 1, true))
    end)

    withStubbedSyncUI(function(SyncUI, state)
        local ui = newUI(SyncUI, state, "watermark", nil, { meta_commit_ok = false })
        ui:syncNow(false)
        assert(next(state.meta_writes) == nil, "failed atomic watermark commit must leave test state unchanged")
        assert(state.shown[#state.shown].text:find("Errors: 1", 1, true))
    end)

    withStubbedSyncUI(function(SyncUI, state)
        local ui = newUI(SyncUI, state, "watermark")
        ui:syncNow(false)
        assert(next(state.meta_writes) == nil)
        assert(state.shown[#state.shown].text:find("cancelled", 1, true))
    end, { cancelled = true })

    withStubbedSyncUI(function(SyncUI, state)
        local ui = newUI(SyncUI, state, "watermark", {
            mode = "offline",
            errors = 0,
            annotation_sync_status = "queued_offline",
            annotation_scanned = 1,
            highlight_creates_queued = 1,
            highlight_queue_waiting = 1,
            postprocess = {},
        })
        ui:syncNow(false)
        assert(state.wrap_calls == 1)
        assert(state.subprocess_calls == 1)
        assert(#state.worker_calls == 1)
        assert(state.worker_calls[1].network_available == false)
        assert(state.worker_calls[1].current_path == "/Readwise/current.html")
        assert(state.shown[#state.shown].text:find("Mode: offline / local queue", 1, true))
        assert(state.shown[#state.shown].text:find("Highlight creates queued durably: 1", 1, true))
        assert(state.shown[#state.shown].text:find("Create queue waiting after sync: 1", 1, true))
        assert(next(state.meta_writes) == nil, "offline local queue must not advance document watermark")
    end, { online = false })

    withStubbedSyncUI(function(SyncUI, state)
        local ui = newUI(SyncUI, state, "watermark")
        ui:confirmAndRun(true)
        assert(state.wrap_calls == 0)
        assert(state.subprocess_calls == 0)
        assert(state.shown[#state.shown].text:find("Full document sync requires Wi-Fi", 1, true))
    end, { online = false })
end
