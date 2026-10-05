-- SPDX-License-Identifier: AGPL-3.0-only

local MetadataMutations = require("sync/metadata_mutations")

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then out[k] = copy(v) else out[k] = v end
    end
    return out
end

local function jsonEncode(value) return require("json").encode(value) end
local function jsonDecode(value) return require("json").decode(value) end

local function queueStub()
    local q = { items = {}, now = 100 }
    function q:prepareMetadata(item)
        item.status = "pending"; item.attempts = 0
        self.items[item.idempotency_key] = copy(item)
        return copy(item)
    end
    function q:getByKey(key)
        return self.items[key] and copy(self.items[key]) or nil
    end
    function q:listMetadataWork()
        local out = {}
        for _, item in pairs(self.items) do
            if item.status == "pending" then out[#out + 1] = copy(item) end
        end
        table.sort(out, function(a,b) return a.idempotency_key < b.idempotency_key end)
        return out
    end
    function q:markInFlight(key, at)
        local item = self.items[key]
        item.status = "in_flight"; item.attempts = (item.attempts or 0) + 1; item.last_attempt_at = at
        return copy(item)
    end
    function q:markSucceeded(key)
        self.items[key].status = "succeeded"; return copy(self.items[key])
    end
    function q:markBlocked(key, kind, message)
        local item = self.items[key]
        item.status = "blocked"; item.last_error_kind = kind; item.last_error_message = message
        return copy(item)
    end
    function q:markRetryWait(key, kind, message)
        local item = self.items[key]
        item.status = "retry_wait"; item.last_error_kind = kind; item.last_error_message = message
        return copy(item)
    end
    function q:markPendingError(key, kind, message)
        local item = self.items[key]
        item.status = "pending"; item.last_error_kind = kind; item.last_error_message = message
        return copy(item)
    end
    function q:countMetadataWaiting()
        local n = 0
        for _, item in pairs(self.items) do if item.status ~= "succeeded" then n = n + 1 end end
        return n
    end
    return q
end

local function newEngine(remote, queue, state)
    state = state or {}; state.patches = state.patches or 0
    local docs = {
        setRemoteMetadata = function(_, id, notes, tags)
            state.cached = { id = id, notes = notes, tags = copy(tags) }
        end,
    }
    local annotations = {
        markTagsSynced = function(_, id, tags)
            state.synced_annotation = { id = id, tags = copy(tags) }
        end,
    }
    local reader = {}
    function reader:getDocument(id)
        local value = remote[id]
        if not value then return nil, { kind = "not_found", retryable = false } end
        return copy(value)
    end
    function reader:updateDocument(id, patch)
        state.patches = state.patches + 1
        local value = remote[id]
        if patch.tags then value.tags = copy(patch.tags) end
        if patch.notes ~= nil then value.notes = patch.notes end
        if state.fail_after_write then
            state.fail_after_write = false
            return nil, { kind = "timeout", retryable = true }
        end
        return { id = id }
    end
    return MetadataMutations:new{
        reader = reader,
        documents = docs,
        queue = queue,
        annotation_metadata = annotations,
        hasher = { sha256 = function(v) return "hash:" .. tostring(#v) end },
        json_encode = jsonEncode,
        json_decode = jsonDecode,
        now = function() state.clock = (state.clock or 100) + 1; return state.clock end,
        retry_delay = function() return 1 end,
    }
end

local function tagMergePreservesRemoteAdd()
    local q = queueStub()
    local remote = { ["doc-1"] = { id="doc-1", category="article", tags={"a","remote"}, notes="" } }
    local state = {}; local e = newEngine(remote, q, state)
    assert(e:queueDocumentTags({ reader_id="doc-1", remote_tags={"a"} }, {"a","kindle"}))
    local r = e:processQueue()
    assert(r.tag_updates == 1 and r.conflicts == 0)
    assert(table.concat(remote["doc-1"].tags, "|") == "a|kindle|remote")
    assert(q:countMetadataWaiting() == 0)
end

local function noteConflictBlocksOverwrite()
    local q = queueStub()
    local remote = { ["doc-1"] = { id="doc-1", category="article", tags={}, notes="changed elsewhere" } }
    local state = {}; local e = newEngine(remote, q, state)
    assert(e:queueDocumentNote({ reader_id="doc-1", remote_notes="baseline" }, "kindle edit"))
    local r = e:processQueue()
    assert(r.conflicts == 1); assert(state.patches == 0); assert(remote["doc-1"].notes == "changed elsewhere")
end

local function noteClearUsesEmptyString()
    local q = queueStub()
    local remote = { ["doc-1"] = { id="doc-1", category="article", tags={}, notes="baseline" } }
    local state = {}; local e = newEngine(remote, q, state)
    assert(e:queueDocumentNote({ reader_id="doc-1", remote_notes="baseline" }, ""))
    local r = e:processQueue()
    assert(r.note_updates == 1); assert(remote["doc-1"].notes == "")
end

local function timeoutReconcilesWithoutSecondPatch()
    local q = queueStub()
    local remote = { ["doc-1"] = { id="doc-1", category="article", tags={"a"}, notes="" } }
    local state = { fail_after_write = true }; local e = newEngine(remote, q, state)
    assert(e:queueDocumentTags({ reader_id="doc-1", remote_tags={"a"} }, {"a","b"}))
    local first = e:processQueue()
    assert(first.deferred == 1 and state.patches == 1)
    for _, item in pairs(q.items) do item.status = "pending" end
    local second = e:processQueue()
    assert(second.reconciled == 1); assert(state.patches == 1)
end

local function highlightIdentityGuard()
    local q = queueStub()
    local remote = { ["hl-1"] = { id="hl-1", parent_id="other", category="highlight", tags={}, notes="" } }
    local state = {}; local e = newEngine(remote, q, state)
    assert(e:queueHighlightTags({
        local_annotation_id="ann-1", reader_document_id="doc-1", reader_highlight_document_id="hl-1",
    }, {}, {"x"}))
    local r = e:processQueue()
    assert(r.blocked == 1 and state.patches == 0)
end

local function pendingDocumentStateReflectsQueuedIntent()
    local q = queueStub()
    local remote = { ["doc-1"] = { id="doc-1", category="article", tags={"a"}, notes="old" } }
    local state = {}; local e = newEngine(remote, q, state)
    assert(e:queueDocumentTags({ reader_id="doc-1", remote_tags={"a"} }, {"a","kindle"}))
    assert(e:queueDocumentNote({ reader_id="doc-1", remote_notes="old" }, "queued note"))
    local pending = e:getPendingDocumentState({ reader_id="doc-1", remote_tags={"a"}, remote_notes="old" })
    assert(pending.tags_pending == true and pending.note_pending == true)
    assert(table.concat(pending.tags, "|") == "a|kindle")
    assert(pending.note == "queued note")
end

return function()
    tagMergePreservesRemoteAdd()
    noteConflictBlocksOverwrite()
    noteClearUsesEmptyString()
    timeoutReconcilesWithoutSecondPatch()
    highlightIdentityGuard()
    pendingDocumentStateReflectsQueuedIntent()
end
