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

    package.loaded["json"] = saved_json_loaded
    package.preload["json"] = saved_json_preload
end
