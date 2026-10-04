-- SPDX-License-Identifier: AGPL-3.0-only

local DocumentAudit = require("sync/document_audit")
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
        getById = function(self, id)
            return self.rows[id] and copy(self.rows[id]) or nil
        end,
        listManaged = function(self)
            local result = {}
            for _, row in pairs(self.rows) do result[#result + 1] = copy(row) end
            return result
        end,
        upsertRemote = function(self, document, seen_at)
            local row = self.rows[document.id] or {
                reader_id = document.id,
                is_managed = true,
                is_local_present = false,
            }
            row.reader_id = document.id
            row.parent_id = document.parent_id
            row.category = document.category
            row.location = document.location
            row.title = document.title
            row.author = document.author
            row.site_name = document.site_name
            row.remote_updated_at = document.updated_at
            row.last_seen_remote_at = seen_at
            self.rows[document.id] = row
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
        markContentRefreshPending = function(self, id, updated_at, detected_at)
            local row = assert(self.rows[id])
            row.content_refresh_pending = true
            row.content_refresh_remote_updated_at = updated_at
            row.content_refresh_detected_at = detected_at
            return copy(row)
        end,
        countContentRefreshPending = function(self)
            local count = 0
            for _, row in pairs(self.rows) do
                if row.content_refresh_pending then count = count + 1 end
            end
            return count
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

local function article(id, location, updated)
    return {
        id = id,
        category = "article",
        location = location or "new",
        title = "Title " .. id,
        updated_at = updated or "u1",
        html_content = "<p>" .. id .. "</p>",
    }
end

local function newSync(options)
    local repository = options.repository or fakeRepository()
    local meta = options.meta or fakeMeta({
        document_watermark = "T001000",
        document_query_after = "T000995",
        document_filter_scope = "locations=new;categories=article",
        metadata_projection_version = DocumentsSync.METADATA_PROJECTION_VERSION,
    })
    local installs = {}
    local times = { 1100, 1101 }
    local time_index = 0
    local materializer = options.materializer or {
        installDocument = function(_, document)
            installs[#installs + 1] = document.id
            local path = "/Readwise/" .. document.id .. ".html"
            repository:setLocalState(document.id, {
                local_path = path,
                local_format = "html",
                is_local_present = true,
                last_sync_error = nil,
            })
            return { path = path }
        end,
    }
    local syncer = DocumentsSync:new{
        reader = options.reader,
        repository = repository,
        sync_meta = meta,
        materializer = materializer,
        collections = { syncLocation = function() return true end },
        koreader_documents = { writeMetadata = function() return true end },
        config = {
            getSyncLocations = function() return options.locations or { "new" } end,
            getSyncCategories = function() return options.categories or { "article" } end,
        },
        now = function()
            time_index = time_index + 1
            return times[time_index] or times[#times]
        end,
        format_time = function(epoch) return string.format("T%06d", epoch) end,
        overlap_seconds = 5,
        file_exists = options.file_exists or function(path)
            for _, row in pairs(repository.rows) do
                if row.local_path == path and row.is_local_present then return true end
            end
            return false
        end,
    }
    return syncer, repository, meta, installs
end

return function()
    do
        local audit = DocumentAudit:new(
            { locations = { new = true }, categories = { article = true } },
            { article = true, pdf = true, epub = true }
        )
        audit:observeMetadata(article("a", "new"))
        audit:observeMetadata({ id = "e", category = "epub", location = "new", title = "EPUB" })
        audit:observeMetadata({ id = "mail", category = "email", location = "new", title = "Mail" })
        audit:observeMetadata(article("arch", "archive"))
        audit:observeMetadata({ id = "h", category = "highlight", location = "new", parent_id = "a" })
        audit:markOutcome("a", "downloaded")
        local report = { errors = 0 }
        audit:apply(report)

        assert(report.metadata_seen == 4)
        assert(report.child_records == 1)
        assert(report.eligible_metadata == 1)
        assert(report.excluded_location_total == 1)
        assert(report.excluded_by_location.archive == 1)
        assert(report.excluded_category_total == 1)
        assert(report.excluded_by_category.epub == 1)
        assert(report.unsupported_category_total == 1)
        assert(report.unsupported_by_category.email == 1)
        assert(report.filtered_out == 3)
        assert(report.audit_accounted == 1 and report.audit_unaccounted == 0)
        assert(report.metadata_unaccounted == 0)
        assert(report.errors == 0)
    end

    do
        local audit = DocumentAudit:new(
            { locations = { new = true }, categories = { article = true } },
            { article = true, pdf = true, epub = true }
        )
        audit:observeMetadata(article("unaccounted", "new"))
        local report = { errors = 0 }
        audit:apply(report)
        assert(report.audit_unaccounted == 1)
        assert(report.audit_invariant_errors == 1)
        assert(report.errors == 1)
    end

    do
        -- Full metadata sees two eligible ids, but the bulk content LIST omits
        -- one. The omitted id must be fetched directly and materialized.
        local repository = fakeRepository({
            localdoc = {
                reader_id = "localdoc",
                category = "article",
                location = "new",
                title = "Title localdoc",
                remote_updated_at = "u1",
                local_path = "/Readwise/localdoc.html",
                is_local_present = true,
                is_managed = true,
            },
            missing = {
                reader_id = "missing",
                category = "article",
                location = "new",
                title = "Title missing",
                remote_updated_at = "u1",
                local_path = "/Readwise/missing.html",
                is_local_present = true,
                is_managed = true,
            },
        })
        local direct_reads = 0
        local reader = {
            iterateDocuments = function(_, options, callback)
                if options.with_html_content then
                    callback(article("localdoc", "new", "u1"))
                else
                    callback(article("localdoc", "new", "u1"))
                    callback(article("missing", "new", "u1"))
                end
                return { pages = 1, duplicates = 0 }
            end,
            getDocument = function(_, id, with_html, with_raw)
                assert(id == "missing")
                assert(with_html == true)
                assert(with_raw == false)
                direct_reads = direct_reads + 1
                return article("missing", "new", "u1")
            end,
        }
        local syncer, repo, _, installs = newSync{
            reader = reader,
            repository = repository,
            file_exists = function(path)
                return path == "/Readwise/localdoc.html"
            end,
        }
        local report, err = syncer:sync{ full_rescan = true }
        assert(err == nil)
        assert(direct_reads == 1)
        assert(#installs == 1 and installs[1] == "missing")
        assert(repo.rows.missing.is_local_present == true)
        assert(report.content_scan_missing == 1)
        assert(report.content_scan_direct_reads == 1)
        assert(report.content_scan_direct_recovered == 1)
        assert(report.content_scan_direct_failed == 0)
        assert(report.audit_already_local == 1)
        assert(report.audit_downloaded == 1)
        assert(report.eligible_documents == 2)
        assert(report.audit_accounted == 2 and report.audit_unaccounted == 0)
        assert(report.metadata_unaccounted == 0)
        assert(report.unchanged == 1)
        assert(report.downloaded == 1)
        assert(report.errors == 0)
        assert(report.proposed_watermark ~= nil)
    end

    do
        local reader = {
            iterateDocuments = function(_, options, callback)
                if not options.with_html_content then callback(article("missing")) end
                return { pages = 1, duplicates = 0 }
            end,
            getDocument = function()
                return nil, { kind = "timeout", stage = "api", retryable = true }
            end,
        }
        local syncer = newSync{ reader = reader }
        local report, err = syncer:sync{ full_rescan = true }
        assert(err == nil)
        assert(report.content_scan_missing == 1)
        assert(report.content_scan_direct_failed == 1)
        assert(report.retryable_item_errors == 1)
        assert(report.audit_retryable_failed == 1)
        assert(report.audit_unaccounted == 0)
        assert(report.errors == 1)
        assert(report.proposed_watermark == nil)
        assert(report.retryable_error_reasons["article / api"].count == 1)
        assert(report.content_lookup_failure_reasons["article / direct lookup api"].count == 1)
    end

    do
        local reader = {
            iterateDocuments = function(_, _, callback)
                callback(article("bad-article"))
                return { pages = 1, duplicates = 0 }
            end,
            getDocument = function() error("content LIST already returned the document") end,
        }
        local syncer = newSync{
            reader = reader,
            materializer = {
                installDocument = function()
                    return nil, {
                        kind = "content",
                        retryable = false,
                        message = "Reader did not provide usable processed HTML content for this document.",
                    }
                end,
            },
        }
        local report, err = syncer:sync{ full_rescan = true }
        assert(err == nil)
        assert(report.nonretryable_skipped == 1)
        assert(report.audit_permanent_skipped == 1)
        assert(report.audit_unaccounted == 0)
        assert(report.errors == 0)
        assert(report.materialization_skip_reasons["article / processed HTML missing"].count == 1)
    end

    do
        local pdf = {
            id = "bad-pdf",
            category = "pdf",
            location = "new",
            title = "Bad PDF",
            updated_at = "u1",
        }
        local reader = {
            iterateDocuments = function(_, _, callback)
                callback(pdf)
                return { pages = 1, duplicates = 0 }
            end,
            getDocument = function() error("not expected") end,
        }
        local syncer = newSync{
            reader = reader,
            categories = { "pdf" },
            materializer = {
                installDocument = function()
                    return nil, {
                        kind = "content",
                        stage = "raw_fallback",
                        detail = "raw_unavailable",
                        retryable = false,
                    }
                end,
            },
        }
        local report, err = syncer:sync{ full_rescan = true }
        assert(err == nil)
        assert(report.materialization_skip_reasons[
            "pdf / raw source unavailable + no HTML fallback"
        ].count == 1)
        assert(report.audit_accounted == 1)
    end
end
