-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubbedUI(run, options)
    options = options or {}
    local names = {
        "ui/reconnect_diagnostics",
        "ui/widget/infomessage",
        "ui/trapper",
        "ui/uimanager",
        "sync/reconnect_probe_worker",
        "gettext",
    }
    local saved_loaded, saved_preload = {}, {}
    for _, name in ipairs(names) do
        saved_loaded[name] = package.loaded[name]
        saved_preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    local shown = {}
    package.preload["gettext"] = function()
        return function(value) return value end
    end
    package.preload["ui/widget/infomessage"] = function()
        return { new = function(_, value) return value end }
    end
    package.preload["ui/uimanager"] = function()
        return { show = function(_, widget) shown[#shown + 1] = widget end }
    end
    package.preload["ui/trapper"] = function()
        return {
            wrap = function(_, fn) fn() end,
            dismissableRunInSubprocess = function(_, fn)
                if options.no_result then
                    fn()
                    return true
                end
                local report, err = fn()
                return true, report, err
            end,
        }
    end
    package.preload["sync/reconnect_probe_worker"] = function()
        return {
            run = function() error("default worker must be injected") end,
            lastStage = function() return "stub_stage" end,
        }
    end

    local ok, err = pcall(function()
        run(require("ui/reconnect_diagnostics"), shown)
    end)

    for _, name in ipairs(names) do
        package.loaded[name] = saved_loaded[name]
        package.preload[name] = saved_preload[name]
    end
    if not ok then error(err) end
end

return function()
    withStubbedUI(function(UI, shown)
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            worker = {
                run = function()
                    return {
                        stage = "done",
                        auth_status = "passed",
                        queue_pending = 2,
                        queue_retry_wait = 0,
                        queue_in_flight = 1,
                        queue_blocked = 0,
                        queue_succeeded = 9,
                        marker_scan_status = "passed",
                        marker_scan_pages = 1,
                        marker_matches_total = 1,
                        items = {
                            {
                                status = "pending",
                                attempts = 0,
                                has_remote_id = false,
                                marker_matches = 0,
                                parent_read = "ok",
                                match_status = "matched",
                                match_mode = "exact",
                            },
                            {
                                status = "in_flight",
                                attempts = 1,
                                error_kind = "create_timeout",
                                has_remote_id = false,
                                marker_matches = 1,
                                parent_read = "ok",
                                match_status = "matched",
                            },
                        },
                        remote_writes = 0,
                    }
                end,
            },
        }
        ui:run()
        assert(#shown == 1)
        assert(shown[1].text:find("Auth probe: passed", 1, true))
        assert(shown[1].text:find("Queue pending: 2", 1, true))
        assert(shown[1].text:find("Queue in_flight: 1", 1, true))
        assert(shown[1].text:find("Active marker matches: 1", 1, true))
        assert(shown[1].text:find("status=in_flight", 1, true))
        assert(shown[1].text:find("marker_matches=1", 1, true))
        assert(shown[1].text:find("Remote writes: none", 1, true))
    end)

    withStubbedUI(function(UI, shown)
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            worker = {
                run = function() return nil, { kind = "worker", stage = "parent_reads" } end,
                lastStage = function() return "parent_reads" end,
            },
        }
        ui:run()
        assert(#shown == 1)
        assert(shown[1].text:find("Last durable stage: parent_reads", 1, true))
        assert(shown[1].text:find("Remote writes: none", 1, true))
    end)

    withStubbedUI(function(UI, shown)
        local ui = UI:new{
            config = { hasAccessToken = function() return false end },
            worker = {},
        }
        ui:run()
        assert(#shown == 1)
        assert(shown[1].text:find("No access token", 1, true))
    end)
end
