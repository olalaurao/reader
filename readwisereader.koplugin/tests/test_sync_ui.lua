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

local function newUI(SyncUI, state, watermark, report)
    return SyncUI:new{
        config = { hasAccessToken = function() return true end },
        sync_meta = {
            get = function(_, key)
                if key == "document_watermark" then return watermark end
                return nil
            end,
        },
        collections = {
            refresh = function()
                state.refresh_calls = state.refresh_calls + 1
                return true
            end,
        },
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
        assert(state.refresh_calls == 1)
        assert(state.shown[#state.shown].text:find("Downloaded: 2", 1, true))
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
        local ui = newUI(SyncUI, state, "watermark")
        ui:syncNow(false)
        assert(state.refresh_calls == 0)
        assert(state.shown[#state.shown].text:find("cancelled", 1, true))
    end, { cancelled = true })

    withStubbedSyncUI(function(SyncUI, state)
        local ui = newUI(SyncUI, state, "watermark")
        ui:syncNow(false)
        assert(state.wrap_calls == 0)
        assert(state.subprocess_calls == 0)
        assert(state.shown[#state.shown].text:find("No internet connection", 1, true))
    end, { online = false })
end
