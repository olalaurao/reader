-- SPDX-License-Identifier: AGPL-3.0-only

local Backlog = require("sync/annotation_backlog")

local function document(id, path, present)
    return {
        reader_id = id,
        local_path = path,
        is_managed = true,
        is_local_present = present ~= false,
    }
end

return function()
    do
        local ordered, current = Backlog._localManagedDocuments({
            document("b", "/b.html"),
            document("c", "/c.html", false),
            document("a", "/a.html"),
        }, "/b.html")
        assert(current == true)
        assert(#ordered == 2)
        assert(ordered[1].local_path == "/b.html", "current document must be scanned first")
        assert(ordered[2].local_path == "/a.html")
    end

    do
        local calls = {}
        local docs = {
            document("a", "/a.html"),
            document("b", "/b.html"),
            document("c", "/c.html"),
        }
        local scanner = {
            scanPath = function(_, path)
                calls[#calls + 1] = "scan:" .. path
                if path == "/b.html" then
                    return {
                        authoritative = false,
                        status = "sidecar_missing",
                        annotations = {},
                    }
                elseif path == "/c.html" then
                    return nil, { kind = "local_missing" }
                end
                return {
                    authoritative = true,
                    annotations = {
                        { local_annotation_id = "ann-a1" },
                        { local_annotation_id = "ann-a2" },
                    },
                }
            end,
        }
        local uploader = {
            queueCandidates = function(_, doc, candidates)
                calls[#calls + 1] = "queue:" .. doc.local_path
                assert(doc.reader_id == "a")
                assert(#candidates == 2)
                return {
                    scanned = 2,
                    queued = 1,
                    already_linked = 1,
                    unmatched = 0,
                    blocked = 0,
                }
            end,
        }
        local backlog = Backlog:new{
            documents = {
                listManagedLocal = function() return docs end,
                listManaged = function() error("filtered local query must be preferred") end,
            },
            scanner = scanner,
            uploader = uploader,
        }

        local report = backlog:queueAll("/a.html")
        assert(report.documents_seen == 3)
        assert(report.documents_authoritative == 1)
        assert(report.documents_skipped == 2)
        assert(report.scan_errors == 1)
        assert(report.queue_errors == 0)
        assert(report.scanned == 2)
        assert(report.queued == 1)
        assert(report.already_linked == 1)
        assert(report.current_managed == true)
        assert(report.current_scan_authoritative == true)
        assert(report.current_status == "ok")
        assert(report.status == "scan_partial")
        assert(calls[1] == "scan:/a.html", "current document must be prioritized")
        assert(calls[2] == "queue:/a.html")
        assert(calls[3] == "scan:/b.html")
        assert(calls[4] == "scan:/c.html")
    end

    do
        local backlog = Backlog:new{
            documents = {
                listManaged = function()
                    return {
                        document("a", "/a.html"),
                        document("b", "/b.html"),
                    }
                end,
            },
            scanner = {
                scanPath = function(_, path)
                    return {
                        authoritative = true,
                        annotations = {
                            { local_annotation_id = path .. ":1" },
                        },
                    }
                end,
            },
            uploader = {
                queueCandidates = function()
                    return {
                        scanned = 1,
                        queued = 1,
                        already_linked = 0,
                        unmatched = 0,
                        blocked = 0,
                    }
                end,
            },
        }

        local report = backlog:queueAll("/not-managed.html")
        assert(report.current_managed == false)
        assert(report.current_scan_authoritative == false)
        assert(report.documents_authoritative == 2)
        assert(report.scanned == 2)
        assert(report.queued == 2)
        assert(report.status == "ok")
    end


    do
        local rows, source = Backlog._safeDocuments({
            listManagedLocal = function() error("simulated sqlite incompatibility") end,
            listManaged = function()
                return {
                    document("a", "/a.html"),
                    document("b", "/b.html", false),
                }
            end,
        }, "/a.html")
        assert(source == "managed_fallback")
        assert(#rows == 2)
    end

    do
        local rows, source = Backlog._safeDocuments({
            listManagedLocal = function() error("primary failed") end,
            listManaged = function() error("fallback failed") end,
            getByLocalPath = function(_, path)
                assert(path == "/current.html")
                return document("current", path)
            end,
        }, "/current.html")
        assert(source == "current_fallback")
        assert(#rows == 1)
        assert(rows[1].reader_id == "current")
    end

    do
        local backlog = Backlog:new{
            documents = {
                listManagedLocal = function()
                    return {
                        document("a", "/a.html"),
                        document("b", "/b.html"),
                        document("c", "/c.html"),
                    }
                end,
            },
            scanner = {
                scanPath = function(_, path)
                    if path == "/b.html" then
                        error("real sidecar parser exception")
                    end
                    return {
                        authoritative = true,
                        annotations = {
                            { local_annotation_id = path .. ":1" },
                        },
                    }
                end,
            },
            uploader = {
                queueCandidates = function(_, doc)
                    if doc.local_path == "/c.html" then
                        error("real queue exception")
                    end
                    return {
                        scanned = 1,
                        queued = 1,
                        already_linked = 0,
                        unmatched = 0,
                        blocked = 0,
                    }
                end,
            },
        }

        local report = backlog:queueAll("/a.html")
        assert(report.status == "queue_partial")
        assert(report.documents_seen == 3)
        assert(report.documents_authoritative == 2)
        assert(report.documents_skipped == 1)
        assert(report.scan_errors == 1)
        assert(report.scan_exceptions == 1)
        assert(report.queue_errors == 1)
        assert(report.queue_exceptions == 1)
        assert(report.scanned == 1)
        assert(report.queued == 1)
        assert(report.current_scan_authoritative == true)
        assert(report.current_status == "ok")
    end

    do
        local backlog = Backlog:new{
            documents = { listManaged = function() return {} end },
            scanner = { scanPath = function() error("must not scan") end },
            uploader = { queueCandidates = function() error("must not queue") end },
        }
        local report = backlog:queueAll(nil)
        assert(report.documents_seen == 0)
        assert(report.status == "no_local_managed_documents")
    end
end
