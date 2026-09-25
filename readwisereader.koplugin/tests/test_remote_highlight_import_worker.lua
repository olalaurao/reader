-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubs(run, options)
    options = options or {}
    local names = {
        "sync/remote_highlight_import_worker",
        "config",
        "storage/db",
        "storage/documents",
        "storage/remote_highlights",
        "storage/sync_meta",
        "api/http",
        "api/reader",
        "api/readwise",
        "sync/remote_highlight_cache",
    }
    local loaded, preload = {}, {}
    for _, name in ipairs(names) do
        loaded[name] = package.loaded[name]
        preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    local state = { db_closed = 0, config_closed = 0, cache_calls = 0 }

    package.preload["config"] = function()
        return {
            new = function()
                return { close = function() state.config_closed = state.config_closed + 1 end }
            end,
        }
    end
    package.preload["storage/db"] = function()
        return {
            new = function()
                return { close = function() state.db_closed = state.db_closed + 1 end }
            end,
        }
    end
    package.preload["storage/documents"] = function()
        return {
            new = function()
                return {
                    getByLocalPath = function(_, path)
                        assert(path == "/books/book.epub")
                        return options.document or {
                            reader_id = "parent-1",
                            local_path = path,
                            local_format = "epub",
                            is_local_present = true,
                            is_managed = true,
                        }
                    end,
                }
            end,
        }
    end
    package.preload["storage/remote_highlights"] = function()
        return { new = function() return { marker = "repo" } end }
    end
    package.preload["storage/sync_meta"] = function()
        return { new = function() return { marker = "meta" } end }
    end
    package.preload["api/http"] = function()
        return { new = function() return { marker = "http" } end }
    end
    package.preload["api/reader"] = function()
        return {
            new = function(_, args)
                assert(args.http.marker == "http")
                return { marker = "reader" }
            end,
        }
    end
    package.preload["api/readwise"] = function()
        return {
            new = function(_, args)
                assert(args.http.marker == "http")
                return { marker = "readwise" }
            end,
        }
    end
    package.preload["sync/remote_highlight_cache"] = function()
        return {
            new = function(_, args)
                assert(args.reader.marker == "reader")
                assert(args.readwise.marker == "readwise")
                assert(args.repository.marker == "repo")
                assert(args.sync_meta.marker == "meta")
                return {
                    refresh = function()
                        state.cache_calls = state.cache_calls + 1
                        if options.cache_error then
                            return nil, options.cache_error
                        end
                        return {
                            mode = "incremental",
                            pages = 2,
                            records_scanned = 5,
                            duplicate_records_ignored = 1,
                            rows_seen = 2,
                            rows_upserted = 2,
                            deleted_highlight_ids = 1,
                            deleted_parent_ids = 1,
                            deletion_pages = 1,
                            scan_started_at = "start",
                            proposed_query_after = "query",
                            updated_after = "old-query",
                        }
                    end,
                    listForDocument = function(_, id)
                        assert(id == "parent-1")
                        return {
                            all = {
                                { id = "h-1" },
                                { id = "h-2" },
                            },
                            with_text = {
                                {
                                    id = "h-1",
                                    parent_id = "parent-1",
                                    content = "One",
                                    notes = "note",
                                    note_present = true,
                                },
                            },
                            notes = 1,
                        }
                    end,
                }
            end,
        }
    end

    local ok, failure = pcall(function()
        local Worker = require("sync/remote_highlight_import_worker")
        run(Worker, state)
    end)

    for _, name in ipairs(names) do
        package.loaded[name] = loaded[name]
        package.preload[name] = preload[name]
    end
    if not ok then error(failure) end
end

return function()
    withStubs(function(Worker, state)
        local report, err = Worker:run("/books/book.epub")
        assert(err == nil)
        assert(report.reader_document_id == "parent-1")
        assert(report.local_format == "epub")
        assert(#report.remote_highlights == 1)
        assert(report.parent_highlight_records == 2)
        assert(report.highlights_with_notes == 1)
        assert(report.cache_mode == "incremental")
        assert(report.cache_deleted_highlights == 1)
        assert(report.cache_deleted_parents == 1)
        assert(report.cache_deletion_pages == 1)
        assert(report.remote_writes == 0)
        assert(state.cache_calls == 1)
        assert(state.db_closed == 1)
        assert(state.config_closed == 1)
    end)

    withStubs(function(Worker, state)
        local report, err = Worker:run("/books/book.epub")
        assert(err == nil)
        assert(report.local_format == "pdf")
        assert(report.reader_document_id == "parent-1")
        assert(#report.remote_highlights == 1)
        assert(state.cache_calls == 1)
        assert(state.db_closed == 1)
        assert(state.config_closed == 1)
    end, {
        document = {
            reader_id = "parent-1",
            local_path = "/books/book.epub",
            local_format = "pdf",
            is_local_present = true,
            is_managed = true,
        },
    })

    withStubs(function(Worker, state)
        local report, err = Worker:run("/books/book.epub")
        assert(report == nil)
        assert(err.kind == "format")
        assert(state.cache_calls == 0)
        assert(state.db_closed == 1)
        assert(state.config_closed == 1)
    end, {
        document = {
            reader_id = "parent-1",
            local_path = "/books/book.epub",
            local_format = "mobi",
            is_local_present = true,
            is_managed = true,
        },
    })

    withStubs(function(Worker, state)
        local report, err = Worker:run("/books/book.epub")
        assert(report == nil)
        assert(err.kind == "offline")
        assert(state.cache_calls == 1)
        assert(state.db_closed == 1)
        assert(state.config_closed == 1)
    end, {
        cache_error = {
            kind = "offline",
            retryable = true,
            message = "offline",
        },
    })
end
