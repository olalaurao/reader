-- SPDX-License-Identifier: AGPL-3.0-only

local Backlog = {}
Backlog.__index = Backlog

local function addCounts(target, source)
    for _, key in ipairs({
        "scanned",
        "queued",
        "already_linked",
        "unmatched",
        "blocked",
    }) do
        target[key] = (target[key] or 0) + (source[key] or 0)
    end
end

local function localManagedDocuments(documents, current_path)
    local current
    local rest = {}
    for _, document in ipairs(documents or {}) do
        if document.is_managed == true
            and document.is_local_present == true
            and type(document.local_path) == "string"
            and document.local_path ~= "" then
            if current_path and document.local_path == current_path then
                current = document
            else
                rest[#rest + 1] = document
            end
        end
    end

    table.sort(rest, function(a, b)
        return tostring(a.reader_id or "") < tostring(b.reader_id or "")
    end)

    local ordered = {}
    if current then ordered[#ordered + 1] = current end
    for _, document in ipairs(rest) do ordered[#ordered + 1] = document end
    return ordered, current ~= nil
end

function Backlog:new(options)
    options = options or {}
    return setmetatable({
        documents = assert(options.documents, "documents repository is required"),
        scanner = assert(options.scanner, "annotation scanner is required"),
        uploader = assert(options.uploader, "annotation uploader is required"),
    }, self)
end

-- Local-only discovery. This function must never perform a remote request.
-- It scans every locally-present Reader-managed document so a highlight made
-- before switching to another book is still discovered on the next manual sync.
local function safeDocuments(documents, current_path)
    local source = "none"
    local rows

    if type(documents.listManagedLocal) == "function" then
        local ok, result = pcall(documents.listManagedLocal, documents)
        if ok and type(result) == "table" then
            rows = result
            source = "managed_local"
        end
    end

    if rows == nil and type(documents.listManaged) == "function" then
        local ok, result = pcall(documents.listManaged, documents)
        if ok and type(result) == "table" then
            rows = result
            source = "managed_fallback"
        end
    end

    if rows == nil then
        rows = {}
        source = "current_fallback"
        if type(current_path) == "string" and current_path ~= ""
            and type(documents.getByLocalPath) == "function" then
            local ok, current = pcall(documents.getByLocalPath, documents, current_path)
            if ok and current then rows[1] = current end
        end
    end

    return rows, source
end

function Backlog:queueAll(current_path)
    local documents, repository_source = safeDocuments(self.documents, current_path)
    local ordered, current_managed = localManagedDocuments(
        documents,
        current_path
    )

    local report = {
        status = "ok",
        repository_source = repository_source,
        repository_fallback = repository_source ~= "managed_local",
        documents_seen = #ordered,
        documents_authoritative = 0,
        documents_skipped = 0,
        scan_errors = 0,
        scan_exceptions = 0,
        normalize_exceptions = 0,
        queue_errors = 0,
        queue_exceptions = 0,
        scanned = 0,
        queued = 0,
        already_linked = 0,
        unmatched = 0,
        blocked = 0,
        current_managed = current_managed,
        current_scan_authoritative = false,
        current_status = current_managed and "not_scanned" or "current_document_not_managed",
        last_error_kind = nil,
    }

    for _, document in ipairs(ordered) do
        local is_current = current_path ~= nil and document.local_path == current_path
        local call_ok, scan_report, scan_err = pcall(
            self.scanner.scanPath,
            self.scanner,
            document.local_path
        )

        if not call_ok then
            report.scan_errors = report.scan_errors + 1
            report.scan_exceptions = report.scan_exceptions + 1
            report.documents_skipped = report.documents_skipped + 1
            report.last_error_kind = "scan_exception"
            if is_current then report.current_status = "scan_exception" end
        elseif not scan_report then
            report.scan_errors = report.scan_errors + 1
            report.documents_skipped = report.documents_skipped + 1
            report.last_error_kind = scan_err and scan_err.kind or "scan_error"
            if is_current then
                report.current_status = "scan_error"
            end
        elseif not scan_report.authoritative then
            report.documents_skipped = report.documents_skipped + 1
            if is_current then
                report.current_status = scan_report.status or "sidecar_not_authoritative"
            end
        else
            report.documents_authoritative = report.documents_authoritative + 1
            report.normalize_exceptions = report.normalize_exceptions
                + (scan_report.normalize_exceptions or 0)
            if is_current then
                report.current_scan_authoritative = true
                report.current_status = "ok"
            end

            local queue_ok, queued, queue_err = pcall(
                self.uploader.queueCandidates,
                self.uploader,
                document,
                scan_report.annotations or {}
            )
            if not queue_ok then
                report.queue_errors = report.queue_errors + 1
                report.queue_exceptions = report.queue_exceptions + 1
                report.last_error_kind = "queue_exception"
                if is_current then report.current_status = "queue_exception" end
            elseif not queued then
                report.queue_errors = report.queue_errors + 1
                report.last_error_kind = queue_err and queue_err.kind or "queue_error"
                if is_current then report.current_status = "queue_error" end
            else
                addCounts(report, queued)
            end
        end
    end

    if report.queue_errors > 0 then
        report.status = "queue_partial"
    elseif report.scan_errors > 0 or report.documents_skipped > 0 then
        report.status = "scan_partial"
    elseif report.documents_seen == 0 then
        report.status = "no_local_managed_documents"
    end

    return report
end

Backlog._safeDocuments = safeDocuments

Backlog._localManagedDocuments = localManagedDocuments
Backlog._addCounts = addCounts

return Backlog
