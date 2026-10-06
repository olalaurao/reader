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

    assert(Worker._annotationQueueStatus({
        documents_authoritative = 1,
    }, true) == "queued_offline")
    assert(Worker._annotationQueueStatus({
        documents_authoritative = 1,
        documents_skipped = 1,
    }, true) == "queued_offline_partial")
    assert(Worker._annotationQueueStatus({
        documents_authoritative = 1,
        queue_errors = 1,
    }, false) == "queued_remote_unavailable_partial")
    assert(Worker._annotationQueueStatus({
        documents_authoritative = 0,
    }, true) == nil)

    local postprocess_by_path = {}
    local function postprocess(path)
        postprocess_by_path[path] = postprocess_by_path[path] or { path = path }
        return postprocess_by_path[path]
    end
    local report = {}
    Worker._applyMetadataMutationReport(report, {
        processed = 3,
        note_updates = 1,
        tag_updates = 1,
        reconciled = 1,
        conflicts = 1,
        blocked = 2,
        deferred = 1,
        auth_waiting = 1,
        remote_errors = 2,
        waiting_after = 4,
        document_metadata_updates = {
            {
                id = "doc-1",
                title = "Remote title",
                author = "Remote author",
                summary = "Remote summary",
                site_name = "Remote site",
                tags = { "reader-new", "preserved" },
            },
            {
                id = "doc-remote-only",
                title = "No local projection",
                tags = { "skip" },
            },
        },
    }, {
        getById = function(_, id)
            if id == "doc-1" then
                return {
                    reader_id = id,
                    is_managed = true,
                    is_local_present = true,
                    local_path = "/Readwise/doc-1.epub",
                }
            end
            return {
                reader_id = id,
                is_managed = true,
                is_local_present = false,
                local_path = nil,
            }
        end,
    }, postprocess)

    assert(report.metadata_queue_processed == 3)
    assert(report.metadata_note_updates == 1)
    assert(report.metadata_tag_updates == 1)
    assert(report.metadata_reconciled == 1)
    assert(report.metadata_conflicts == 1)
    assert(report.metadata_blocked == 2)
    assert(report.metadata_deferred == 1)
    assert(report.metadata_auth_waiting == 1)
    assert(report.metadata_remote_errors == 2)
    assert(report.metadata_queue_waiting == 4)
    local projected = assert(postprocess_by_path["/Readwise/doc-1.epub"])
    assert(projected.metadata.title == "Remote title")
    assert(projected.metadata.summary == "Remote summary")
    assert(projected.metadata.tags[1] == "reader-new")
    assert(postprocess_by_path["doc-remote-only"] == nil)
end
