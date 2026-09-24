-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = require("sync/worker")

return function()
    local source_tags = { "research", "deep work" }
    local metadata = Worker._copyMetadata({
        title = "Title",
        author = "Author",
        summary = "Summary",
        site_name = "Site",
        tags = source_tags,
    })

    assert(metadata.title == "Title")
    assert(metadata.author == "Author")
    assert(metadata.summary == "Summary")
    assert(metadata.site_name == "Site")
    assert(metadata.tags[1] == "research")
    assert(metadata.tags[2] == "deep work")
    assert(metadata.tags ~= source_tags, "worker metadata payload must own its tag array")

    assert(Worker._isNetworkUnavailable({ kind = "offline" }) == true)
    assert(Worker._isNetworkUnavailable({ kind = "timeout" }) == true)
    assert(Worker._isNetworkUnavailable({ kind = "tls" }) == true)
    assert(Worker._isNetworkUnavailable({ kind = "unknown" }) == true)
    assert(Worker._isNetworkUnavailable({ kind = "auth" }) == false)
    assert(Worker._isNetworkUnavailable({ kind = "rate_limit" }) == false)
    assert(Worker._isNetworkUnavailable({ kind = "server" }) == false)
    assert(Worker._isNetworkUnavailable(nil) == false)

    local calls = 0
    local reachable, probe_err = Worker._probeReader({
        validateToken = function()
            calls = calls + 1
            return true
        end,
    })
    assert(reachable == true)
    assert(probe_err == nil)
    assert(calls == 1)

    local offline, offline_err = Worker._probeReader({
        validateToken = function()
            return nil, { kind = "offline", retryable = true }
        end,
    })
    assert(offline == false)
    assert(offline_err.kind == "offline")

    local unknown, unknown_err = Worker._probeReader({
        validateToken = function()
            return nil, nil
        end,
    })
    assert(unknown == false)
    assert(unknown_err.kind == "unknown")
end
