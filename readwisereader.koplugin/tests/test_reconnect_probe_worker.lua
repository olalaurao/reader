-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = require("sync/reconnect_probe_worker")

return function()
    local tmp = os.tmpname()
    assert(Worker._writeStage(tmp, "marker_scan") == true)
    assert(Worker._readStage(tmp) == "marker_scan")
    os.remove(tmp)

    assert(Worker._statusCount({ pending = 3 }, "pending") == 3)
    assert(Worker._statusCount({}, "pending") == 0)

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
    assert(item.parent_read == "not_run")
    assert(item.match_status == "not_run")
end
