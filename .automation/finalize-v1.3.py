from pathlib import Path

def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"marker not found in {path}: {old[:120]!r}")
    if text.count(old) != 1:
        raise SystemExit(f"marker not unique in {path}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1))

Path("readwisereader.koplugin/sync/annotation_upload.lua").write_text(r'''-- SPDX-License-Identifier: AGPL-3.0-only

-- v1.3 compatibility wrapper around the accepted v1.2 create engine.
-- It adds durable Reader-tag intent to new highlights without introducing a
-- second queue: linked metadata mutations are drained explicitly by worker.lua.
local Base = require("sync/annotation_upload_base")
local AnnotationMetadata = require("storage/annotation_metadata")

local base_new = Base.new
local base_persist_remote = Base._persistRemote

local function localIdFromMarker(marker)
    local prefix = "KOReader Readwise Reader:"
    if type(marker) ~= "string" or marker:sub(1, #prefix) ~= prefix then return nil end
    local value = marker:sub(#prefix + 1)
    return value ~= "" and value or nil
end

function Base:new(options)
    options = options or {}
    local annotation_metadata = options.annotation_metadata
    if not annotation_metadata and options.queue and options.queue.db then
        annotation_metadata = AnnotationMetadata:new{ db = options.queue.db }
    end

    local reader = assert(options.reader, "Reader API is required")
    local reader_proxy = setmetatable({}, { __index = reader })
    function reader_proxy:createHighlight(parent_id, content, note, tags, saved_using)
        local local_id = localIdFromMarker(saved_using)
        if local_id and annotation_metadata then
            local metadata = annotation_metadata:getById(local_id)
            if metadata and metadata.pending_tags ~= nil then
                tags = metadata.pending_tags
            end
        end
        return reader:createHighlight(parent_id, content, note, tags, saved_using)
    end

    local wrapped = {}
    for key, value in pairs(options) do wrapped[key] = value end
    wrapped.reader = reader_proxy
    local instance = base_new(self, wrapped)
    instance.annotation_metadata = annotation_metadata
    return instance
end

function Base:_persistRemote(candidate, remote_id, key)
    base_persist_remote(self, candidate, remote_id, key)
    if self.annotation_metadata then
        local metadata = self.annotation_metadata:getById(candidate.local_annotation_id)
        if metadata and metadata.pending_tags ~= nil then
            self.annotation_metadata:markTagsSynced(
                candidate.local_annotation_id,
                metadata.pending_tags,
                self.now()
            )
        end
    end
end

Base._localIdFromMarker = localIdFromMarker

return Base
''')

replace_once(
    "readwisereader.koplugin/sync/worker.lua",
    '    local AnnotationsRepository = require("storage/annotations")\n',
    '    local AnnotationsRepository = require("storage/annotations")\n'
    '    local AnnotationMetadataRepository = require("storage/annotation_metadata")\n'
)
replace_once(
    "readwisereader.koplugin/sync/worker.lua",
    '    local AnnotationMutations = require("sync/annotation_mutations")\n',
    '    local AnnotationMutations = require("sync/annotation_mutations")\n'
    '    local MetadataMutations = require("sync/metadata_mutations")\n'
)
replace_once(
    "readwisereader.koplugin/sync/worker.lua",
    '        local annotations_repository = AnnotationsRepository:new{ db = db }\n'
    '        local queue_repository = QueueRepository:new{ db = db }\n',
    '        local annotations_repository = AnnotationsRepository:new{ db = db }\n'
    '        local annotation_metadata_repository = AnnotationMetadataRepository:new{ db = db }\n'
    '        local queue_repository = QueueRepository:new{ db = db }\n'
)
replace_once(
    "readwisereader.koplugin/sync/worker.lua",
    '            reader = reader,\n'
    '            hasher = Hash,\n'
    '        }\n\n'
    '        -- Phase O closes the staging limitation',
    '            reader = reader,\n'
    '            annotation_metadata = annotation_metadata_repository,\n'
    '            hasher = Hash,\n'
    '        }\n\n'
    '        -- Phase O closes the staging limitation'
)
replace_once(
    "readwisereader.koplugin/sync/worker.lua",
    '            sync_report.annotation_sync_status = annotation_sync_status\n\n'
    '            sync_report.archive_enabled = archive_enabled\n',
    '            sync_report.annotation_sync_status = annotation_sync_status\n'
    '            sync_report.metadata_queue_processed = 0\n'
    '            sync_report.metadata_note_updates = 0\n'
    '            sync_report.metadata_tag_updates = 0\n'
    '            sync_report.metadata_reconciled = 0\n'
    '            sync_report.metadata_conflicts = 0\n'
    '            sync_report.metadata_blocked = 0\n'
    '            sync_report.metadata_deferred = 0\n'
    '            sync_report.metadata_auth_waiting = 0\n'
    '            sync_report.metadata_remote_errors = 0\n'
    '            sync_report.metadata_queue_waiting = queue_repository:countMetadataWaiting()\n\n'
    '            sync_report.archive_enabled = archive_enabled\n'
)
replace_once(
    "readwisereader.koplugin/sync/worker.lua",
    '        -- Process every durable create, including work left by a previous\n'
    '        -- KOReader process, before the document feed. New local work from all\n'
    '        -- authoritative managed sidecars was already queued above.\n'
    '        stage = "create_queue_processing"\n',
    '        -- Reader metadata edits share the durable queue but have their own\n'
    '        -- explicit worker phase. This runs only after the same read-only\n'
    '        -- reachability/auth preflight that gates all other remote writes.\n'
    '        stage = "metadata_queue_processing"\n'
    '        local metadata_mutations = MetadataMutations:new{\n'
    '            reader = reader,\n'
    '            documents = repository,\n'
    '            queue = queue_repository,\n'
    '            annotation_metadata = annotation_metadata_repository,\n'
    '            hasher = Hash,\n'
    '        }\n'
    '        local metadata_report = metadata_mutations:processQueue()\n\n'
    '        -- Process every durable create, including work left by a previous\n'
    '        -- KOReader process, before the document feed. New local work from all\n'
    '        -- authoritative managed sidecars was already queued above.\n'
    '        stage = "create_queue_processing"\n'
)
replace_once(
    "readwisereader.koplugin/sync/worker.lua",
    '        sync_report.remote_preflight = "passed"\n'
    '        sync_report.network_available = true\n\n'
    '        stage = "content_refresh_reconcile"\n',
    '        sync_report.remote_preflight = "passed"\n'
    '        sync_report.network_available = true\n'
    '        Worker._applyMetadataMutationReport(\n'
    '            sync_report, metadata_report, repository, postprocess\n'
    '        )\n'
    '        sync_report.metadata_queue_waiting = metadata_report.waiting_after\n'
    '            or queue_repository:countMetadataWaiting()\n\n'
    '        stage = "content_refresh_reconcile"\n'
)
replace_once(
    "readwisereader.koplugin/sync/worker.lua",
    'Worker._copyMetadata = copyMetadata\n',
    '''function Worker._applyMetadataMutationReport(sync_report, metadata_report, repository, postprocess)
    metadata_report = metadata_report or {}
    sync_report.metadata_queue_processed = metadata_report.processed or 0
    sync_report.metadata_note_updates = metadata_report.note_updates or 0
    sync_report.metadata_tag_updates = metadata_report.tag_updates or 0
    sync_report.metadata_reconciled = metadata_report.reconciled or 0
    sync_report.metadata_conflicts = metadata_report.conflicts or 0
    sync_report.metadata_blocked = metadata_report.blocked or 0
    sync_report.metadata_deferred = metadata_report.deferred or 0
    sync_report.metadata_auth_waiting = metadata_report.auth_waiting or 0
    sync_report.metadata_remote_errors = metadata_report.remote_errors or 0
    sync_report.metadata_queue_waiting = metadata_report.waiting_after or 0

    for _, update in ipairs(metadata_report.document_metadata_updates or {}) do
        local local_document = type(update.id) == "string" and repository:getById(update.id) or nil
        if local_document
            and local_document.is_managed == true
            and local_document.is_local_present == true
            and type(local_document.local_path) == "string"
            and local_document.local_path ~= "" then
            postprocess(local_document.local_path).metadata = copyMetadata(update)
        end
    end
    return sync_report
end

Worker._copyMetadata = copyMetadata
'''
)

replace_once(
    "readwisereader.koplugin/ui/sync.lua",
    '        string.format(_("Annotation remote errors: %d"), report.annotation_remote_errors or 0),\n'
    '        "",\n'
    '        string.format(\n'
    '            _("Reader → KOReader pre-sync reconciliation: %s"),',
    '        string.format(_("Annotation remote errors: %d"), report.annotation_remote_errors or 0),\n'
    '        "",\n'
    '        string.format(_("Reader metadata queue processed: %d"), report.metadata_queue_processed or 0),\n'
    '        string.format(_("Reader metadata note updates: %d"), report.metadata_note_updates or 0),\n'
    '        string.format(_("Reader metadata tag updates: %d"), report.metadata_tag_updates or 0),\n'
    '        string.format(_("Reader metadata reconciled: %d"), report.metadata_reconciled or 0),\n'
    '        string.format(_("Reader metadata note conflicts: %d"), report.metadata_conflicts or 0),\n'
    '        string.format(_("Reader metadata blocked: %d"), report.metadata_blocked or 0),\n'
    '        string.format(_("Reader metadata retries deferred: %d"), report.metadata_deferred or 0),\n'
    '        string.format(_("Reader metadata auth waits: %d"), report.metadata_auth_waiting or 0),\n'
    '        string.format(_("Reader metadata queue waiting: %d"), report.metadata_queue_waiting or 0),\n'
    '        string.format(_("Reader metadata remote errors: %d"), report.metadata_remote_errors or 0),\n'
    '        "",\n'
    '        string.format(\n'
    '            _("Reader → KOReader pre-sync reconciliation: %s"),'
)
replace_once(
    "readwisereader.koplugin/ui/sync.lua",
    'SyncUI._errorText = errorText\n',
    'SyncUI._errorText = errorText\nSyncUI._summaryText = summaryText\n'
)

replace_once(
    "readwisereader.koplugin/tests/test_storage_db.lua",
    '        "documents", "annotation_links", "queue", "sync_meta", "remote_highlights",\n',
    '        "documents", "annotation_links", "queue", "sync_meta", "remote_highlights",\n'
    '        "annotation_metadata",\n'
)

replace_once(
    "readwisereader.koplugin/tests/test_worker.lua",
    '    assert(Worker._annotationQueueStatus({\n'
    '        documents_authoritative = 0,\n'
    '    }, true) == nil)\n'
    'end',
    '''    assert(Worker._annotationQueueStatus({
        documents_authoritative = 0,
    }, true) == nil)

    local postprocess_by_path = {}
    local function postprocess(path)
        postprocess_by_path[path] = postprocess_by_path[path] or { path = path }
        return postprocess_by_path[path]
    end
    local report = {}
    Worker._applyMetadataMutationReport(report, {
        processed = 3,
        note_updates = 1,
        tag_updates = 1,
        reconciled = 1,
        conflicts = 1,
        blocked = 2,
        deferred = 1,
        auth_waiting = 1,
        remote_errors = 2,
        waiting_after = 4,
        document_metadata_updates = {
            {
                id = "doc-1",
                title = "Remote title",
                author = "Remote author",
                summary = "Remote summary",
                site_name = "Remote site",
                tags = { "reader-new", "preserved" },
            },
            {
                id = "doc-remote-only",
                title = "No local projection",
                tags = { "skip" },
            },
        },
    }, {
        getById = function(_, id)
            if id == "doc-1" then
                return {
                    reader_id = id,
                    is_managed = true,
                    is_local_present = true,
                    local_path = "/Readwise/doc-1.epub",
                }
            end
            return {
                reader_id = id,
                is_managed = true,
                is_local_present = false,
                local_path = nil,
            }
        end,
    }, postprocess)

    assert(report.metadata_queue_processed == 3)
    assert(report.metadata_note_updates == 1)
    assert(report.metadata_tag_updates == 1)
    assert(report.metadata_reconciled == 1)
    assert(report.metadata_conflicts == 1)
    assert(report.metadata_blocked == 2)
    assert(report.metadata_deferred == 1)
    assert(report.metadata_auth_waiting == 1)
    assert(report.metadata_remote_errors == 2)
    assert(report.metadata_queue_waiting == 4)
    local projected = assert(postprocess_by_path["/Readwise/doc-1.epub"])
    assert(projected.metadata.title == "Remote title")
    assert(projected.metadata.summary == "Remote summary")
    assert(projected.metadata.tags[1] == "reader-new")
    assert(postprocess_by_path["doc-remote-only"] == nil)
end'''
)

replace_once(
    "readwisereader.koplugin/tests/test_metadata_mutations.lua",
    '    function reader:getDocument(id)\n'
    '        local value = remote[id]\n'
    '        if not value then return nil, { kind = "not_found", retryable = false } end\n'
    '        return copy(value)\n'
    '    end\n'
    '    function reader:updateDocument(id, patch)\n'
    '        state.patches = state.patches + 1\n'
    '        local value = remote[id]\n',
    '    function reader:getDocument(id)\n'
    '        if state.get_error then\n'
    '            local err = state.get_error\n'
    '            if state.get_error_once then state.get_error = nil end\n'
    '            return nil, copy(err)\n'
    '        end\n'
    '        local value = remote[id]\n'
    '        if not value then return nil, { kind = "not_found", retryable = false } end\n'
    '        return copy(value)\n'
    '    end\n'
    '    function reader:updateDocument(id, patch)\n'
    '        state.patches = state.patches + 1\n'
    '        if state.patch_error then\n'
    '            local err = state.patch_error\n'
    '            if state.patch_error_once then state.patch_error = nil end\n'
    '            return nil, copy(err)\n'
    '        end\n'
    '        local value = remote[id]\n'
)

extra_tests = r'''
local function noteCreateAndEdit()
    local q = queueStub()
    local remote = { ["doc-1"] = { id="doc-1", category="article", tags={}, notes="" } }
    local state = {}; local e = newEngine(remote, q, state)
    assert(e:queueDocumentNote({ reader_id="doc-1", remote_notes="" }, "created"))
    assert(e:processQueue().note_updates == 1)
    assert(remote["doc-1"].notes == "created")
    assert(e:queueDocumentNote({ reader_id="doc-1", remote_notes="created" }, "edited"))
    assert(e:processQueue().note_updates == 1)
    assert(remote["doc-1"].notes == "edited")
    assert(state.patches == 2)
end

local function keepKindleRebasesAfterConflict()
    local q = queueStub()
    local remote = { ["doc-1"] = { id="doc-1", category="article", tags={}, notes="Reader changed" } }
    local state = {}; local e = newEngine(remote, q, state)
    assert(e:queueDocumentNote({ reader_id="doc-1", remote_notes="old" }, "Kindle wins"))
    assert(e:processQueue().conflicts == 1)
    assert(state.patches == 0)
    assert(e:queueDocumentNote({ reader_id="doc-1", remote_notes="Reader changed" }, "Kindle wins"))
    local second = e:processQueue()
    assert(second.note_updates == 1 and second.conflicts == 0)
    assert(remote["doc-1"].notes == "Kindle wins")
    assert(state.patches == 1)
end

local function tagRemovePreservesConcurrentRemoteAdd()
    local q = queueStub()
    local remote = {
        ["doc-1"] = { id="doc-1", category="article", tags={"a","b","remote"}, notes="" },
    }
    local state = {}; local e = newEngine(remote, q, state)
    assert(e:queueDocumentTags(
        { reader_id="doc-1", remote_tags={"a","b"} },
        {"a"}
    ))
    assert(e:processQueue().tag_updates == 1)
    assert(table.concat(remote["doc-1"].tags, "|") == "a|remote")
end

local function tagAddDoesNotReintroduceRemoteRemoval()
    local q = queueStub()
    local remote = { ["doc-1"] = { id="doc-1", category="article", tags={"b"}, notes="" } }
    local state = {}; local e = newEngine(remote, q, state)
    assert(e:queueDocumentTags(
        { reader_id="doc-1", remote_tags={"a","b"} },
        {"a","b","kindle"}
    ))
    assert(e:processQueue().tag_updates == 1)
    assert(table.concat(remote["doc-1"].tags, "|") == "b|kindle")
end

local function existingTagDeltaReconcilesWithoutPatch()
    local q = queueStub()
    local remote = { ["doc-1"] = { id="doc-1", category="article", tags={"a"}, notes="" } }
    local state = {}; local e = newEngine(remote, q, state)
    assert(e:queueDocumentTags({ reader_id="doc-1", remote_tags={"a"} }, {"a"}))
    local r = e:processQueue()
    assert(r.reconciled == 1 and r.tag_updates == 0 and state.patches == 0)
end

local function linkedHighlightTagsUpdate()
    local q = queueStub()
    local remote = {
        ["hl-1"] = { id="hl-1", parent_id="doc-1", category="highlight", tags={"old"}, notes="" },
    }
    local state = {}; local e = newEngine(remote, q, state)
    assert(e:queueHighlightTags({
        local_annotation_id="ann-1",
        reader_document_id="doc-1",
        reader_highlight_document_id="hl-1",
    }, {"old"}, {"new"}))
    local r = e:processQueue()
    assert(r.tag_updates == 1 and r.blocked == 0)
    assert(remote["hl-1"].tags[1] == "new")
    assert(state.synced_annotation.id == "ann-1")
end

local function timeoutWithoutWriteRetriesSafely()
    local q = queueStub()
    local remote = { ["doc-1"] = { id="doc-1", category="article", tags={}, notes="old" } }
    local state = {
        patch_error = { kind="timeout", retryable=true, message="timeout" },
        patch_error_once = true,
    }
    local e = newEngine(remote, q, state)
    assert(e:queueDocumentNote({ reader_id="doc-1", remote_notes="old" }, "new"))
    local first = e:processQueue()
    assert(first.deferred == 1 and remote["doc-1"].notes == "old")
    for _, item in pairs(q.items) do item.status = "pending" end
    local second = e:processQueue()
    assert(second.note_updates == 1)
    assert(remote["doc-1"].notes == "new")
    assert(state.patches == 2)
end

local function authWaitsWithoutPatch()
    local q = queueStub()
    local remote = { ["doc-1"] = { id="doc-1", category="article", tags={}, notes="old" } }
    local state = {
        get_error = { kind="auth", retryable=false, message="unauthorized" },
    }
    local e = newEngine(remote, q, state)
    assert(e:queueDocumentNote({ reader_id="doc-1", remote_notes="old" }, "new"))
    local r = e:processQueue()
    assert(r.auth_waiting == 1 and r.remote_errors == 1 and state.patches == 0)
end

local function rateLimitDefersWithoutChangingRemote()
    local q = queueStub()
    local remote = { ["doc-1"] = { id="doc-1", category="article", tags={}, notes="old" } }
    local state = {
        patch_error = { kind="rate_limit", retryable=true, retry_after=30, message="slow down" },
    }
    local e = newEngine(remote, q, state)
    assert(e:queueDocumentNote({ reader_id="doc-1", remote_notes="old" }, "new"))
    local r = e:processQueue()
    assert(r.deferred == 1 and r.remote_errors == 1)
    assert(remote["doc-1"].notes == "old")
end

local function missingRemoteBlocks()
    local q = queueStub()
    local remote = {}
    local state = {}; local e = newEngine(remote, q, state)
    assert(e:queueDocumentNote({ reader_id="missing", remote_notes="" }, "new"))
    local r = e:processQueue()
    assert(r.blocked == 1 and r.remote_errors == 1 and state.patches == 0)
end
'''
replace_once(
    "readwisereader.koplugin/tests/test_metadata_mutations.lua",
    '\nreturn function()\n',
    '\n' + extra_tests + '\nreturn function()\n'
)
replace_once(
    "readwisereader.koplugin/tests/test_metadata_mutations.lua",
    '    pendingDocumentStateReflectsQueuedIntent()\n'
    'end',
    '    pendingDocumentStateReflectsQueuedIntent()\n'
    '    noteCreateAndEdit()\n'
    '    keepKindleRebasesAfterConflict()\n'
    '    tagRemovePreservesConcurrentRemoteAdd()\n'
    '    tagAddDoesNotReintroduceRemoteRemoval()\n'
    '    existingTagDeltaReconcilesWithoutPatch()\n'
    '    linkedHighlightTagsUpdate()\n'
    '    timeoutWithoutWriteRetriesSafely()\n'
    '    authWaitsWithoutPatch()\n'
    '    rateLimitDefersWithoutChangingRemote()\n'
    '    missingRemoteBlocks()\n'
    'end'
)

replace_once(
    "readwisereader.koplugin/tests/test_sync_ui.lua",
    '    assert(SyncUI._errorText({ kind = "worker", stage = "annotation_backlog" }):find("annotation_backlog", 1, true))\n',
    '    assert(SyncUI._errorText({ kind = "worker", stage = "annotation_backlog" }):find("annotation_backlog", 1, true))\n'
    '    local metadata_summary = SyncUI._summaryText{\n'
    '        metadata_queue_processed = 2,\n'
    '        metadata_note_updates = 1,\n'
    '        metadata_tag_updates = 1,\n'
    '        metadata_conflicts = 1,\n'
    '        metadata_queue_waiting = 3,\n'
    '    }\n'
    '    assert(metadata_summary:find("Reader metadata queue processed: 2", 1, true))\n'
    '    assert(metadata_summary:find("Reader metadata note conflicts: 1", 1, true))\n'
    '    assert(metadata_summary:find("Reader metadata queue waiting: 3", 1, true))\n'
)

print("v1.3 worker/metadata hardening patch applied")
