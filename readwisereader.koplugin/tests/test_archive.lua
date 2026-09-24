-- SPDX-License-Identifier: AGPL-3.0-only

local Archive = require("sync/archive")

local function copy(value)
    local out = {}
    for key, item in pairs(value or {}) do out[key] = item end
    return out
end

local function stateQueue(state)
    local queue = {}

    function queue:getByKey(key)
        return state.queue[key]
    end

    function queue:prepareArchive(item, reopen)
        local old = state.queue[item.idempotency_key]
        if not old then
            old = copy(item)
            old.status = item.status or "pending"
            old.attempts = item.attempts or 0
            state.queue[item.idempotency_key] = old
        elseif old.attempts == 0
            and (old.status == "pending"
                or old.status == "cancelled"
                or (reopen and old.status == "succeeded")) then
            old.payload_json = item.payload_json
            old.payload_hash = item.payload_hash
            old.status = "pending"
            old.available_after = nil
            old.last_attempt_at = nil
            old.last_error_kind = nil
            old.last_error_message = nil
        end
        return old
    end

    function queue:markInFlight(key, now)
        local item = state.queue[key]
        if item and item.status == "pending" then
            item.status = "in_flight"
            item.attempts = (item.attempts or 0) + 1
            item.last_attempt_at = now
            item.last_error_kind = nil
            item.last_error_message = nil
        end
        return item
    end

    function queue:markSucceeded(key, _, now)
        local item = state.queue[key]
        item.status = "succeeded"
        item.available_after = nil
        item.last_error_kind = nil
        item.last_error_message = nil
        item.updated_at = now
        return item
    end

    function queue:markCancelled(key, reason, now)
        local item = state.queue[key]
        item.status = "cancelled"
        item.attempts = 0
        item.available_after = nil
        item.last_attempt_at = nil
        item.last_error_kind = "cancelled"
        item.last_error_message = reason
        item.updated_at = now
        return item
    end

    function queue:markPendingError(key, kind, message, now)
        local item = state.queue[key]
        item.status = "pending"
        item.available_after = nil
        item.last_error_kind = kind
        item.last_error_message = message
        item.updated_at = now
        return item
    end

    function queue:markRetryWait(key, kind, message, available_after, now)
        local item = state.queue[key]
        item.status = "retry_wait"
        item.available_after = available_after
        item.last_error_kind = kind
        item.last_error_message = message
        item.updated_at = now
        return item
    end

    function queue:markBlocked(key, kind, message, now)
        local item = state.queue[key]
        item.status = "blocked"
        item.available_after = nil
        item.last_error_kind = kind
        item.last_error_message = message
        item.updated_at = now
        return item
    end

    function queue:listArchiveWork(now)
        local items = {}
        for _, item in pairs(state.queue) do
            if item.operation == "archive_document"
                and item.status == "retry_wait"
                and (item.available_after == nil or item.available_after <= now) then
                item.status = "pending"
                item.available_after = nil
            end
            if item.operation == "archive_document"
                and (item.status == "pending" or item.status == "in_flight") then
                items[#items + 1] = item
            end
        end
        table.sort(items, function(a, b)
            return a.idempotency_key < b.idempotency_key
        end)
        return items
    end

    function queue:countArchiveWaiting()
        local count = 0
        for _, item in pairs(state.queue) do
            if item.operation == "archive_document"
                and (item.status == "pending"
                    or item.status == "retry_wait"
                    or item.status == "in_flight"
                    or item.status == "blocked") then
                count = count + 1
            end
        end
        return count
    end

    return queue
end

local function baseState()
    return {
        now = 100,
        queue = {},
        location = "new",
        local_finished = true,
        sidecar_present = true,
        file_present = true,
        patches = 0,
        remote_location = "new",
        local_writes = 0,
    }
end

local function newArchive(state, reader_override)
    local queue = stateQueue(state)
    local documents = {
        listManagedLocal = function()
            return {
                {
                    reader_id = "doc-1",
                    location = state.location,
                    local_path = "/Readwise/a.html",
                    is_managed = true,
                    is_local_present = true,
                },
            }
        end,
        getById = function(_, id)
            assert(id == "doc-1")
            return {
                reader_id = "doc-1",
                location = state.location,
                local_path = "/Readwise/a.html",
                is_managed = true,
                is_local_present = true,
            }
        end,
        setLocation = function(_, id, location)
            assert(id == "doc-1")
            state.location = location
        end,
    }
    local status = {
        scan = function(_, path)
            assert(path == "/Readwise/a.html")
            return {
                sidecar_present = state.sidecar_present,
                sidecar_status = state.local_finished and "complete" or "reading",
                sidecar_modified = "2026-09-24",
                percent_finished = 0.1538,
                finished = state.local_finished,
            }
        end,
    }
    local reader = reader_override or {
        getDocument = function(_, id)
            assert(id == "doc-1")
            return { id = id, location = state.remote_location }
        end,
        updateDocument = function(_, id, patch)
            assert(id == "doc-1")
            assert(patch.location == "archive")
            state.patches = state.patches + 1
            state.remote_location = "archive"
            return { id = id }
        end,
    }

    return Archive:new{
        documents = documents,
        queue = queue,
        status = status,
        reader = reader,
        hasher = { sha256 = function(value) return "hash:" .. value end },
        json_encode = function()
            return '{"location":"archive"}'
        end,
        json_decode = function()
            return { location = "archive" }
        end,
        now = function() return state.now end,
        retry_delay = function(_, failure)
            return failure and failure.retry_after or 5
        end,
        file_exists = function()
            return state.file_present
        end,
    }, queue
end

local function successfulExactlyOnce()
    local state = baseState()
    local archive, queue = newArchive(state)

    local local_report = archive:queueAll()
    local key = Archive.queueKey("doc-1")
    assert(local_report.finished_detected == 1)
    assert(local_report.queued == 1)
    assert(queue:getByKey(key).status == "pending")

    local remote_report = archive:processQueue()
    assert(remote_report.archived == 1)
    assert(remote_report.already_archived == 0)
    assert(remote_report.waiting_after == 0)
    assert(state.patches == 1)
    assert(state.location == "archive")
    assert(queue:getByKey(key).status == "succeeded")
    assert(state.local_finished == true)
    assert(state.sidecar_present == true)
    assert(state.file_present == true)

    local second_local = archive:queueAll()
    assert(second_local.already_archived == 1)
    local second_remote = archive:processQueue()
    assert(second_remote.processed == 0)
    assert(state.patches == 1, "unchanged second sync must not PATCH archive twice")
end

local function timeoutReconcilesBeforeRetry()
    local state = baseState()
    local first = true
    local reader = {
        getDocument = function(_, id)
            return { id = id, location = state.remote_location }
        end,
        updateDocument = function(_, id, patch)
            assert(patch.location == "archive")
            state.patches = state.patches + 1
            if first then
                first = false
                state.remote_location = "archive"
                return nil, {
                    kind = "timeout",
                    retryable = true,
                    message = "timeout",
                }
            end
            error("reconciliation must prevent a duplicate PATCH")
        end,
    }
    local archive, queue = newArchive(state, reader)
    archive:queueAll()
    local key = Archive.queueKey("doc-1")

    local first_report = archive:processQueue()
    assert(first_report.deferred == 1)
    assert(queue:getByKey(key).status == "retry_wait")
    assert(queue:getByKey(key).attempts == 1)
    assert(state.patches == 1)

    state.now = queue:getByKey(key).available_after
    local second = archive:processQueue()
    assert(second.already_archived == 1)
    assert(second.archived == 0)
    assert(second.waiting_after == 0)
    assert(state.patches == 1, "remote GET must adopt the timed-out successful PATCH")
    assert(state.location == "archive")
end

local function unfinishedCancelsBeforePatch()
    local state = baseState()
    local archive, queue = newArchive(state)
    archive:queueAll()
    local key = Archive.queueKey("doc-1")
    assert(queue:getByKey(key).status == "pending")

    state.local_finished = false
    local report = archive:processQueue()
    assert(report.cancelled == 1)
    assert(state.patches == 0)
    assert(queue:getByKey(key).status == "cancelled")

    state.local_finished = true
    local reopened = archive:queueAll()
    assert(reopened.queued == 1)
    assert(queue:getByKey(key).status == "pending")
end

local function alreadyRemoteArchiveIsAdopted()
    local state = baseState()
    state.remote_location = "archive"
    local archive = newArchive(state)
    archive:queueAll()
    local report = archive:processQueue()
    assert(report.already_archived == 1)
    assert(report.archived == 0)
    assert(state.patches == 0)
    assert(state.location == "archive")
end

local function missingLocalFileBlocks()
    local state = baseState()
    local archive, queue = newArchive(state)
    archive:queueAll()
    state.file_present = false
    local report = archive:processQueue()
    assert(report.blocked == 1)
    assert(state.patches == 0)
    assert(queue:getByKey(Archive.queueKey("doc-1")).last_error_kind
        == "archive_local_missing")
end

return function()
    assert(Archive.queueKey("doc-1") == "archive_document:doc-1")
    successfulExactlyOnce()
    timeoutReconcilesBeforeRetry()
    unfinishedCancelsBeforePatch()
    alreadyRemoteArchiveIsAdopted()
    missingLocalFileBlocks()
end
