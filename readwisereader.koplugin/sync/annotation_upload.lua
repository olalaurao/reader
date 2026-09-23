-- SPDX-License-Identifier: AGPL-3.0-only

local TextMatch = require("sync/text_match")

local Upload = {}
Upload.__index = Upload

local function defaultJsonEncode(value)
    return require("json").encode(value)
end

local function err(kind, message, retryable)
    return { kind = kind, message = message, retryable = retryable == true }
end

local function markerFor(local_annotation_id)
    return "KOReader Readwise Reader:" .. tostring(local_annotation_id)
end

local function queueKey(local_annotation_id)
    return "create_highlight:" .. tostring(local_annotation_id)
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
        now = options.now or os.time,
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
        self.queue:markBlocked(
            key,
            "reconcile_" .. tostring(scan_err and scan_err.kind or "unknown"),
            "Remote create outcome could not be reconciled safely.",
            self.now()
        )
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

    local kind = #matches > 1 and "reconcile_multiple" or "reconcile_not_found"
    self.queue:markBlocked(
        key,
        kind,
        #matches > 1
            and "Multiple Reader children carry the create marker; no target was guessed."
            or "No Reader child with the exact create marker was found; the POST was not retried.",
        self.now()
    )
    return nil, err(
        kind,
        #matches > 1
            and "Multiple remote highlight candidates matched the durable marker."
            or "Create outcome remains unknown; no duplicate-risk retry was attempted.",
        false
    )
end

function Upload:_prepareQueue(document, candidate, exact, marker)
    local payload = {
        operation = "create_highlight",
        parent_id = document.reader_id,
        content = exact,
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

function Upload:syncPath(local_path)
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
            created = 0,
            reconciled = 0,
            already_linked = 0,
            unmatched = 0,
            blocked = 0,
            marker_verified = 0,
        }
    end

    local report = {
        status = "ok",
        scanned = #(scan.annotations or {}),
        created = 0,
        reconciled = 0,
        already_linked = 0,
        unmatched = 0,
        blocked = 0,
        marker_verified = 0,
        remote_errors = 0,
    }

    local parent
    local parent_error
    local function getParent()
        if parent or parent_error then return parent, parent_error end
        parent, parent_error = self.reader:getDocument(document.reader_id, true, false)
        return parent, parent_error
    end

    for _, candidate in ipairs(scan.annotations or {}) do
        local link = self.annotations:getById(candidate.local_annotation_id)
        if not link then
            -- The production worker performs the canonical sidecar scan first.
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
            -- Phase N owns deletion semantics; never recreate a local tombstone.
        else
            local marker = markerFor(candidate.local_annotation_id)
            local key = queueKey(candidate.local_annotation_id)
            local queued = self.queue:getByKey(key)

            local must_reconcile = queued
                and not (queued.status == "pending" and (queued.attempts or 0) == 0)
            if must_reconcile then
                if queued.status == "in_flight"
                    or (queued.status == "pending" and (queued.attempts or 0) > 0) then
                    queued = self.queue:markBlocked(
                        key,
                        "stale_create_in_flight",
                        "A prior create attempt may have reached Reader; reconcile before retry.",
                        self.now()
                    )
                end
                local reconciled, reconcile_err = self:_reconcile(document, candidate, queued, marker, key)
                if reconciled then
                    report.reconciled = report.reconciled + 1
                    if reconciled.marker_verified then
                        report.marker_verified = report.marker_verified + 1
                    end
                else
                    report.blocked = report.blocked + 1
                    if reconcile_err and reconcile_err.retryable then
                        report.remote_errors = report.remote_errors + 1
                    end
                end
            else
                local remote_parent, remote_parent_err = getParent()
                if not remote_parent then
                    report.remote_errors = report.remote_errors + 1
                    parent_error = remote_parent_err
                    break
                end

                local exact, match = self.matcher.findExactSubstring(
                    remote_parent.html_content,
                    candidate.text
                )
                if not exact then
                    report.unmatched = report.unmatched + 1
                else
                    queued = self:_prepareQueue(document, candidate, exact, marker)
                    if not queued then
                        report.remote_errors = report.remote_errors + 1
                    else
                        queued = self.queue:markInFlight(key, self.now())
                        if not queued or queued.status ~= "in_flight" then
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
                                self.queue:markBlocked(
                                    key,
                                    "create_" .. tostring(create_err and create_err.kind or "unknown"),
                                    "Reader create outcome is not safe to retry without reconciliation.",
                                    self.now()
                                )
                                report.blocked = report.blocked + 1
                                if create_err and create_err.retryable then
                                    report.remote_errors = report.remote_errors + 1
                                end
                            else
                                -- The response contains the durable child id. Persist it
                                -- before any optional verification GET.
                                self:_persistRemote(candidate, created.id, key)
                                report.created = report.created + 1

                                local child = self.reader:getDocument(created.id, false, false)
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

    return report
end

Upload.markerFor = markerFor
Upload.queueKey = queueKey

return Upload
