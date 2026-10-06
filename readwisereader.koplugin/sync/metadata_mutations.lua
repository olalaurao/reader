-- SPDX-License-Identifier: AGPL-3.0-only

local Tags = require("metadata/tags")

local MetadataMutations = {}
MetadataMutations.__index = MetadataMutations

local function normalizeNote(value)
    if value == nil then return "" end
    return tostring(value):gsub("\r\n", "\n"):gsub("\r", "\n")
end

local function retryDelay(item, failure)
    local retry_after = failure and tonumber(failure.retry_after)
    if retry_after and retry_after >= 0 then return math.max(1, retry_after) end
    local attempts = tonumber(item and item.attempts) or 0
    return math.min(300, 5 * (2 ^ math.min(attempts, 6)))
end

local function keyFor(target_kind, target_id, field)
    return table.concat({ "metadata", target_kind, target_id, field }, ":")
end

local function isPendingStatus(status)
    return status == "pending" or status == "retry_wait"
        or status == "in_flight" or status == "blocked"
end

function MetadataMutations:new(options)
    options = options or {}
    return setmetatable({
        reader = assert(options.reader, "Reader API is required"),
        documents = assert(options.documents, "documents repository is required"),
        queue = assert(options.queue, "queue repository is required"),
        annotation_metadata = options.annotation_metadata,
        hasher = assert(options.hasher, "hasher is required"),
        json_encode = options.json_encode or function(value) return require("json").encode(value) end,
        json_decode = options.json_decode or function(value) return require("json").decode(value) end,
        now = options.now or os.time,
        retry_delay = options.retry_delay or retryDelay,
    }, self)
end

function MetadataMutations:_queue(payload)
    local ok, payload_json = pcall(self.json_encode, payload)
    if not ok or type(payload_json) ~= "string" then
        return nil, { kind = "encode", retryable = false, message = "Metadata edit could not be encoded." }
    end
    local now = self.now()
    local payload_hash = self.hasher.sha256(payload_json)
    local queued = self.queue:prepareMetadata({
        idempotency_key = keyFor(payload.target_kind, payload.target_id, payload.field),
        operation = payload.field == "note" and "metadata_note" or "metadata_tags",
        entity_type = payload.target_kind,
        local_annotation_id = payload.local_annotation_id,
        reader_document_id = payload.target_kind == "document" and payload.target_id or payload.parent_id,
        reader_highlight_document_id = payload.target_kind == "highlight" and payload.target_id or nil,
        payload_json = payload_json,
        payload_hash = payload_hash,
        created_at = now,
        updated_at = now,
    })
    if not queued then
        return nil, {
            kind = "metadata_queue", retryable = true,
            message = "Reader metadata edit could not be queued safely.",
        }
    end
    if queued.payload_hash ~= payload_hash then
        return nil, {
            kind = "metadata_reconcile_required", retryable = true,
            message = "A previously attempted Reader metadata edit must be reconciled by Sync now before it can be replaced.",
        }
    end
    return queued
end

function MetadataMutations:queueDocumentNote(document, desired_note)
    assert(document and document.reader_id, "managed document is required")
    return self:_queue({
        target_kind = "document",
        target_id = document.reader_id,
        field = "note",
        baseline_note = normalizeNote(document.remote_notes),
        desired_note = normalizeNote(desired_note),
    })
end

function MetadataMutations:queueDocumentTags(document, desired_tags)
    assert(document and document.reader_id, "managed document is required")
    local baseline = Tags.normalize(document.remote_tags)
    desired_tags = Tags.normalize(desired_tags)
    local add, remove = Tags.diff(baseline, desired_tags)
    return self:_queue({
        target_kind = "document",
        target_id = document.reader_id,
        field = "tags",
        add_tags = add,
        remove_tags = remove,
        desired_tags = desired_tags,
    })
end

function MetadataMutations:cancelDocumentEdit(document, field)
    assert(document and document.reader_id, "managed document is required")
    assert(field == "note" or field == "tags", "metadata field is required")
    return self.queue:markCancelled(
        keyFor("document", document.reader_id, field),
        "User kept the current Reader value.",
        self.now()
    )
end

function MetadataMutations:getPendingDocumentState(document)
    assert(document and document.reader_id, "managed document is required")
    local state = {
        tags = Tags.normalize(document.remote_tags),
        note = normalizeNote(document.remote_notes),
        tags_pending = false,
        note_pending = false,
    }

    local tags_item = self.queue:getByKey(keyFor("document", document.reader_id, "tags"))
    if tags_item and isPendingStatus(tags_item.status) then
        local payload = self:_decode(tags_item)
        if payload and payload.field == "tags" then
            state.tags = Tags.normalize(payload.desired_tags)
            state.tags_pending = true
            state.tags_status = tags_item.status
        end
    end

    local note_item = self.queue:getByKey(keyFor("document", document.reader_id, "note"))
    if note_item and isPendingStatus(note_item.status) then
        local payload = self:_decode(note_item)
        if payload and payload.field == "note" then
            state.note = normalizeNote(payload.desired_note)
            state.note_pending = true
            state.note_status = note_item.status
        end
    end
    return state
end

function MetadataMutations:queueHighlightTags(link, baseline_tags, desired_tags)
    assert(link and link.reader_highlight_document_id, "linked highlight is required")
    local baseline = Tags.normalize(baseline_tags)
    desired_tags = Tags.normalize(desired_tags)
    local add, remove = Tags.diff(baseline, desired_tags)
    return self:_queue({
        target_kind = "highlight",
        target_id = link.reader_highlight_document_id,
        parent_id = link.reader_document_id,
        local_annotation_id = link.local_annotation_id,
        field = "tags",
        add_tags = add,
        remove_tags = remove,
        desired_tags = desired_tags,
    })
end

function MetadataMutations:_decode(item)
    local ok, payload = pcall(self.json_decode, item.payload_json)
    if not ok or type(payload) ~= "table" then
        return nil, { kind = "decode", retryable = false, message = "Metadata queue payload could not be decoded." }
    end
    return payload
end

function MetadataMutations:_getRemote(payload)
    local remote, get_err = self.reader:getDocument(payload.target_id, false, false)
    if not remote then return nil, get_err end
    if payload.target_kind == "highlight" then
        if remote.category ~= "highlight" or remote.parent_id ~= payload.parent_id then
            return nil, {
                kind = "remote_identity",
                retryable = false,
                message = "Reader highlight identity no longer matches the queued metadata edit.",
            }
        end
    elseif remote.parent_id ~= nil and remote.parent_id ~= "" then
        return nil, {
            kind = "remote_identity",
            retryable = false,
            message = "Reader document metadata edit resolved to a child record.",
        }
    end
    return remote
end

function MetadataMutations:_cacheSuccess(payload, remote, report)
    if payload.target_kind == "document" then
        self.documents:setRemoteMetadata(payload.target_id, remote.notes, remote.tags)
        report.document_metadata_updates[#report.document_metadata_updates + 1] = remote
    elseif payload.local_annotation_id and self.annotation_metadata then
        self.annotation_metadata:markTagsSynced(
            payload.local_annotation_id,
            remote.tags,
            self.now()
        )
    end
end

function MetadataMutations:_defer(item, failure, report, attempted)
    local kind = failure and failure.kind or "unknown"
    local message = failure and failure.message or "Reader metadata request failed."
    local now = self.now()
    if kind == "auth" then
        self.queue:markPendingError(item.idempotency_key, "metadata_auth", message, now)
        report.auth_waiting = report.auth_waiting + 1
    elseif failure and failure.retryable then
        self.queue:markRetryWait(
            item.idempotency_key,
            "metadata_" .. kind,
            attempted and "Metadata PATCH outcome will be reconciled before retry." or message,
            now + self.retry_delay(item, failure),
            now
        )
        report.deferred = report.deferred + 1
    else
        self.queue:markBlocked(item.idempotency_key, "metadata_" .. kind, message, now)
        report.blocked = report.blocked + 1
    end
    report.remote_errors = report.remote_errors + 1
end

function MetadataMutations:_processNote(item, payload, remote, report)
    local baseline = normalizeNote(payload.baseline_note)
    local desired = normalizeNote(payload.desired_note)
    local current = normalizeNote(remote.notes)
    if current == desired then
        self.queue:markSucceeded(item.idempotency_key, payload.target_id, self.now())
        self:_cacheSuccess(payload, remote, report)
        report.reconciled = report.reconciled + 1
        return
    end
    if current ~= baseline then
        if payload.target_kind == "document" then
            self.documents:setRemoteMetadata(payload.target_id, remote.notes, remote.tags)
        end
        self.queue:markBlocked(
            item.idempotency_key,
            "metadata_note_conflict",
            "Reader note changed after the Kindle baseline; no overwrite was attempted.",
            self.now()
        )
        report.conflicts = report.conflicts + 1
        return
    end

    local in_flight = self.queue:markInFlight(item.idempotency_key, self.now())
    local updated, update_err = self.reader:updateDocument(payload.target_id, { notes = desired })
    if not updated then
        self:_defer(in_flight or item, update_err, report, true)
        return
    end
    local verified, verify_err = self:_getRemote(payload)
    if not verified then
        self:_defer(in_flight or item, verify_err, report, true)
        return
    end
    if normalizeNote(verified.notes) ~= desired then
        self:_defer(in_flight or item, {
            kind = "verify",
            retryable = true,
            message = "Reader note PATCH could not be verified yet.",
        }, report, true)
        return
    end
    self.queue:markSucceeded(item.idempotency_key, payload.target_id, self.now())
    self:_cacheSuccess(payload, verified, report)
    report.note_updates = report.note_updates + 1
end

function MetadataMutations:_tagsSatisfied(current, add, remove)
    return Tags.equal(current, Tags.apply(current, add, remove))
end

function MetadataMutations:_processTags(item, payload, remote, report)
    local add = Tags.normalize(payload.add_tags)
    local remove = Tags.normalize(payload.remove_tags)
    local current = Tags.normalize(remote.tags)
    if self:_tagsSatisfied(current, add, remove) then
        self.queue:markSucceeded(item.idempotency_key, payload.target_id, self.now())
        self:_cacheSuccess(payload, remote, report)
        report.reconciled = report.reconciled + 1
        return
    end

    local merged = Tags.apply(current, add, remove)
    local in_flight = self.queue:markInFlight(item.idempotency_key, self.now())
    local updated, update_err = self.reader:updateDocument(payload.target_id, { tags = merged })
    if not updated then
        self:_defer(in_flight or item, update_err, report, true)
        return
    end
    local verified, verify_err = self:_getRemote(payload)
    if not verified then
        self:_defer(in_flight or item, verify_err, report, true)
        return
    end
    if not self:_tagsSatisfied(verified.tags, add, remove) then
        self:_defer(in_flight or item, {
            kind = "verify",
            retryable = true,
            message = "Reader tag PATCH could not be verified yet.",
        }, report, true)
        return
    end
    self.queue:markSucceeded(item.idempotency_key, payload.target_id, self.now())
    self:_cacheSuccess(payload, verified, report)
    report.tag_updates = report.tag_updates + 1
end

function MetadataMutations:processQueue()
    local report = {
        processed = 0,
        note_updates = 0,
        tag_updates = 0,
        reconciled = 0,
        conflicts = 0,
        blocked = 0,
        deferred = 0,
        auth_waiting = 0,
        remote_errors = 0,
        document_metadata_updates = {},
    }
    for _, item in ipairs(self.queue:listMetadataWork(self.now())) do
        report.processed = report.processed + 1
        local payload, payload_err = self:_decode(item)
        if not payload then
            self:_defer(item, payload_err, report, false)
        else
            local remote, remote_err = self:_getRemote(payload)
            if not remote then
                self:_defer(item, remote_err, report, false)
            elseif payload.field == "note" then
                self:_processNote(item, payload, remote, report)
            elseif payload.field == "tags" then
                self:_processTags(item, payload, remote, report)
            else
                self:_defer(item, {
                    kind = "client",
                    retryable = false,
                    message = "Unknown metadata queue field.",
                }, report, false)
            end
        end
    end
    report.waiting_after = self.queue:countMetadataWaiting()
    return report
end

MetadataMutations._normalizeNote = normalizeNote
MetadataMutations._keyFor = keyFor

return MetadataMutations
