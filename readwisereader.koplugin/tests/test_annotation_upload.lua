-- SPDX-License-Identifier: AGPL-3.0-only

local Upload = require("sync/annotation_upload")

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
        link = {
            local_annotation_id = "ann-1",
            reader_document_id = "doc-1",
            sync_state = "local_only",
            created_remote = false,
        },
        queue = {},
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
            assert(synced.note == "ver [[Foucault]]\n#pesquisar")
            state.link.created_remote = true
            state.link.sync_state = "synced"
            state.link.reader_highlight_document_id = remote_id
            state.links = state.links + 1
        end,
    }

    local queue = {
        getByKey = function(_, key) return state.queue[key] end,
        prepare = function(_, item)
            local old = state.queue[item.idempotency_key]
            if not old then
                old = {
                    idempotency_key = item.idempotency_key,
                    operation = item.operation,
                    local_annotation_id = item.local_annotation_id,
                    reader_document_id = item.reader_document_id,
                    payload_json = item.payload_json,
                    payload_hash = item.payload_hash,
                    status = "pending",
                    attempts = 0,
                }
                state.queue[item.idempotency_key] = old
            elseif old.status == "pending" and old.attempts == 0 then
                old.payload_json = item.payload_json
                old.payload_hash = item.payload_hash
            end
            return old
        end,
        markInFlight = function(_, key)
            local item = state.queue[key]
            if item.status == "pending" then
                item.status = "in_flight"
                item.attempts = item.attempts + 1
            end
            return item
        end,
        markBlocked = function(_, key, kind, message)
            local item = state.queue[key]
            item.status = "blocked"
            item.last_error_kind = kind
            item.last_error_message = message
            return item
        end,
        markSucceeded = function(_, key, remote_id)
            local item = state.queue[key]
            item.status = "succeeded"
            item.reader_highlight_document_id = remote_id
            return item
        end,
    }
    return annotations, queue
end

local function baseOptions(state, reader)
    local annotations, queue = repositories(state)
    return {
        documents = { getByLocalPath = function() return {
            reader_id = "doc-1",
            local_path = "/Readwise/a.html",
            is_managed = true,
            is_local_present = true,
        } end },
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
            assert(payload.parent_id == "doc-1")
            assert(payload.content == "Selected text")
            assert(payload.notes == "ver [[Foucault]]\n#pesquisar")
            assert(payload.saved_using == Upload.markerFor("ann-1"))
            return "payload-json"
        end,
        now = (function()
            local n = 100
            return function() n = n + 1 return n end
        end)(),
        file_exists = function() return true end,
    }
end

local function successCase()
    local state = newState()
    local marker = Upload.markerFor("ann-1")
    local reader = {
        getDocument = function(_, id, with_html)
            if id == "doc-1" and with_html then
                return { id = "doc-1", html_content = "<p>Before Selected text After</p>" }
            end
            if id == "remote-hl-1" then
                return {
                    id = "remote-hl-1",
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
            error("reconciliation must not run on confirmed create")
        end,
    }
    local uploader = Upload:new(baseOptions(state, reader))
    local result = assert(uploader:syncPath("/Readwise/a.html"))
    assert(result.created == 1)
    assert(result.marker_verified == 1)
    assert(result.blocked == 0)
    assert(state.creates == 1)
    assert(state.links == 1)
    assert(state.queue[Upload.queueKey("ann-1")].status == "succeeded")

    local second = assert(uploader:syncPath("/Readwise/a.html"))
    assert(second.created == 0)
    assert(second.already_linked == 1)
    assert(state.creates == 1, "second sync must not POST the linked annotation again")
end

local function timeoutThenReconcileCase()
    local state = newState()
    local marker = Upload.markerFor("ann-1")
    local reader = {
        getDocument = function(_, id, with_html)
            if id == "doc-1" and with_html then
                return { id = "doc-1", html_content = "<p>Selected text</p>" }
            end
        end,
        createHighlight = function()
            state.creates = state.creates + 1
            return nil, { kind = "timeout", retryable = true, message = "timeout" }
        end,
        iterateDocuments = function(_, options, callback)
            assert(options.category == "highlight")
            callback({
                id = "remote-after-timeout",
                parent_id = "doc-1",
                category = "highlight",
                source = marker,
            })
            return { pages = 2 }
        end,
    }
    local uploader = Upload:new(baseOptions(state, reader))
    local first = assert(uploader:syncPath("/Readwise/a.html"))
    assert(first.created == 0)
    assert(first.blocked == 1)
    assert(state.creates == 1)
    assert(state.queue[Upload.queueKey("ann-1")].status == "blocked")

    local second = assert(uploader:syncPath("/Readwise/a.html"))
    assert(second.reconciled == 1)
    assert(second.marker_verified == 1)
    assert(state.creates == 1, "blocked create must reconcile without a second POST")
    assert(state.link.reader_highlight_document_id == "remote-after-timeout")
end

local function blockedNoMatchNeverRetries()
    local state = newState()
    local key = Upload.queueKey("ann-1")
    state.queue[key] = {
        idempotency_key = key,
        operation = "create_highlight",
        status = "blocked",
        attempts = 1,
    }
    local reader = {
        getDocument = function() error("parent fetch is unnecessary for blocked reconciliation") end,
        createHighlight = function() state.creates = state.creates + 1 end,
        iterateDocuments = function() return { pages = 1 } end,
    }
    local uploader = Upload:new(baseOptions(state, reader))
    local result = assert(uploader:syncPath("/Readwise/a.html"))
    assert(result.blocked == 1)
    assert(state.creates == 0, "unreconciled blocked create must never be blindly retried")
    assert(state.queue[key].last_error_kind == "reconcile_not_found")
end

local function ambiguousTextNeverQueues()
    local state = newState()
    local reader = {
        getDocument = function()
            return { id = "doc-1", html_content = "<p>same same</p>" }
        end,
        createHighlight = function() state.creates = state.creates + 1 end,
        iterateDocuments = function() error("not expected") end,
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
    assert(result.unmatched == 1)
    assert(state.creates == 0)
    assert(next(state.queue) == nil, "ambiguous text must not enter the remote-create queue")
end

return function()
    assert(Upload.markerFor("ann-1") == "KOReader Readwise Reader:ann-1")
    successCase()
    timeoutThenReconcileCase()
    blockedNoMatchNeverRetries()
    ambiguousTextNeverQueues()
end
