-- SPDX-License-Identifier: AGPL-3.0-only

local Cache = require("sync/remote_highlight_cache")

local function newMeta(initial)
    local data = initial or {}
    return {
        data = data,
        get = function(_, key) return data[key] end,
        setMany = function(_, values)
            for key, value in pairs(values) do data[key] = value end
        end,
    }
end

local function baselineCase()
    local calls = { replace = 0, upsert = 0, delete_ids = 0, delete_parents = 0 }
    local meta = newMeta()
    local repository = {
        replaceSnapshot = function(_, rows, seen_at)
            calls.replace = calls.replace + 1
            assert(#rows == 2)
            assert(rows[1].id == "h-1")
            assert(rows[2].id == "h-2")
            assert(seen_at == 1000)
            return #rows
        end,
        upsertMany = function() calls.upsert = calls.upsert + 1 end,
        deleteByRemoteIds = function() calls.delete_ids = calls.delete_ids + 1 end,
        deleteByParents = function() calls.delete_parents = calls.delete_parents + 1 end,
    }
    local cache = Cache:new{
        reader = {
            iterateDocuments = function(_, options, callback)
                assert(options.category == "highlight")
                assert(options.updated_after == nil)
                callback{
                    id = "h-1", parent_id = "p-1", category = "highlight",
                    content = "One", notes = "N1", updated_at = "u1",
                }
                callback{
                    id = "h-2", parent_id = "p-2", category = "highlight",
                    content = "Two", updated_at = "u2",
                }
                callback{
                    id = "not-highlight", parent_id = "p-1", category = "note",
                    content = "Ignore",
                }
                return { pages = 3, unique = 3, duplicates = 1 }
            end,
        },
        readwise = {
            exportUpdated = function(_, options)
                assert(options.updated_after == "1970-01-01T00:11:40Z")
                assert(options.include_deleted == true)
                return {
                    next_page_cursor = nil,
                    results = {
                        {
                            external_id = "p-raced",
                            is_deleted = true,
                            highlights = {
                                {
                                    external_id = "h-raced",
                                    is_deleted = true,
                                },
                            },
                        },
                    },
                }
            end,
        },
        repository = repository,
        sync_meta = meta,
        now = function() return 1000 end,
    }

    local report = assert(cache:refresh())
    assert(report.mode == "historical")
    assert(report.rows_seen == 2 and report.rows_upserted == 2)
    assert(report.deleted_highlight_ids == 1)
    assert(report.deleted_parent_ids == 1)
    assert(report.deletion_pages == 1)
    assert(calls.replace == 1)
    assert(calls.upsert == 0)
    assert(calls.delete_ids == 1)
    assert(calls.delete_parents == 1)
    assert(meta.data[Cache.VERSION_KEY] == Cache.CACHE_VERSION)
    assert(meta.data[Cache.BASELINE_KEY] == "1")
    assert(meta.data[Cache.WATERMARK_KEY] == "1970-01-01T00:16:40Z")
    assert(meta.data[Cache.QUERY_AFTER_KEY] == "1970-01-01T00:11:40Z")
end

local function incrementalDeletionCase()
    local calls = {}
    local meta = newMeta{
        [Cache.VERSION_KEY] = Cache.CACHE_VERSION,
        [Cache.BASELINE_KEY] = "1",
        [Cache.WATERMARK_KEY] = "old-watermark",
        [Cache.QUERY_AFTER_KEY] = "2026-09-25T03:55:00Z",
    }
    local page = 0
    local repository = {
        upsertMany = function(_, rows, seen_at)
            calls.upsert = { rows = rows, seen_at = seen_at }
            return #rows
        end,
        replaceSnapshot = function()
            error("incremental refresh must not replace snapshot")
        end,
        deleteByRemoteIds = function(_, ids)
            calls.delete_ids = ids
            return #ids
        end,
        deleteByParents = function(_, ids)
            calls.delete_parents = ids
            return #ids
        end,
    }
    local cache = Cache:new{
        reader = {
            iterateDocuments = function(_, options, callback)
                assert(options.updated_after == "2026-09-25T03:55:00Z")
                callback{
                    id = "h-updated", parent_id = "p-1", category = "highlight",
                    content = "Updated",
                }
                return { pages = 1, unique = 1, duplicates = 0 }
            end,
        },
        readwise = {
            exportUpdated = function(_, options)
                assert(options.updated_after == "2026-09-25T03:55:00Z")
                assert(options.include_deleted == true)
                page = page + 1
                if page == 1 then
                    assert(options.page_cursor == nil)
                    return {
                        next_page_cursor = "next",
                        results = {
                            {
                                source = "reader",
                                external_id = "p-1",
                                is_deleted = false,
                                highlights = {
                                    { external_id = "h-deleted", is_deleted = true },
                                    { external_id = "h-alive", is_deleted = false },
                                },
                            },
                            {
                                source = "kindle",
                                external_id = "ignore-parent",
                                is_deleted = true,
                                highlights = {
                                    { external_id = "ignore-highlight", is_deleted = true },
                                },
                            },
                        },
                    }
                end
                assert(options.page_cursor == "next")
                return {
                    next_page_cursor = nil,
                    results = {
                        {
                            source = "reader",
                            external_id = "p-deleted",
                            is_deleted = true,
                            highlights = {},
                        },
                        {
                            source = "reader",
                            external_id = "p-1",
                            is_deleted = false,
                            highlights = {
                                -- duplicate tombstone across overlap/pages must dedupe.
                                { external_id = "h-deleted", is_deleted = true },
                            },
                        },
                    },
                }
            end,
        },
        repository = repository,
        sync_meta = meta,
        now = function() return 2000 end,
    }

    local report = assert(cache:refresh())
    assert(report.mode == "incremental")
    assert(report.rows_seen == 1)
    assert(report.deleted_highlight_ids == 2)
    assert(report.deleted_parent_ids == 2)
    assert(report.deletion_pages == 2)
    assert(calls.upsert.seen_at == 2000)
    local deleted_ids = {}
    for _, id in ipairs(calls.delete_ids) do deleted_ids[id] = true end
    assert(deleted_ids["h-deleted"])
    assert(deleted_ids["ignore-highlight"])
    local deleted_parents = {}
    for _, id in ipairs(calls.delete_parents) do deleted_parents[id] = true end
    assert(deleted_parents["p-deleted"])
    assert(deleted_parents["ignore-parent"])
    assert(meta.data[Cache.WATERMARK_KEY] == "1970-01-01T00:33:20Z")
    assert(meta.data[Cache.QUERY_AFTER_KEY] == "1970-01-01T00:28:20Z")
end

local function deletionFailureIsFailClosedCase()
    local mutated = 0
    local meta = newMeta{
        [Cache.VERSION_KEY] = Cache.CACHE_VERSION,
        [Cache.BASELINE_KEY] = "1",
        [Cache.WATERMARK_KEY] = "old-watermark",
        [Cache.QUERY_AFTER_KEY] = "old-query",
    }
    local cache = Cache:new{
        reader = {
            iterateDocuments = function()
                return { pages = 1, unique = 0, duplicates = 0 }
            end,
        },
        readwise = {
            exportUpdated = function()
                return nil, {
                    kind = "offline",
                    retryable = true,
                    message = "offline",
                }
            end,
        },
        repository = {
            upsertMany = function() mutated = mutated + 1 end,
            replaceSnapshot = function() mutated = mutated + 1 end,
            deleteByRemoteIds = function() mutated = mutated + 1 end,
            deleteByParents = function() mutated = mutated + 1 end,
        },
        sync_meta = meta,
        now = function() return 3000 end,
    }

    local report, err = cache:refresh()
    assert(report == nil)
    assert(err.kind == "offline")
    assert(mutated == 0, "failed tombstone verification must not mutate cache")
    assert(meta.data[Cache.WATERMARK_KEY] == "old-watermark")
    assert(meta.data[Cache.QUERY_AFTER_KEY] == "old-query")
end

local function repeatedDeletionCursorFailsCase()
    local meta = newMeta{
        [Cache.VERSION_KEY] = Cache.CACHE_VERSION,
        [Cache.BASELINE_KEY] = "1",
        [Cache.QUERY_AFTER_KEY] = "old-query",
    }
    local cache = Cache:new{
        reader = {
            iterateDocuments = function()
                return { pages = 1, unique = 0, duplicates = 0 }
            end,
        },
        readwise = {
            exportUpdated = function()
                return { next_page_cursor = "loop", results = {} }
            end,
        },
        repository = {
            upsertMany = function() error("must not mutate") end,
            replaceSnapshot = function() error("must not mutate") end,
            deleteByRemoteIds = function() error("must not mutate") end,
            deleteByParents = function() error("must not mutate") end,
        },
        sync_meta = meta,
        now = function() return 4000 end,
    }

    local report, err = cache:refresh()
    assert(report == nil)
    assert(err.kind == "pagination")
end

local function staleCacheVersionForcesReplacementCase()
    local meta = newMeta{
        [Cache.VERSION_KEY] = "old-experimental-cache",
        [Cache.BASELINE_KEY] = "1",
        [Cache.WATERMARK_KEY] = "old-watermark",
        [Cache.QUERY_AFTER_KEY] = "old-query",
    }
    local replaced = 0
    local cache = Cache:new{
        reader = {
            iterateDocuments = function(_, options, callback)
                assert(options.updated_after == nil,
                    "stale cache version must force a full v3 baseline")
                callback{
                    id = "fresh-h", parent_id = "fresh-p", category = "highlight",
                    content = "Fresh",
                }
                return { pages = 1, unique = 1, duplicates = 0 }
            end,
        },
        readwise = {
            exportUpdated = function(_, options)
                assert(options.updated_after == "1970-01-01T01:18:20Z")
                assert(options.include_deleted == true)
                return { next_page_cursor = nil, results = {} }
            end,
        },
        repository = {
            replaceSnapshot = function(_, rows)
                replaced = replaced + 1
                assert(#rows == 1 and rows[1].id == "fresh-h")
                return 1
            end,
            upsertMany = function() error("stale cache must not incrementally upsert") end,
            deleteByRemoteIds = function(_, ids)
                assert(#ids == 0,
                    "stale-cache rebuild should apply only verified overlap tombstones")
                return 0
            end,
            deleteByParents = function(_, ids)
                assert(#ids == 0,
                    "stale-cache rebuild should apply only verified overlap tombstones")
                return 0
            end,
        },
        sync_meta = meta,
        now = function() return 5000 end,
    }

    local report = assert(cache:refresh())
    assert(report.mode == "historical")
    assert(replaced == 1)
    assert(meta.data[Cache.VERSION_KEY] == Cache.CACHE_VERSION)
    assert(meta.data[Cache.BASELINE_KEY] == "1")
end

return function()
    baselineCase()
    incrementalDeletionCase()
    deletionFailureIsFailClosedCase()
    repeatedDeletionCursorFailsCase()
    staleCacheVersionForcesReplacementCase()
end
