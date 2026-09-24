-- SPDX-License-Identifier: AGPL-3.0-only

local Upload = require("sync/annotation_upload")

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

local function candidate()
    return {
        local_annotation_id = "ann-1",
        text = "Selected text",
        note = "ver [[Foucault]]\n#pesquisar",
        text_hash = "th",
        note_hash = "nh",
    }
end

local function newState()
    return {
        now = 100,
        link = {
            local_annotation_id = "ann-1",
            reader_document_id = "doc-1",
            sync_state = "local_only",
            created_remote = false,
            local_deleted_at = nil,
        },
        queue = {},
        payloads = {},
        payload_seq = 0,
        creates = 0,
        links = 0,
    }
end

local function repositories(state)
    local annotations = {
        getById = function(_, id)
            if id == "ann-1" then return state.link end
        end,
        setReaderRemoteLink = function(_, id, remote_id, synced)
            assert(id == "ann-1")
            state.link.created_remote = true
            state.link.sync_state = "synced"
            state.link.reader_highlight_document_id = remote_id
            state.link.last_synced_text = synced.text
            state.link.last_synced_note = synced.note
            state.links = state.links + 1
        end,
    }

    local queue = {}
    function queue:getByKey(key) return state.queue[key] end

    function queue:prepare(item)
        local old = state.queue[item.idempotency_key]
        if not old then
            old = copy(item)
            old.status = item.status or "pending"
            old.attempts = item.attempts or 0
            state.queue[item.idempotency_key] = old
        elseif old.status == "pending" and old.attempts == 0 then
            old.payload_json = item.payload_json
            old.payload_hash = item.payload_hash
            old.updated_at = item.updated_at
        end
        return old
    end

    function queue:markInFlight(key, attempted_at)
        local item = state.queue[key]
        if item and item.status == "pending" then
            item.status = "in_flight"
            item.attempts = (item.attempts or 0) + 1
            item.last_attempt_at = attempted_at
            item.last_error_kind = nil
            item.last_error_message = nil
        end
        return item
    end

    function queue:markBlocked(key, kind, message, updated_at)
        local item = state.queue[key]
        item.status = "blocked"
        item.available_after = nil
        item.last_error_kind = kind
        item.last_error_message = message
        item.updated_at = updated_at
        return item
    end

    function queue:markPendingError(key, kind, message, updated_at)
        local item = state.queue[key]
        item.status = "pending"
        item.available_after = nil
        item.last_error_kind = kind
        item.last_error_message = message
        item.updated_at = updated_at
        return item
    end

    function queue:markRetryWait(key, kind, message, available_after, updated_at)
        local item = state.queue[key]
        item.status = "retry_wait"
        item.available_after = available_after
        item.last_error_kind = kind
        item.last_error_message = message
        item.updated_at = updated_at
        return item
    end

    function queue:markSucceeded(key, remote_id, updated_at)
        local item = state.queue[key]
        item.status = "succeeded"
        item.available_after = nil
        item.reader_highlight_document_id = remote_id
        item.last_error_kind = nil
        item.last_error_message = nil
        item.updated_at = updated_at
        return item
    end

    function queue:promoteAvailable(now)
        for _, item in pairs(state.queue) do
            if item.status == "retry_wait"
                and (item.available_after == nil or item.available_after <= now) then
                item.status = "pending"
                item.available_after = nil
                item.updated_at = now
            end
        end
    end

    function queue:listCreateWork(now)
        self:promoteAvailable(now)
        local items = {}
        for _, item in pairs(state.queue) do
            if item.operation == "create_highlight"
                and (item.status == "pending"
                    or item.status == "blocked"
                    or item.status == "in_flight") then
                items[#items + 1] = item
            end
        end
        table.sort(items, function(a, b)
            return a.idempotency_key < b.idempotency_key
        end)
        return items
    end

    function queue:countCreateWaiting()
        local count = 0
        for _, item in pairs(state.queue) do
            if item.operation == "create_highlight"
                and item.status ~= "succeeded" then
                count = count + 1
            end
        end
        return count
    end

    return annotations, queue
end

local function baseOptions(state, reader)
    local annotations, queue = repositories(state)
    return {
        documents = {
            getByLocalPath = function(_, path)
                if path == "/Readwise/a.html" then
                    return {
                        reader_id = "doc-1",
                        local_path = path,
                        is_managed = true,
                        is_local_present = true,
                    }
                end
            end,
            getById = function(_, id)
                if id == "doc-1" then
                    return {
                        reader_id = "doc-1",
                        local_path = "/Readwise/a.html",
                        is_managed = true,
                        is_local_present = true,
                    }
                end
            end,
        },
        annotations = annotations,
        queue = queue,
        adapter = {
            scan = function()
                return { authoritative = true, annotations = { candidate() } }
            end,
        },
        reader = reader,
        hasher = { sha256 = function(v) return "hash:" .. v end },
        json_encode = function(payload)
            state.payload_seq = state.payload_seq + 1
            local key = "payload:" .. tostring(state.payload_seq)
            state.payloads[key] = copy(payload)
            return key
        end,
        json_decode = function(key)
            return copy(assert(state.payloads[key]))
        end,
        now = function() return state.now end,
        retry_delay = function(_, failure)
            return failure and failure.retry_after or 5
        end,
        file_exists = function() return true end,
    }
end

local function successCase()
    local state = newState()
    local marker = Upload.markerFor("ann-1")
    local reader = {
        getDocument = function(_, id, with_html)
            if id == "doc-1" and with_html then
                return { id = id, html_content = "<p>Before Selected text After</p>" }
            end
            if id == "remote-hl-1" then
                return {
                    id = id,
                    parent_id = "doc-1",
                    category = "highlight",
                    source = marker,
                }
            end
        end,
        createHighlight = function(_, parent, content, note, tags, saved_using)
            state.creates = state.creates + 1
            assert(parent == "doc-1")
            assert(content == "Selected text")
            assert(note == "ver [[Foucault]]\n#pesquisar")
            assert(tags == nil)
            assert(saved_using == marker)
            return { id = "remote-hl-1" }
        end,
        iterateDocuments = function()
            error("reconciliation must not run on first confirmed create")
        end,
    }
    local uploader = Upload:new(baseOptions(state, reader))
    local result = assert(uploader:syncPath("/Readwise/a.html"))
    assert(result.queued == 1)
    assert(result.created == 1)
    assert(result.marker_verified == 1)
    assert(result.blocked == 0)
    assert(result.waiting_after == 0)
    assert(state.creates == 1)
    assert(state.links == 1)

    local second = assert(uploader:syncPath("/Readwise/a.html"))
    assert(second.created == 0)
    assert(second.already_linked == 1)
    assert(state.creates == 1)
end

local function offlineQueueRestartReconnectCase()
    local state = newState()
    local online = false
    local marker = Upload.markerFor("ann-1")
    local reader = {
        getDocument = function(_, id, with_html)
            if id == "doc-1" and with_html then
                if not online then
                    return nil, { kind = "offline", retryable = true, message = "offline" }
                end
                return { id = id, html_content = "<p>Selected text</p>" }
            end
            if id == "remote-offline" then
                return {
                    id = id,
                    parent_id = "doc-1",
                    category = "highlight",
                    source = marker,
                }
            end
        end,
        createHighlight = function()
            assert(online)
            state.creates = state.creates + 1
            return { id = "remote-offline" }
        end,
        iterateDocuments = function()
            error("never-attempted offline item must not reconcile")
        end,
    }

    local first = Upload:new(baseOptions(state, reader))
    local queued = assert(first:syncPath("/Readwise/a.html"))
    local key = Upload.queueKey("ann-1")
    assert(queued.created == 0)
    assert(queued.deferred == 1)
    assert(queued.waiting_after == 1)
    assert(state.queue[key].status == "retry_wait")
    assert(state.queue[key].attempts == 0)
    assert(state.creates == 0)

    -- Simulate KOReader restart: construct a new uploader over the same durable
    -- repositories, then reconnect after the backoff becomes due.
    online = true
    state.now = state.queue[key].available_after
    local restarted = Upload:new(baseOptions(state, reader))
    local processed = restarted:processQueue()
    assert(processed.created == 1)
    assert(processed.waiting_after == 0)
    assert(state.creates == 1)
    assert(state.link.reader_highlight_document_id == "remote-offline")
end

local function rateLimitThenSafeRetryCase()
    local state = newState()
    local marker = Upload.markerFor("ann-1")
    local remote_exists = false
    local reader = {
        getDocument = function(_, id, with_html)
            if id == "doc-1" and with_html then
                return { id = id, html_content = "<p>Selected text</p>" }
            end
            if id == "remote-rate" and remote_exists then
                return {
                    id = id,
                    parent_id = "doc-1",
                    category = "highlight",
                    source = marker,
                }
            end
        end,
        createHighlight = function()
            state.creates = state.creates + 1
            if state.creates == 1 then
                return nil, {
                    kind = "rate_limit",
                    retryable = true,
                    retry_after = 7,
                    message = "rate limited",
                }
            end
            remote_exists = true
            return { id = "remote-rate" }
        end,
        iterateDocuments = function(_, _, callback)
            if remote_exists then
                callback({
                    id = "remote-rate",
                    parent_id = "doc-1",
                    category = "highlight",
                    source = marker,
                })
            end
            return { pages = 1 }
        end,
    }

    local uploader = Upload:new(baseOptions(state, reader))
    local first = assert(uploader:syncPath("/Readwise/a.html"))
    local key = Upload.queueKey("ann-1")
    assert(first.created == 0)
    assert(first.deferred == 1)
    assert(state.queue[key].status == "retry_wait")
    assert(state.queue[key].attempts == 1)
    assert(state.creates == 1)

    state.now = state.queue[key].available_after
    local second = uploader:processQueue()
    assert(second.created == 1)
    assert(second.reconciled == 0)
    assert(state.creates == 2)
    assert(state.link.reader_highlight_document_id == "remote-rate")
end

local function timeoutThenReconcileCase()
    local state = newState()
    local marker = Upload.markerFor("ann-1")
    local remote_exists = false
    local reader = {
        getDocument = function(_, id, with_html)
            if id == "doc-1" and with_html then
                return { id = id, html_content = "<p>Selected text</p>" }
            end
        end,
        createHighlight = function()
            state.creates = state.creates + 1
            remote_exists = true
            return nil, { kind = "timeout", retryable = true, message = "timeout" }
        end,
        iterateDocuments = function(_, options, callback)
            assert(options.category == "highlight")
            if remote_exists then
                callback({
                    id = "remote-after-timeout",
                    parent_id = "doc-1",
                    category = "highlight",
                    source = marker,
                })
            end
            return { pages = 2 }
        end,
    }

    local uploader = Upload:new(baseOptions(state, reader))
    local first = assert(uploader:syncPath("/Readwise/a.html"))
    local key = Upload.queueKey("ann-1")
    assert(first.created == 0)
    assert(first.blocked == 1)
    assert(state.queue[key].status == "blocked")
    assert(state.creates == 1)

    local second = uploader:processQueue()
    assert(second.reconciled == 1)
    assert(second.marker_verified == 1)
    assert(state.creates == 1, "timeout recovery must not POST a duplicate")
    assert(state.link.reader_highlight_document_id == "remote-after-timeout")
end

local function timeoutNoMatchNeverRetriesCase()
    local state = newState()
    local reader = {
        getDocument = function(_, id, with_html)
            if id == "doc-1" and with_html then
                return { id = id, html_content = "<p>Selected text</p>" }
            end
        end,
        createHighlight = function()
            state.creates = state.creates + 1
            return nil, { kind = "timeout", retryable = true, message = "timeout" }
        end,
        iterateDocuments = function()
            return { pages = 1 }
        end,
    }
    local uploader = Upload:new(baseOptions(state, reader))
    assert(uploader:syncPath("/Readwise/a.html"))
    local second = uploader:processQueue()
    local item = state.queue[Upload.queueKey("ann-1")]
    assert(second.blocked == 1)
    assert(item.last_error_kind == "reconcile_not_found")
    assert(state.creates == 1, "ambiguous timeout must never be blindly retried")
end

local function serverErrorNoBlindRetryCase()
    local state = newState()
    local reader = {
        getDocument = function(_, id, with_html)
            if id == "doc-1" and with_html then
                return { id = id, html_content = "<p>Selected text</p>" }
            end
        end,
        createHighlight = function()
            state.creates = state.creates + 1
            return nil, { kind = "server", retryable = true, message = "server error" }
        end,
        iterateDocuments = function()
            return { pages = 1 }
        end,
    }
    local uploader = Upload:new(baseOptions(state, reader))
    local first = assert(uploader:syncPath("/Readwise/a.html"))
    local item = state.queue[Upload.queueKey("ann-1")]
    assert(first.blocked == 1)
    assert(item.status == "blocked")
    assert(item.last_error_kind == "create_server")
    assert(state.creates == 1)

    local second = uploader:processQueue()
    assert(second.blocked == 1)
    assert(state.creates == 1, "5xx outcome must reconcile before any later write")
    assert(item.last_error_kind == "reconcile_not_found")
end

local function authBeforePostSurvivesCase()
    local state = newState()
    local authorized = false
    local marker = Upload.markerFor("ann-1")
    local reader = {
        getDocument = function(_, id, with_html)
            if id == "doc-1" and with_html then
                if not authorized then
                    return nil, { kind = "auth", retryable = false, message = "expired" }
                end
                return { id = id, html_content = "<p>Selected text</p>" }
            end
            if id == "remote-auth" then
                return {
                    id = id,
                    parent_id = "doc-1",
                    category = "highlight",
                    source = marker,
                }
            end
        end,
        createHighlight = function()
            state.creates = state.creates + 1
            return { id = "remote-auth" }
        end,
        iterateDocuments = function()
            error("preflight auth rejection must not become ambiguous create")
        end,
    }
    local uploader = Upload:new(baseOptions(state, reader))
    local first = assert(uploader:syncPath("/Readwise/a.html"))
    local item = state.queue[Upload.queueKey("ann-1")]
    assert(first.auth_waiting == 1)
    assert(item.status == "pending")
    assert(item.attempts == 0)
    assert(state.creates == 0)

    authorized = true
    local second = uploader:processQueue()
    assert(second.created == 1)
    assert(state.creates == 1)
end

local function ambiguousTextBlocksWithoutWriteCase()
    local state = newState()
    local reader = {
        getDocument = function()
            return { id = "doc-1", html_content = "<p>same same</p>" }
        end,
        createHighlight = function()
            state.creates = state.creates + 1
        end,
        iterateDocuments = function() return { pages = 1 } end,
    }
    local options = baseOptions(state, reader)
    options.adapter = {
        scan = function()
            local item = candidate()
            item.text = "same"
            return { authoritative = true, annotations = { item } }
        end,
    }
    local uploader = Upload:new(options)
    local result = assert(uploader:syncPath("/Readwise/a.html"))
    assert(result.created == 0)
    assert(result.unmatched == 1)
    assert(state.creates == 0)
    assert(state.queue[Upload.queueKey("ann-1")].status == "blocked")
end

return function()
    assert(Upload.markerFor("ann-1") == "KOReader Readwise Reader:ann-1")
    successCase()
    offlineQueueRestartReconnectCase()
    rateLimitThenSafeRetryCase()
    timeoutThenReconcileCase()
    timeoutNoMatchNeverRetriesCase()
    serverErrorNoBlindRetryCase()
    authBeforePostSurvivesCase()
    ambiguousTextBlocksWithoutWriteCase()
end
