-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = {}

local function readFile(path, max_bytes)
    local file, err = io.open(path, "rb")
    if not file then
        return nil, {
            kind = "io",
            retryable = false,
            message = "The local document could not be opened safely.",
            detail = tostring(err or "open failed"),
        }
    end
    local content = file:read(max_bytes + 1)
    file:close()
    if type(content) ~= "string" then
        return nil, {
            kind = "io",
            retryable = false,
            message = "The local document could not be read safely.",
        }
    end
    if #content > max_bytes then
        return nil, {
            kind = "too_large",
            retryable = false,
            message = "The local HTML exceeds the Gate 15 diagnostic cap.",
        }
    end
    return content
end

function Worker:run(options)
    options = options or {}
    local local_path = options.local_path
    local reading_state = options.reading_state or {}

    local Config = require("config")
    local DB = require("storage/db")
    local Documents = require("storage/documents")
    local Http = require("api/http")
    local Reader = require("api/reader")
    local Hash = require("content/hash")
    local Html = require("content/html")
    local TextMatch = require("sync/text_match")
    local Refresh = require("sync/content_refresh")
    local Constants = require("constants")

    local config = Config:new()
    local db

    local ok, result_or_err = pcall(function()
        db = DB:new()
        local documents = Documents:new{ db = db }
        local document = documents:getByLocalPath(local_path)
        if not document or document.is_managed ~= true then
            return nil, {
                kind = "document",
                retryable = false,
                message = "The current document is not managed by Readwise Reader.",
            }
        end

        local report = {
            remote_writes = 0,
            local_writes = 0,
            category = document.category,
            local_format = document.local_format,
            download_strategy = document.download_strategy,
            local_present = document.is_local_present == true,
            db_remote_updated_at = document.remote_updated_at,
            materialized_remote_updated_at =
                document.materialized_remote_updated_at,
            refresh_pending = document.content_refresh_pending == true,
            refresh_remote_updated_at =
                document.content_refresh_remote_updated_at,
            refresh_detected_at = document.content_refresh_detected_at,
            sidecar_present = reading_state.sidecar_present == true,
            percent_finished = reading_state.percent_finished,
            annotation_count = tonumber(reading_state.annotation_count) or 0,
            last_xpointer_present =
                reading_state.last_xpointer_present == true,
            last_page_present =
                reading_state.last_page_present == true,
            partial_md5_checksum_present =
                reading_state.partial_md5_checksum_present == true,
            has_reading_state = reading_state.has_reading_state == true,
            remote_probe = "not_run",
            comparison = "not_run",
            local_bytes = 0,
            remote_html_bytes = 0,
            replacement_allowed = Refresh.isReplacementAllowed(),
        }

        local reader = Reader:new{
            http = Http:new(),
            config = config,
        }

        local wants_html = document.local_format == "html"
        local remote, remote_err = reader:getDocument(
            document.reader_id,
            wants_html,
            false,
            wants_html and Constants.GATE15_REMOTE_HTML_PROBE_MAX_BYTES
                or nil
        )
        if not remote then
            report.remote_probe = remote_err and remote_err.kind or "unknown"
            report.comparison = "unavailable"
            report.decision = Refresh.decide{
                local_present = report.local_present,
                category = report.category,
                local_format = report.local_format,
                pending = report.refresh_pending,
                remote_revision_changed = true,
                comparison = report.comparison,
                has_reading_state = report.has_reading_state,
            }
            return report
        end

        report.remote_probe = "passed"
        report.remote_updated_at = remote.updated_at
        if document.materialized_remote_updated_at == nil then
            report.remote_revision_state = "materialized_baseline_unknown"
        elseif remote.updated_at ~= document.materialized_remote_updated_at then
            report.remote_revision_state = "newer_than_materialized"
        else
            report.remote_revision_state = "same_as_materialized"
        end

        local remote_revision_changed =
            document.materialized_remote_updated_at ~= nil
            and remote.updated_at ~= document.materialized_remote_updated_at

        if wants_html then
            local local_html, local_err = readFile(
                local_path,
                Constants.GATE15_LOCAL_HTML_PROBE_MAX_BYTES
            )
            if not local_html then
                report.local_probe_error =
                    local_err and local_err.kind or "unknown"
                report.comparison = "unavailable"
            elseif type(remote.html_content) ~= "string"
                or remote.html_content == "" then
                report.comparison = "remote_html_unavailable"
            else
                report.local_bytes = #local_html
                report.remote_html_bytes = #remote.html_content
                local local_visible = Refresh.normalizeVisible(
                    local_html,
                    Html,
                    TextMatch
                )
                local remote_visible = Refresh.normalizeVisible(
                    remote.html_content,
                    Html,
                    TextMatch
                )
                if local_visible and remote_visible then
                    report.comparison =
                        Hash.sha256(local_visible) == Hash.sha256(remote_visible)
                        and "same" or "different"
                else
                    report.comparison = "unavailable"
                end
            end
        else
            report.comparison = "not_attempted_raw"
        end

        report.decision = Refresh.decide{
            local_present = report.local_present,
            category = report.category,
            local_format = report.local_format,
            pending = report.refresh_pending,
            remote_revision_changed = remote_revision_changed,
            comparison = report.comparison,
            has_reading_state = report.has_reading_state,
        }

        return report
    end)

    if db then pcall(function() db:close() end) end
    pcall(function() config:close() end)

    if not ok then
        return nil, {
            kind = "worker",
            retryable = true,
            message = "Gate 15 content-refresh diagnostic failed safely.",
        }
    end
    return result_or_err
end

Worker._readFile = readFile

return Worker
