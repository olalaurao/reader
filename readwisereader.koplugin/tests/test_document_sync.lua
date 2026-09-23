-- SPDX-License-Identifier: AGPL-3.0-only

local DocumentsSync = require("sync/documents")

local function copy(value)
    local out = {}
    for key, item in pairs(value or {}) do out[key] = item end
    return out
end

local function fakeRepository(initial)
    local rows = {}
    for id, row in pairs(initial or {}) do rows[id] = copy(row) end
    return {
        rows = rows,
        getById = function(self, id) return self.rows[id] and copy(self.rows[id]) or nil end,
        listManaged = function(self)
            local result = {}
            for _, row in pairs(self.rows) do result[#result + 1] = copy(row) end
            return result
        end,
        upsertRemote = function(self, doc, seen)
            local row = self.rows[doc.id] or {
                reader_id = doc.id, is_managed = true, is_local_present = false,
            }
            row.parent_id, row.category, row.location = doc.parent_id, doc.category, doc.location
            row.title, row.author, row.site_name = doc.title, doc.author, doc.site_name
            row.remote_updated_at, row.last_seen_remote_at = doc.updated_at, seen
            self.rows[doc.id] = row
            return copy(row)
        end,
        setLastSyncError = function(self, id, kind)
            self.rows[id] = self.rows[id] or { reader_id = id }
            self.rows[id].last_sync_error = kind
        end,
        setLocalState = function(self, id, state)
            self.rows[id] = self.rows[id] or { reader_id = id }
            for key, value in pairs(state) do self.rows[id][key] = value end
        end,
    }
end

local function fakeMeta(initial)
    local values = copy(initial)
    return {
        values = values,
        get = function(self, key) return self.values[key] end,
        set = function(self, key, value) self.values[key] = value end,
    }
end

local function newSync(options)
    local repository = options.repository or fakeRepository()
    local meta = options.meta or fakeMeta()
    local installs, collection_calls, metadata_calls = {}, {}, {}
    local times, time_index = options.now_values or { 1000, 1010 }, 0
    local syncer = DocumentsSync:new{
        reader = options.reader,
        repository = repository,
        sync_meta = meta,
        config = {
            getSyncLocations = function() return options.locations or { "new", "later" } end,
            getSyncCategories = function() return options.categories or { "article" } end,
        },
        materializer = options.materializer or {
            installDocument = function(_, doc)
                installs[#installs + 1] = doc.id
                local path = "/Readwise/" .. doc.id .. ".html"
                repository:setLocalState(doc.id, {
                    local_path = path, is_local_present = true, local_format = "html",
                })
                return { path = path }
            end,
        },
        collections = {
            syncLocation = function(_, path, location)
                collection_calls[#collection_calls + 1] = { path = path, location = location }
                return true
            end,
        },
        koreader_documents = {
            writeMetadata = function(_, path, doc)
                metadata_calls[#metadata_calls + 1] = { path = path, title = doc.title }
                return true
            end,
        },
        now = function()
            time_index = time_index + 1
            return times[time_index] or times[#times]
        end,
        format_time = function(epoch) return string.format("T%06d", epoch) end,
        overlap_seconds = 5,
        file_exists = function(path)
            for _, row in pairs(repository.rows) do
                if row.local_path == path and row.is_local_present then return true end
            end
            return false
        end,
    }
    return syncer, repository, meta, installs, collection_calls, metadata_calls
end

local function doc(id, location, title, updated, html)
    return {
        id = id, category = "article", location = location,
        title = title, updated_at = updated, html_content = html,
    }
end

return function()
    do
        local reader = {
            iterateDocuments = function(_, options, callback)
                if options.with_html_content then
                    if options.location == "new" then callback(doc("a", "new", "Alpha", "u1", "<p>A</p>")) end
                    if options.location == "later" then callback(doc("b", "later", "Beta", "u1", "<p>B</p>")) end
                else
                    callback(doc("a", "new", "Alpha", "u1"))
                    callback(doc("b", "later", "Beta", "u1"))
                end
                return { pages = 1, duplicates = 0 }
            end,
        }
        local syncer, repository, meta, installs = newSync{ reader = reader }
        local report, err = syncer:sync{}
        assert(err == nil)
        assert(report.mode == "full")
        assert(report.downloaded == 2)
        assert(#installs == 2)
        assert(repository.rows.a.local_path == "/Readwise/a.html")
        assert(repository.rows.b.local_path == "/Readwise/b.html")
        assert(meta.values.document_watermark == "T001000")
        assert(meta.values.document_query_after == "T000995")
        assert(meta.values.document_filter_scope == "locations=later,new;categories=article")
    end

    do
        local repository = fakeRepository({
            a = {
                reader_id = "a", category = "article", location = "new",
                title = "Alpha", remote_updated_at = "u1",
                local_path = "/Readwise/a.html", is_local_present = true, is_managed = true,
            },
        })
        local meta = fakeMeta({
            document_watermark = "T001000",
            document_query_after = "T000995",
            document_filter_scope = "locations=later,new;categories=article",
        })
        local reader = {
            iterateDocuments = function(_, options)
                assert(options.updated_after == "T000995")
                return { pages = 1, duplicates = 0 }
            end,
            getDocument = function() error("no pending document expected") end,
        }
        local syncer, _, _, installs = newSync{
            reader = reader, repository = repository, meta = meta, now_values = { 1020, 1021 },
        }
        local report, err = syncer:sync{}
        assert(err == nil)
        assert(report.mode == "incremental")
        assert(report.downloaded == 0 and #installs == 0)
        assert(meta.values.document_watermark == "T001020")
        assert(meta.values.document_query_after == "T001015")
    end

    do
        local repository = fakeRepository({
            a = {
                reader_id = "a", category = "article", location = "new",
                title = "Old", author = "A", remote_updated_at = "u1",
                local_path = "/Readwise/a.html", is_local_present = true, is_managed = true,
            },
        })
        local meta = fakeMeta({
            document_watermark = "T001000",
            document_query_after = "T000995",
            document_filter_scope = "locations=later,new;categories=article",
        })
        local reader = {
            iterateDocuments = function(_, _, callback)
                callback(doc("a", "later", "Renamed", "u2"))
                return { pages = 1, duplicates = 0 }
            end,
            getDocument = function() error("existing document must not be re-downloaded") end,
        }
        local syncer, repo, _, installs, collections, metadata = newSync{
            reader = reader, repository = repository, meta = meta, now_values = { 1030, 1031 },
        }
        local report, err = syncer:sync{}
        assert(err == nil)
        assert(#installs == 0)
        assert(repo.rows.a.title == "Renamed")
        assert(repo.rows.a.location == "later")
        assert(repo.rows.a.local_path == "/Readwise/a.html")
        assert(report.location_moved == 1)
        assert(report.metadata_updated == 1)
        assert(report.content_refresh_deferred == 1)
        assert(#collections >= 1 and #metadata == 1)
    end


    do
        local reader = {
            iterateDocuments = function()
                return { pages = 1, duplicates = 0 }
            end,
        }
        local syncer, _, meta = newSync{ reader = reader }
        local report, err = syncer:sync{ defer_watermark = true }
        assert(err == nil)
        assert(report.proposed_watermark == "T001000")
        assert(report.proposed_query_after == "T000995")
        assert(meta.values.document_watermark == nil, "worker-deferred sync must not commit watermark")
        assert(meta.values.last_successful_sync_at == nil)
    end

    do
        -- Expanding filters after a successful sync must backfill historical
        -- documents instead of relying on updatedAfter.
        local meta = fakeMeta({
            document_watermark = "T001000",
            document_query_after = "T000995",
            document_filter_scope = "locations=new;categories=article",
        })
        local saw_incremental = false
        local reader = {
            iterateDocuments = function(_, options, callback)
                if options.updated_after then saw_incremental = true end
                if options.with_html_content and options.location == "archive" then
                    callback(doc("old", "archive", "Historical", "u0", "<p>Old</p>"))
                end
                return { pages = 1, duplicates = 0 }
            end,
        }
        local syncer, _, updated_meta, installs = newSync{
            reader = reader,
            meta = meta,
            locations = { "new", "archive" },
            now_values = { 1040, 1041 },
        }
        local report, err = syncer:sync{}
        assert(err == nil)
        assert(report.mode == "full")
        assert(report.filter_scope_changed == true)
        assert(saw_incremental == false)
        assert(report.downloaded == 1 and installs[1] == "old")
        assert(updated_meta.values.document_filter_scope == "locations=archive,new;categories=article")
    end

    do
        -- Permanent per-document content failures (such as Reader returning no
        -- processed HTML) must not strand the whole-library watermark.
        local reader = {
            iterateDocuments = function(_, options, callback)
                if options.with_html_content and options.location == "new" then
                    callback(doc("empty", "new", "No body", "u1", nil))
                elseif not options.with_html_content then
                    callback(doc("empty", "new", "No body", "u1"))
                end
                return { pages = 1, duplicates = 0 }
            end,
        }
        local repository = fakeRepository()
        local materializer = {
            installDocument = function(_, document)
                repository:upsertRemote(document, 1000)
                return nil, { kind = "content", retryable = false }
            end,
        }
        local syncer, _, meta = newSync{
            reader = reader, repository = repository, materializer = materializer,
        }
        local report, err = syncer:sync{}
        assert(err == nil)
        assert(report.errors == 0)
        assert(report.nonretryable_skipped == 1)
        assert(report.retryable_item_errors == 0)
        assert(meta.values.document_watermark == "T001000")
        assert(repository.rows.empty.last_sync_error == "content")

        -- A no-change incremental pass must not refetch this permanent skip.
        local no_change_reader = {
            iterateDocuments = function(_, options)
                assert(options.updated_after ~= nil)
                return { pages = 1, duplicates = 0 }
            end,
            getDocument = function()
                error("permanent skip must not be retried without a remote revision")
            end,
        }
        local second_sync = newSync{
            reader = no_change_reader,
            repository = repository,
            meta = meta,
            now_values = { 1020, 1021 },
        }
        local second_report, second_err = second_sync:sync{}
        assert(second_err == nil)
        assert(second_report.mode == "incremental")
        assert(second_report.nonretryable_skipped == 0)
        assert(second_report.retryable_item_errors == 0)
        assert(second_report.downloaded == 0)

        -- A later remote revision is allowed to retry the previously skipped item.
        local changed_reader = {
            iterateDocuments = function(_, options, callback)
                assert(options.updated_after ~= nil)
                callback(doc("empty", "new", "Now has body", "u2"))
                return { pages = 1, duplicates = 0 }
            end,
            getDocument = function(_, id)
                assert(id == "empty")
                return doc("empty", "new", "Now has body", "u2", "<p>Now readable</p>")
            end,
        }
        local third_sync, _, _, third_installs = newSync{
            reader = changed_reader,
            repository = repository,
            meta = meta,
            now_values = { 1030, 1031 },
        }
        local third_report, third_err = third_sync:sync{}
        assert(third_err == nil)
        assert(third_report.mode == "incremental")
        assert(third_report.downloaded == 1)
        assert(third_installs[1] == "empty")
    end

    do
        local reader = {
            iterateDocuments = function(_, options, callback)
                if options.with_html_content and options.location == "new" then
                    callback(doc("retry", "new", "Retry", "u1", "<p>x</p>"))
                elseif not options.with_html_content then
                    callback(doc("retry", "new", "Retry", "u1"))
                end
                return { pages = 1, duplicates = 0 }
            end,
        }
        local repository = fakeRepository()
        local materializer = {
            installDocument = function(_, document)
                repository:upsertRemote(document, 1000)
                return nil, { kind = "io", stage = "write", retryable = true }
            end,
        }
        local syncer, _, meta = newSync{
            reader = reader, repository = repository, materializer = materializer,
        }
        local report, err = syncer:sync{}
        assert(err == nil)
        assert(report.errors == 1)
        assert(report.retryable_item_errors == 1)
        assert(report.retryable_error_stages.write == 1)
        assert(meta.values.document_watermark == nil)
    end

    do
        local meta = fakeMeta({
            document_watermark = "T001000",
            document_query_after = "T000995",
            document_filter_scope = "locations=later,new;categories=article",
        })
        local syncer = newSync{
            meta = meta,
            reader = { iterateDocuments = function() return nil, { kind = "timeout" } end },
        }
        local report, err = syncer:sync{}
        assert(report == nil and err.kind == "timeout")
        assert(meta.values.document_watermark == "T001000")
    end
end
