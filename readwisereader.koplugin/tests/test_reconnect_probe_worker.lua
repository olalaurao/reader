-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = require("sync/reconnect_probe_worker")

return function()
    local saved_json_loaded = package.loaded["json"]
    local saved_json_preload = package.preload["json"]
    local encoded_value
    package.loaded["json"] = nil
    package.preload["json"] = function()
        return {
            encode = function(value)
                encoded_value = value
                return "__snapshot__"
            end,
            decode = function(raw)
                assert(raw == "__snapshot__")
                return encoded_value
            end,
        }
    end

    local tmp = os.tmpname()
    assert(Worker._writeStage(tmp, "marker_scan") == true)
    assert(Worker._readStage(tmp) == "marker_scan")
    os.remove(tmp)

    assert(Worker._statusCount({ pending = 3 }, "pending") == 3)
    assert(Worker._statusCount({}, "pending") == 0)

    local snap = os.tmpname()
    local snapshot = {
        stage = "marker_scan_passed",
        remote_writes = 0,
        queue_pending = 3,
        items = {
            { status = "pending", marker_matches = 1 },
        },
    }
    assert(Worker._writeSnapshot(snap, snapshot) == true)
    local loaded = assert(Worker._readSnapshot(snap))
    assert(loaded.stage == "marker_scan_passed")
    assert(loaded.queue_pending == 3)
    assert(loaded.items[1].marker_matches == 1)
    os.remove(snap)

    local item = Worker._summarizeItem({
        status = "blocked",
        attempts = 2,
        last_error_kind = "stale_create_in_flight",
        reader_highlight_document_id = "remote-1",
    })
    assert(item.status == "blocked")
    assert(item.attempts == 2)
    assert(item.error_kind == "stale_create_in_flight")
    assert(item.has_remote_id == true)
    assert(item.marker_matches == 0)
    assert(item.parent_metadata == "not_run")
    assert(item.parent_html == "not_run")
    assert(item.parent_html_bytes == 0)
    assert(item.match_status == "not_run")

    do
        -- Gate 16 restart checkpoint: after a fresh process opens the durable
        -- queue, an offline auth probe must still return the queue snapshot and
        -- must not continue into marker/parent remote reads or any write path.
        local module_names = {
            "config",
            "storage/db",
            "storage/queue",
            "api/http",
            "api/reader",
            "sync/annotation_identity",
            "sync/text_match",
        }
        local saved = {}
        for _, name in ipairs(module_names) do
            saved[name] = {
                loaded = package.loaded[name],
                preload = package.preload[name],
            }
            package.loaded[name] = nil
        end

        local function provide(name, value)
            package.preload[name] = function() return value end
        end

        local validate_calls = 0
        local downstream_remote_calls = 0

        provide("config", {
            new = function()
                return {
                    close = function() end,
                }
            end,
        })
        provide("storage/db", {
            new = function()
                return {
                    close = function() end,
                }
            end,
        })
        provide("storage/queue", {
            new = function()
                return {
                    listCreateDiagnostics = function()
                        return {
                            {
                                status = "pending",
                                attempts = 0,
                                local_annotation_id = "gate16-restart-ann",
                                reader_document_id = "gate16-doc",
                                payload_json = "{}",
                            },
                        }
                    end,
                    countCreateStatuses = function()
                        return {
                            pending = 1,
                            retry_wait = 0,
                            in_flight = 0,
                            blocked = 0,
                            succeeded = 0,
                        }
                    end,
                }
            end,
        })
        provide("api/http", {
            new = function() return {} end,
        })
        provide("api/reader", {
            new = function()
                return {
                    validateToken = function()
                        validate_calls = validate_calls + 1
                        return nil, {
                            kind = "offline",
                            retryable = true,
                        }
                    end,
                    iterateDocuments = function()
                        downstream_remote_calls = downstream_remote_calls + 1
                        error("marker scan must not run after offline auth")
                    end,
                    getDocument = function()
                        downstream_remote_calls = downstream_remote_calls + 1
                        error("parent probe must not run after offline auth")
                    end,
                }
            end,
        })
        provide("sync/annotation_identity", {
            markerFor = function(id)
                return "marker:" .. tostring(id)
            end,
        })
        provide("sync/text_match", {
            findExactSubstring = function()
                downstream_remote_calls = downstream_remote_calls + 1
                error("text matching must not run after offline auth")
            end,
        })

        local stage_path = os.tmpname()
        local snapshot_path = os.tmpname()
        os.remove(stage_path)
        os.remove(snapshot_path)

        local report, err = Worker:run{
            stage_path = stage_path,
            snapshot_path = snapshot_path,
        }
        assert(err == nil)
        assert(report ~= nil)
        assert(report.stage == "done_auth_failure")
        assert(report.auth_status == "offline")
        assert(report.auth_retryable == true)
        assert(report.remote_writes == 0)
        assert(report.queue_pending == 1)
        assert(report.queue_retry_wait == 0)
        assert(report.queue_in_flight == 0)
        assert(report.items[1].status == "pending")
        assert(report.items[1].has_remote_id == false)
        assert(report.marker_scan_status == "not_run")
        assert(validate_calls == 1)
        assert(downstream_remote_calls == 0)

        os.remove(stage_path)
        os.remove(snapshot_path)
        for _, name in ipairs(module_names) do
            package.loaded[name] = saved[name].loaded
            package.preload[name] = saved[name].preload
        end
    end

    package.loaded["json"] = saved_json_loaded
    package.preload["json"] = saved_json_preload
end
