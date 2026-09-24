-- SPDX-License-Identifier: AGPL-3.0-only

local Archive = {}
Archive.__index = Archive

local OPERATION = "archive_document"

local function defaultJsonEncode(value)
    return require("json").encode(value)
end

local function defaultJsonDecode(value)
    return require("json").decode(value)
end

local function queueKey(reader_document_id)
    return OPERATION .. ":" .. tostring(reader_document_id)
end

local function retryDelay(item, failure)
    local retry_after = failure and tonumber(failure.retry_after)
    if retry_after and retry_after >= 0 then
        return math.max(1, retry_after)
    end
    local attempts = tonumber(item and item.attempts) or 0
    local exponent = math.min(attempts, 6)
    return math.min(300, 5 * (2 ^ exponent))
end

local function waiting(status)
    return status == "pending"
        or status == "retry_wait"
        or status == "in_flight"
        or status == "blocked"
end

function Archive:new(options)
    options = options or {}
    return setmetatable({
        documents = assert(options.documents, "documents repository is required"),
        queue = assert(options.queue, "queue repository is required"),
        status = assert(options.status, "KOReader status adapter is required"),
        reader = assert(options.reader, "Reader API is required"),
        hasher = assert(options.hasher, "hasher is required"),
        json_encode = options.json_encode or defaultJsonEncode,
        json_decode = options.json_decode or defaultJsonDecode,
        now = options.now or os.time,
        retry_delay = options.retry_delay or retryDelay,
        file_exists = options.file_exists or function(path)
            return require("libs/libkoreader-lfs").attributes(path, "mode") == "file"
        end,
    }, self)
end

function Archive:_prepare(document, local_status, reopen_succeeded)
    local payload = {
        operation = OPERATION,
        reader_document_id = document.reader_id,
        location = "archive",
        finished_modified = local_status and local_status.sidecar_modified or nil,
    }
    local ok, payload_json = pcall(self.json_encode, payload)
    if not ok or type(payload_json) ~= "string" then
        return nil, {
            kind = "encode",
            retryable = false,
            message = "Archive queue payload could not be encoded.",
        }
    end

    local now = self.now()
    return self.queue:prepareArchive({
        idempotency_key = queueKey(document.reader_id),
        operation = OPERATION,
        entity_type = "document",
        reader_document_id = document.reader_id,
        payload_json = payload_json,
        payload_hash = self.hasher.sha256(payload_json),
        created_at = now,
        updated_at = now,
    }, reopen_succeeded == true)
end

function Archive:_persistArchived(item, document, report, reconciled)
    self.queue:markSucceeded(item.idempotency_key, nil, self.now())
    self.documents:setLocation(document.reader_id, "archive")
    report.location_updates[#report.location_updates + 1] = {
        path = document.local_path,
        location = "archive",
    }
    if reconciled then
        report.already_archived = report.already_archived + 1
    else
        report.archived = report.archived + 1
    end
end

function Archive:_deferRead(item, failure, report)
    local kind = failure and failure.kind or "unknown"
    local message = failure and failure.message or "Reader archive precheck failed."
    local now = self.now()

    if kind == "auth" then
        self.queue:markPendingError(
            item.idempotency_key,
            "archive_precheck_auth",
            message,
            now
        )
        report.auth_waiting = report.auth_waiting + 1
    elseif failure and failure.retryable then
        local delay = self.retry_delay(item, failure)
        self.queue:markRetryWait(
            item.idempotency_key,
            "archive_precheck_" .. kind,
            message,
            now + delay,
            now
        )
        report.deferred = report.deferred + 1
    else
        self.queue:markBlocked(
            item.idempotency_key,
            "archive_precheck_" .. kind,
            message,
            now
        )
        report.blocked = report.blocked + 1
    end
    report.remote_errors = report.remote_errors + 1
end

function Archive:_deferPatch(item, failure, report)
    local kind = failure and failure.kind or "unknown"
    local message = failure and failure.message or "Reader archive PATCH failed."
    local now = self.now()

    if kind == "auth" then
        self.queue:markPendingError(
            item.idempotency_key,
            "archive_auth",
            message,
            now
        )
        report.auth_waiting = report.auth_waiting + 1
    elseif kind == "client" then
        self.queue:markBlocked(
            item.idempotency_key,
            "archive_client",
            message,
            now
        )
        report.blocked = report.blocked + 1
    else
        -- PATCH location=archive is an idempotent state assignment. Any later
        -- retry first GETs the document: if this attempt actually succeeded,
        -- the next cycle adopts archive without issuing a duplicate PATCH.
        local delay = self.retry_delay(item, failure)
        self.queue:markRetryWait(
            item.idempotency_key,
            "archive_" .. kind,
            message,
            now + delay,
            now
        )
        report.deferred = report.deferred + 1
    end
    report.remote_errors = report.remote_errors + 1
end

-- Local-only discovery. It is intentionally safe to run before network
-- reachability is known so Finished intent survives offline Sync/restart.
function Archive:queueAll()
    local report = {
        status = "ok",
        documents_seen = 0,
        finished_detected = 0,
        queued = 0,
        already_archived = 0,
        cancelled = 0,
        skipped = 0,
        scan_errors = 0,
    }

    local ok, documents = pcall(self.documents.listManagedLocal, self.documents)
    if not ok or type(documents) ~= "table" then
        report.status = "repository_error"
        report.scan_errors = 1
        return report
    end

    for _, document in ipairs(documents) do
        report.documents_seen = report.documents_seen + 1
        local key = queueKey(document.reader_id)
        local existing = self.queue:getByKey(key)

        if document.location == "archive" then
            report.already_archived = report.already_archived + 1
            if existing and existing.status ~= "succeeded" then
                self.queue:markSucceeded(key, nil, self.now())
            end
        elseif type(document.local_path) ~= "string"
            or document.local_path == ""
            or not self.file_exists(document.local_path) then
            report.skipped = report.skipped + 1
        else
            local scan_ok, local_status, scan_err = pcall(
                self.status.scan,
                self.status,
                document.local_path
            )
            if not scan_ok or not local_status then
                report.scan_errors = report.scan_errors + 1
                report.last_error_kind = scan_err and scan_err.kind or "sidecar"
            elseif not local_status.sidecar_present then
                report.skipped = report.skipped + 1
            elseif local_status.finished == true then
                report.finished_detected = report.finished_detected + 1
                local reopen = existing
                    and existing.status == "succeeded"
                    and document.location ~= "archive"
                local queued, queue_err = self:_prepare(
                    document,
                    local_status,
                    reopen
                )
                if not queued then
                    report.scan_errors = report.scan_errors + 1
                    report.last_error_kind = queue_err and queue_err.kind or "queue"
                elseif waiting(queued.status) then
                    report.queued = report.queued + 1
                end
            elseif existing
                and existing.attempts == 0
                and (existing.status == "pending"
                    or existing.status == "retry_wait") then
                self.queue:markCancelled(
                    key,
                    "Local document is no longer Finished before any archive PATCH.",
                    self.now()
                )
                report.cancelled = report.cancelled + 1
            end
        end
    end

    return report
end

function Archive:processQueue()
    local items = self.queue:listArchiveWork(self.now())
    local report = {
        status = "ok",
        processed = 0,
        archived = 0,
        already_archived = 0,
        cancelled = 0,
        blocked = 0,
        deferred = 0,
        auth_waiting = 0,
        remote_errors = 0,
        waiting_after = 0,
        location_updates = {},
    }

    for _, original in ipairs(items) do
        report.processed = report.processed + 1
        local item = original
        local key = item.idempotency_key
        local document = self.documents:getById(item.reader_document_id)

        if not document or document.is_managed ~= true then
            self.queue:markBlocked(
                key,
                "archive_missing_document",
                "The Reader document is no longer managed locally.",
                self.now()
            )
            report.blocked = report.blocked + 1
        elseif document.is_local_present ~= true
            or type(document.local_path) ~= "string"
            or document.local_path == ""
            or not self.file_exists(document.local_path) then
            self.queue:markBlocked(
                key,
                "archive_local_missing",
                "Archive was not sent because the managed local file is missing.",
                self.now()
            )
            report.blocked = report.blocked + 1
        else
            local local_status, status_err = self.status:scan(document.local_path)
            if not local_status then
                self.queue:markBlocked(
                    key,
                    "archive_" .. tostring(status_err and status_err.kind or "sidecar"),
                    status_err and status_err.message
                        or "KOReader Finished status could not be read safely.",
                    self.now()
                )
                report.blocked = report.blocked + 1
            else
                if item.status == "in_flight" then
                    item = self.queue:markPendingError(
                        key,
                        "stale_archive_in_flight",
                        "Archive outcome will be verified before retry.",
                        self.now()
                    )
                end

                local remote, remote_err = self.reader:getDocument(
                    document.reader_id,
                    false,
                    false
                )
                if not remote then
                    self:_deferRead(item, remote_err, report)
                elseif remote.location == "archive" then
                    self:_persistArchived(item, document, report, true)
                elseif local_status.finished ~= true then
                    -- The read-only GET proves Reader is not archived. It is
                    -- therefore safe to cancel even if a prior PATCH attempt
                    -- had an unknown outcome.
                    self.queue:markCancelled(
                        key,
                        "Local document is no longer Finished and Reader is not archived.",
                        self.now()
                    )
                    report.cancelled = report.cancelled + 1
                else
                    if item.status ~= "pending" then
                        item = self.queue:markPendingError(
                            key,
                            item.last_error_kind,
                            item.last_error_message,
                            self.now()
                        )
                    end
                    item = self.queue:markInFlight(key, self.now())
                    if not item or item.status ~= "in_flight" then
                        report.blocked = report.blocked + 1
                    else
                        local updated, patch_err = self.reader:updateDocument(
                            document.reader_id,
                            { location = "archive" }
                        )
                        if updated then
                            self:_persistArchived(item, document, report, false)
                        else
                            self:_deferPatch(item, patch_err, report)
                        end
                    end
                end
            end
        end
    end

    report.waiting_after = self.queue:countArchiveWaiting()
    return report
end

Archive.queueKey = queueKey
Archive.retryDelay = retryDelay

return Archive
