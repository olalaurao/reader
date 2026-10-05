-- SPDX-License-Identifier: AGPL-3.0-only

local TextMatch = require("sync/text_match")
local AnnotationIdentity = require("sync/annotation_identity")

local Upload = {}
Upload.__index = Upload

local function defaultJsonEncode(value)
    return require("json").encode(value)
end

local function defaultJsonDecode(value)
    return require("json").decode(value)
end

local function err(kind, message, retryable)
    return { kind = kind, message = message, retryable = retryable == true }
end

local markerFor = AnnotationIdentity.markerFor
local queueKey = AnnotationIdentity.createQueueKey

local function retryDelay(item, failure)
    local retry_after = failure and tonumber(failure.retry_after)
    if retry_after and retry_after >= 0 then
        return math.max(1, retry_after)
    end
    local attempts = tonumber(item and item.attempts) or 0
    local exponent = math.min(attempts, 6)
    return math.min(300, 5 * (2 ^ exponent))
end

local function safeRejectedCreate(kind)
    return kind == "create_rate_limit" or kind == "create_auth"
end

local function asSet(values)
    local set = {}
    for key, value in pairs(values or {}) do
        if type(key) == "number" then
            if type(value) == "string" and value ~= "" then set[value] = true end
        elseif value == true and type(key) == "string" and key ~= "" then
            set[key] = true
        end
    end
    return set
end

function Upload:new(options)
    options = options or {}
    return setmetatable({
        documents = assert(options.documents, "documents repository is required"),
        annotations = assert(options.annotations, "annotations repository is required"),
        queue = assert(options.queue, "queue repository is required"),
        adapter = assert(options.adapter, "annotation adapter is required"),
        reader = assert(options.reader, "Reader API is required"),
        hasher = assert(options.hasher, "hasher is required"),
        matcher = options.matcher or TextMatch,
        json_encode = options.json_encode or defaultJsonEncode,
        json_decode = options.json_decode or defaultJsonDecode,
        now = options.now or os.time,
        retry_delay = options.retry_delay or retryDelay,
        file_exists = options.file_exists or function(path)
            return require("libs/libkoreader-lfs").attributes(path, "mode") == "file"
        end,
    }, self)
end

function Upload:_persistRemote(candidate, remote_id, key)
    self.annotations:setReaderRemoteLink(candidate.local_annotation_id, remote_id, {
        text = candidate.text,
        note = candidate.note,
        text_hash = candidate.text_hash,
        note_hash = candidate.note_hash,
        sync_state = "synced",
    })
    self.queue:markSucceeded(key, remote_id, self.now())
end

function Upload:_decodeItem(item)
    local ok, payload = pcall(self.json_decode, item.payload_json)
    if not ok or type(payload) ~= "table" then
        return nil, err("decode", "Highlight queue payload could not be decoded.", false)
    end
    return payload
end

function Upload:_candidateFromPayload(item, payload)
    return {
        local_annotation_id = item.local_annotation_id,
        text = payload.local_text or payload.content,
        note = payload.notes,
        text_hash = payload.text_hash,
        note_hash = payload.note_hash,
    }
end

-- Reconciliation never performs a write. It returns:
-- - reconciled: exact unique marker was found and persisted;
-- - not_found: a full scan completed with zero exact marker matches;
-- - error: scan failed or multiple matches made identity ambiguous.
function Upload:_reconcile(document, candidate, item, marker, key)
    if item.reader_highlight_document_id then
        local child = self.reader:getDocument(item.reader_highlight_document_id, false, false)
        if child
            and child.parent_id == document.reader_id
            and child.category == "highlight"
            and child.source == marker then
            self:_persistRemote(candidate, child.id, key)
            return {
                status = "reconciled",
                remote_id = child.id,
                marker_verified = true,
            }
        end
    end

    local matches = {}
    local scan, scan_err = self.reader:iterateDocuments({
        category = "highlight",
        limit = 100,
        with_html_content = false,
        with_raw_source_url = false,
    }, function(remote)
        if remote.parent_id == document.reader_id
            and remote.category == "highlight"
            and remote.source == marker then
            matches[#matches + 1] = remote
        end
    end)
    if not scan then
        return nil, scan_err
    end

    if #matches == 1 then
        self:_persistRemote(candidate, matches[1].id, key)
        return {
            status = "reconciled",
            remote_id = matches[1].id,
            marker_verified = true,
            reconciliation_pages = scan.pages,
        }
    end

    if #matches > 1 then
        return nil, err(
            "reconcile_multiple",
            "Multiple remote highlight candidates matched the durable marker.",
            false
        )
    end

    return {
        status = "not_found",
        marker_verified = false,
        reconciliation_pages = scan.pages,
    }
end

function Upload:_prepareQueue(document, candidate, content, marker)
    local payload = {
        operation = "create_highlight",
        parent_id = document.reader_id,
        local_text = candidate.text,
        content = content or candidate.text,
        notes = candidate.note,
        saved_using = marker,
        local_annotation_id = candidate.local_annotation_id,
        text_hash = candidate.text_hash,
        note_hash = candidate.note_hash,
    }
    local ok, payload_json = pcall(self.json_encode, payload)
    if not ok or type(payload_json) ~= "string" then
        return nil, err("encode", "Highlight queue payload could not be encoded.", false)
    end
    local now = self.now()
    return self.queue:prepare({
        idempotency_key = queueKey(candidate.local_annotation_id),
        operation = "create_highlight",
        entity_type = "annotation",
        local_annotation_id = candidate.local_annotation_id,
        reader_document_id = document.reader_id,
        payload_json = payload_json,
        payload_hash = self.hasher.sha256(payload_json),
        created_at = now,
        updated_at = now,
    })
end

-- Local-only stage. No network operation is allowed here.
-- Candidates passed by AnnotationSync already have their deterministic local
-- identities reconciled and their annotation_links persisted.
function Upload:queueCandidates(document, candidates)
    if not document or document.is_managed ~= true then
        return nil, err("not_managed", "The document is not managed by Readwise Reader.")
    end
    if document.is_local_present ~= true then
        return nil, err("local_missing", "The managed Reader document is not recorded as local.")
    end

    candidates = candidates or {}
    local report = {
        status = "ok",
        scanned = #candidates,
        queued = 0,
        already_linked = 0,
        unmatched = 0,
        blocked = 0,
    }

    for _, candidate in ipairs(candidates) do
        local link = self.annotations:getById(candidate.local_annotation_id)
        if not link then
            report.unmatched = report.unmatched + 1
        elseif link.created_remote then
            report.already_linked = report.already_linked + 1
            local existing = self.queue:getByKey(queueKey(candidate.local_annotation_id))
            if existing and existing.status ~= "succeeded" then
                self.queue:markSucceeded(
                    existing.idempotency_key,
                    link.reader_highlight_document_id,
                    self.now()
                )
            end
        elseif link.local_deleted_at ~= nil then
            -- Never recreate a tombstone.
        else
            local marker = markerFor(candidate.local_annotation_id)
            local queued, queue_err = self:_prepareQueue(
                document,
                candidate,
                candidate.text,
                marker
            )
            if not queued then
                report.blocked = report.blocked + 1
                report.last_error_kind = queue_err and queue_err.kind or "queue"
            else
                report.queued = report.queued + 1
            end
        end
    end

    return report
end

-- Compatibility/local utility entry point. Worker backlog discovery uses
-- AnnotationSync + queueCandidates so each sidecar is read only once.
function Upload:queuePath(local_path)
    local document = self.documents:getByLocalPath(local_path)
    if not document or document.is_managed ~= true then
        return nil, err("not_managed", "The current document is not managed by Readwise Reader.")
    end
    if document.is_local_present ~= true or not self.file_exists(document.local_path) then
        return nil, err("local_missing", "The managed Reader file is missing.")
    end

    local scan, scan_err = self.adapter:scan(document.local_path, document.reader_id)
    if not scan then return nil, scan_err end
    if not scan.authoritative then
        return {
            status = scan.status or "sidecar_not_authoritative",
            scanned = 0,
            queued = 0,
            already_linked = 0,
            unmatched = 0,
            blocked = 0,
        }
    end

    return self:queueCandidates(document, scan.annotations or {})
end

function Upload:_deferPreflight(item, failure, report)
    local kind = failure and failure.kind or "unknown"
    local message = failure and failure.message or "Remote preflight failed."
    local now = self.now()

    if kind == "auth" then
        self.queue:markPendingError(
            item.idempotency_key,
            "preflight_auth",
            message,
            now
        )
        report.auth_waiting = report.auth_waiting + 1
    elseif failure and failure.retryable then
        local delay = self.retry_delay(item, failure)
        self.queue:markRetryWait(
            item.idempotency_key,
            "preflight_" .. kind,
            message,
            now + delay,
            now
        )
        report.deferred = report.deferred + 1
    else
        self.queue:markBlocked(
            item.idempotency_key,
            "preflight_" .. kind,
            message,
            now
        )
        report.blocked = report.blocked + 1
    end
    report.remote_errors = report.remote_errors + 1
end

function Upload:_handleCreateFailure(item, failure, report)
    local kind = failure and failure.kind or "unknown"
    local message = failure and failure.message or "Reader create failed."
    local now = self.now()

    if kind == "rate_limit" then
        local delay = self.retry_delay(item, failure)
        self.queue:markRetryWait(
            item.idempotency_key,
            "create_rate_limit",
            message,
            now + delay,
            now
        )
        report.deferred = report.deferred + 1
    elseif kind == "auth" then
        -- HTTP auth rejection is a confirmed rejection, but the prior POST
        -- attempt is still reconciled before any later retry.
        self.queue:markPendingError(
            item.idempotency_key,
            "create_auth",
            message,
            now
        )
        report.auth_waiting = report.auth_waiting + 1
    elseif kind == "client" then
        self.queue:markBlocked(
            item.idempotency_key,
            "create_client",
            message,
            now
        )
        report.blocked = report.blocked + 1
    else
        -- timeout/offline/5xx/unknown can have an ambiguous remote outcome.
        -- Never turn them into a blind retry.
        self.queue:markBlocked(
            item.idempotency_key,
            "create_" .. kind,
            "Create outcome is unknown; reconcile before any retry.",
            now
        )
        report.blocked = report.blocked + 1
    end
    report.remote_errors = report.remote_errors + 1
end

function Upload:processQueue(options)
    options = options or {}
    local suppressed_annotation_ids = asSet(options.suppress_annotation_ids)
    local suppressed_reader_document_ids =
        asSet(options.suppress_reader_document_ids)
    local now = self.now()
    local items = self.queue:listCreateWork(now)
    local report = {
        status = "ok",
        processed = 0,
        created = 0,
        reconciled = 0,
        blocked = 0,
        unmatched = 0,
        marker_verified = 0,
        remote_errors = 0,
        deferred = 0,
        auth_waiting = 0,
        suppressed = 0,
        waiting_after = 0,
    }

    for _, item in ipairs(items) do
        report.processed = report.processed + 1
        local key = item.idempotency_key
        local link = self.annotations:getById(item.local_annotation_id)
        local suppressed =
            suppressed_annotation_ids[item.local_annotation_id] == true
            or suppressed_reader_document_ids[item.reader_document_id] == true

        if suppressed then
            -- Keep the durable create intent pending. A pre-sync Reader
            -- reconciliation found (or could not safely exclude) an existing
            -- remote counterpart, so this run must not POST a duplicate.
            report.suppressed = report.suppressed + 1
        elseif not link then
            self.queue:markBlocked(
                key,
                "missing_annotation_link",
                "The durable local annotation link is missing.",
                self.now()
            )
            report.blocked = report.blocked + 1
        elseif link.created_remote then
            self.queue:markSucceeded(
                key,
                link.reader_highlight_document_id,
                self.now()
            )
        elseif link.local_deleted_at ~= nil then
            self.queue:markBlocked(
                key,
                "local_deleted_before_create",
                "The local annotation was deleted before remote creation.",
                self.now()
            )
            report.blocked = report.blocked + 1
        else
            local payload, payload_err = self:_decodeItem(item)
            if not payload then
                self.queue:markBlocked(
                    key,
                    payload_err.kind,
                    payload_err.message,
                    self.now()
                )
                report.blocked = report.blocked + 1
            else
                local document = self.documents:getById(item.reader_document_id)
                if not document or document.is_managed ~= true then
                    self.queue:markBlocked(
                        key,
                        "missing_document",
                        "The Reader parent document is no longer managed locally.",
                        self.now()
                    )
                    report.blocked = report.blocked + 1
                else
                    local candidate = self:_candidateFromPayload(item, payload)
                    local marker = markerFor(item.local_annotation_id)
                    local prior_error = item.last_error_kind
                    local prior_attempt = (item.attempts or 0) > 0
                    local can_write = true

                    if prior_attempt then
                        local reconciled, reconcile_err = self:_reconcile(
                            document,
                            candidate,
                            item,
                            marker,
                            key
                        )
                        if reconciled and reconciled.status == "reconciled" then
                            report.reconciled = report.reconciled + 1
                            if reconciled.marker_verified then
                                report.marker_verified = report.marker_verified + 1
                            end
                            can_write = false
                        elseif not reconciled then
                            -- Keep the original create ambiguity classification.
                            if reconcile_err and reconcile_err.retryable then
                                local delay = self.retry_delay(item, reconcile_err)
                                self.queue:markRetryWait(
                                    key,
                                    prior_error or "reconcile_retry",
                                    reconcile_err.message or "Reconciliation retry deferred.",
                                    self.now() + delay,
                                    self.now()
                                )
                                report.deferred = report.deferred + 1
                                report.remote_errors = report.remote_errors + 1
                            else
                                self.queue:markBlocked(
                                    key,
                                    reconcile_err and reconcile_err.kind or "reconcile_error",
                                    reconcile_err and reconcile_err.message
                                        or "Remote create reconciliation failed safely.",
                                    self.now()
                                )
                                report.blocked = report.blocked + 1
                            end
                            can_write = false
                        elseif reconciled.status == "not_found"
                            and not safeRejectedCreate(prior_error) then
                            self.queue:markBlocked(
                                key,
                                "reconcile_not_found",
                                "A prior create outcome is still ambiguous; no duplicate-risk retry was attempted.",
                                self.now()
                            )
                            report.blocked = report.blocked + 1
                            can_write = false
                        end
                    end

                    if can_write then
                        local remote_parent, parent_err = self.reader:getDocument(
                            document.reader_id,
                            true,
                            false
                        )
                        if not remote_parent then
                            self:_deferPreflight(item, parent_err, report)
                        else
                            local exact, match = self.matcher.findExactSubstring(
                                remote_parent.html_content,
                                candidate.text
                            )
                            if not exact then
                                self.queue:markBlocked(
                                    key,
                                    "match_" .. tostring(match and match.status or "unmatched"),
                                    "The local selection could not be matched uniquely to Reader content.",
                                    self.now()
                                )
                                report.unmatched = report.unmatched + 1
                            else
                                -- Before the first POST, persist the exact Reader
                                -- substring. prepare() only mutates attempts==0 rows.
                                if (item.attempts or 0) == 0 then
                                    item = self:_prepareQueue(
                                        document,
                                        candidate,
                                        exact,
                                        marker
                                    ) or item
                                end

                                -- Safe retry after an explicit 429/auth rejection:
                                -- status may be pending with attempts>0. markInFlight
                                -- deliberately increments the durable attempt count.
                                if item.status ~= "pending" then
                                    self.queue:markPendingError(
                                        key,
                                        prior_error,
                                        item.last_error_message,
                                        self.now()
                                    )
                                end
                                item = self.queue:markInFlight(key, self.now())
                                if not item or item.status ~= "in_flight" then
                                    report.blocked = report.blocked + 1
                                else
                                    local created, create_err = self.reader:createHighlight(
                                        document.reader_id,
                                        exact,
                                        candidate.note,
                                        nil,
                                        marker
                                    )
                                    if not created then
                                        self:_handleCreateFailure(item, create_err, report)
                                    else
                                        self:_persistRemote(candidate, created.id, key)
                                        report.created = report.created + 1

                                        local child = self.reader:getDocument(
                                            created.id,
                                            false,
                                            false
                                        )
                                        if child
                                            and child.id == created.id
                                            and child.parent_id == document.reader_id
                                            and child.category == "highlight"
                                            and child.source == marker then
                                            report.marker_verified = report.marker_verified + 1
                                        end
                                        report.last_match_mode = match and match.mode or nil
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    report.waiting_after = self.queue:countCreateWaiting()
    return report
end

-- Compatibility entry point used by tests and the production worker.
function Upload:syncPath(local_path)
    local queued, queue_err = self:queuePath(local_path)
    if not queued then return nil, queue_err end
    local processed = self:processQueue()

    return {
        status = queued.status or processed.status,
        scanned = queued.scanned or 0,
        queued = queued.queued or 0,
        created = processed.created or 0,
        reconciled = processed.reconciled or 0,
        already_linked = queued.already_linked or 0,
        unmatched = (queued.unmatched or 0) + (processed.unmatched or 0),
        blocked = (queued.blocked or 0) + (processed.blocked or 0),
        marker_verified = processed.marker_verified or 0,
        remote_errors = processed.remote_errors or 0,
        deferred = processed.deferred or 0,
        auth_waiting = processed.auth_waiting or 0,
        suppressed = processed.suppressed or 0,
        waiting_after = processed.waiting_after or 0,
        queue_processed = processed.processed or 0,
    }
end

Upload.markerFor = markerFor
Upload.queueKey = queueKey
Upload._retryDelay = retryDelay
Upload._safeRejectedCreate = safeRejectedCreate

return Upload
