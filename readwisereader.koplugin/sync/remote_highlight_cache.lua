-- SPDX-License-Identifier: AGPL-3.0-only

local Constants = require("constants")

local Cache = {}
Cache.__index = Cache

local BASELINE_KEY = "remote_highlight_cache_baseline"
local WATERMARK_KEY = "remote_highlight_cache_watermark"
local QUERY_AFTER_KEY = "remote_highlight_cache_query_after"

local function formatTime(epoch)
    return os.date("!%Y-%m-%dT%H:%M:%SZ", epoch)
end

local function appendUnique(out, seen, value)
    if type(value) == "string" and value ~= "" and not seen[value] then
        seen[value] = true
        out[#out + 1] = value
    end
end

function Cache:new(options)
    options = options or {}
    return setmetatable({
        reader = assert(options.reader, "Reader API is required"),
        readwise = assert(options.readwise, "Readwise API is required"),
        repository = assert(options.repository, "remote highlight repository is required"),
        sync_meta = assert(options.sync_meta, "sync_meta is required"),
        now = options.now or os.time,
    }, self)
end

function Cache:_deletedSince(updated_after)
    if type(updated_after) ~= "string" or updated_after == "" then
        return {
            highlight_ids = {},
            parent_ids = {},
            pages = 0,
        }
    end

    local highlight_ids, parent_ids = {}, {}
    local seen_highlights, seen_parents = {}, {}
    local cursor
    local seen_cursors = {}
    local pages = 0

    while true do
        if cursor and seen_cursors[cursor] then
            return nil, {
                kind = "pagination",
                retryable = false,
                message = "Readwise export returned a repeated page cursor.",
            }
        end
        if cursor then seen_cursors[cursor] = true end

        local page, export_err = self.readwise:exportUpdated{
            updated_after = updated_after,
            page_cursor = cursor,
            include_deleted = true,
        }
        if not page then return nil, export_err end
        pages = pages + 1

        for _, book in ipairs(page.results or {}) do
            if type(book) == "table" then
                -- Do not depend on the export source label. Reader/Readwise
                -- representations have historically varied there, while the
                -- durable cross-API contract is the exact external_id. Delete
                -- operations below can only affect cache rows whose exact
                -- Reader parent/child IDs match these tombstones.
                if book.is_deleted == true then
                    appendUnique(parent_ids, seen_parents, book.external_id)
                end
                for _, highlight in ipairs(book.highlights or {}) do
                    if type(highlight) == "table"
                        and highlight.is_deleted == true then
                        appendUnique(
                            highlight_ids,
                            seen_highlights,
                            highlight.external_id
                        )
                    end
                end
            end
        end

        local next_cursor = page.next_page_cursor
        if next_cursor == nil then break end
        if type(next_cursor) ~= "string" or next_cursor == "" then
            return nil, {
                kind = "decode",
                retryable = false,
                message = "Readwise export returned an invalid page cursor.",
            }
        end
        cursor = next_cursor
    end

    return {
        highlight_ids = highlight_ids,
        parent_ids = parent_ids,
        pages = pages,
    }
end

function Cache:refresh()
    local baseline = self.sync_meta:get(BASELINE_KEY) == "1"
    local query_after = baseline and self.sync_meta:get(QUERY_AFTER_KEY) or nil
    if baseline and (type(query_after) ~= "string" or query_after == "") then
        baseline = false
        query_after = nil
    end

    local started_epoch = self.now()
    local remote_rows = {}
    local scan, scan_err = self.reader:iterateDocuments({
        category = "highlight",
        updated_after = query_after,
        limit = 100,
        with_html_content = false,
        with_raw_source_url = false,
    }, function(remote)
        if type(remote.id) == "string" and remote.id ~= ""
            and type(remote.parent_id) == "string"
            and remote.parent_id ~= ""
            and remote.category == "highlight" then
            remote_rows[#remote_rows + 1] = {
                id = remote.id,
                parent_id = remote.parent_id,
                content = remote.content,
                notes = remote.notes,
                created_at = remote.created_at,
                updated_at = remote.updated_at,
                highlight_offset = remote.highlight_offset,
                highlight_location = remote.highlight_location,
            }
        end
    end)
    if not scan then return nil, scan_err end

    -- Reader v3 LIST has no documented deletion tombstone. Once the initial
    -- full snapshot exists, use Readwise v2 EXPORT includeDeleted=true with
    -- the same overlap lower bound before advancing the cache watermark.
    -- The v2 highlight external_id is the Reader highlight child ID, and a
    -- Reader-sourced book external_id is its Reader parent document ID.
    local deleted = {
        highlight_ids = {},
        parent_ids = {},
        pages = 0,
    }
    if baseline then
        local deletion_err
        deleted, deletion_err = self:_deletedSince(query_after)
        if not deleted then return nil, deletion_err end
    end

    local written
    if baseline then
        written = self.repository:upsertMany(remote_rows, started_epoch)
        self.repository:deleteByRemoteIds(deleted.highlight_ids)
        self.repository:deleteByParents(deleted.parent_ids)
    else
        -- A successful historical v3 scan is an authoritative extant snapshot.
        -- Replace atomically so stale rows from an older/partial baseline cannot
        -- survive into the first import run.
        written = self.repository:replaceSnapshot(remote_rows, started_epoch)
    end

    local started_at = formatTime(started_epoch)
    local proposed_query_after = formatTime(math.max(
        0,
        started_epoch - (Constants.REMOTE_HIGHLIGHT_IMPORT_OVERLAP_SECONDS or 300)
    ))
    self.sync_meta:setMany({
        [BASELINE_KEY] = "1",
        [WATERMARK_KEY] = started_at,
        [QUERY_AFTER_KEY] = proposed_query_after,
    })

    return {
        mode = baseline and "incremental" or "historical",
        updated_after = query_after,
        scan_started_at = started_at,
        proposed_query_after = proposed_query_after,
        rows_seen = #remote_rows,
        rows_upserted = written or 0,
        deleted_highlight_ids = #deleted.highlight_ids,
        deleted_parent_ids = #deleted.parent_ids,
        deletion_pages = deleted.pages or 0,
        pages = scan.pages or 0,
        records_scanned = scan.unique or 0,
        duplicate_records_ignored = scan.duplicates or 0,
    }
end

function Cache:listForDocument(reader_document_id)
    local all = self.repository:listByParent(reader_document_id)
    local with_text = {}
    local notes = 0
    for _, remote in ipairs(all) do
        if type(remote.content) == "string" and remote.content ~= "" then
            if remote.note_present then notes = notes + 1 end
            with_text[#with_text + 1] = remote
        end
    end
    return {
        all = all,
        with_text = with_text,
        notes = notes,
    }
end

Cache.BASELINE_KEY = BASELINE_KEY
Cache.WATERMARK_KEY = WATERMARK_KEY
Cache.QUERY_AFTER_KEY = QUERY_AFTER_KEY

return Cache
