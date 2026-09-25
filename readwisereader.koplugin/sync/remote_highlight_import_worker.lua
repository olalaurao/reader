-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = {}

local function domainError(kind, message)
    return { kind = kind, retryable = false, message = message }
end

function Worker:run(local_path)
    local Config = require("config")
    local DB = require("storage/db")
    local Documents = require("storage/documents")
    local RemoteHighlights = require("storage/remote_highlights")
    local SyncMeta = require("storage/sync_meta")
    local Http = require("api/http")
    local Reader = require("api/reader")
    local Readwise = require("api/readwise")
    local Cache = require("sync/remote_highlight_cache")

    local config = Config:new()
    local db
    local ok, report, domain_err = pcall(function()
        db = DB:new()
        local documents = Documents:new{ db = db }
        local document = documents:getByLocalPath(local_path)
        if not document or document.is_managed ~= true then
            return nil, domainError(
                "not_managed",
                "The current document is not managed by Readwise Reader."
            )
        end
        if document.is_local_present ~= true then
            return nil, domainError(
                "local_missing",
                "The managed Reader document is not recorded as local."
            )
        end
        if document.local_format ~= "epub"
            and document.local_format ~= "html" then
            return nil, domainError(
                "format",
                "Reader highlight import currently supports EPUB/HTML only."
            )
        end

        local http = Http:new()
        local cache = Cache:new{
            reader = Reader:new{
                http = http,
                config = config,
            },
            readwise = Readwise:new{
                http = http,
                config = config,
            },
            repository = RemoteHighlights:new{ db = db },
            sync_meta = SyncMeta:new{ db = db },
        }
        local refresh, refresh_err = cache:refresh()
        if not refresh then return nil, refresh_err end

        local current = cache:listForDocument(document.reader_id)
        return {
            reader_document_id = document.reader_id,
            local_format = document.local_format,
            remote_highlights = current.with_text,
            parent_highlight_records = #current.all,
            highlights_with_text = #current.with_text,
            highlights_with_notes = current.notes,
            pages = refresh.pages,
            records_scanned = refresh.records_scanned,
            duplicate_records_ignored = refresh.duplicate_records_ignored,
            cache_mode = refresh.mode,
            cache_rows_seen = refresh.rows_seen,
            cache_rows_upserted = refresh.rows_upserted,
            cache_deleted_highlights = refresh.deleted_highlight_ids or 0,
            cache_deleted_parents = refresh.deleted_parent_ids or 0,
            cache_deletion_pages = refresh.deletion_pages or 0,
            cache_scan_started_at = refresh.scan_started_at,
            cache_query_after = refresh.proposed_query_after,
            updated_after = refresh.updated_after,
            remote_writes = 0,
        }
    end)

    if db then pcall(function() db:close() end) end
    pcall(function() config:close() end)

    if not ok then
        return nil, {
            kind = "worker",
            retryable = true,
            message = "Reader-highlight cache refresh failed safely.",
        }
    end
    return report, domain_err
end

return Worker
