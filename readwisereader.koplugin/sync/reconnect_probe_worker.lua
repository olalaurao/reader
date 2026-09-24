-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = {}

local function defaultStagePath()
    return require("datastorage"):getSettingsDir()
        .. "/readwisereader_gate13c_probe.stage"
end

local function writeStage(path, stage)
    local file = io.open(path, "w")
    if not file then return false end
    file:write(tostring(stage or "unknown"))
    file:close()
    return true
end

local function readStage(path)
    local file = io.open(path, "r")
    if not file then return "unavailable" end
    local value = file:read("*line")
    file:close()
    if type(value) ~= "string" or value == "" then
        return "unavailable"
    end
    return value
end

local function statusCount(counts, key)
    return tonumber(counts and counts[key]) or 0
end

local function summarizeItem(item)
    return {
        status = tostring(item.status or "unknown"),
        attempts = tonumber(item.attempts) or 0,
        error_kind = item.last_error_kind and tostring(item.last_error_kind) or nil,
        has_remote_id = type(item.reader_highlight_document_id) == "string"
            and item.reader_highlight_document_id ~= "",
        marker_matches = 0,
        parent_read = "not_run",
        match_status = "not_run",
    }
end

function Worker:lastStage(stage_path)
    return readStage(stage_path or defaultStagePath())
end

function Worker:run(options)
    options = options or {}
    local stage_path = options.stage_path or defaultStagePath()
    writeStage(stage_path, "bootstrap")

    local Config = require("config")
    local DB = require("storage/db")
    local Queue = require("storage/queue")
    local Http = require("api/http")
    local Reader = require("api/reader")
    local TextMatch = require("sync/text_match")
    local Identity = require("sync/annotation_identity")

    local config = Config:new()
    local db

    local ok, report, probe_err = pcall(function()
        writeStage(stage_path, "queue_snapshot")
        db = DB:new()
        local queue = Queue:new{ db = db }
        local rows = queue:listCreateDiagnostics(10)
        local counts = queue:countCreateStatuses()

        local result = {
            stage = "queue_snapshot",
            remote_writes = 0,
            queue_pending = statusCount(counts, "pending"),
            queue_retry_wait = statusCount(counts, "retry_wait"),
            queue_in_flight = statusCount(counts, "in_flight"),
            queue_blocked = statusCount(counts, "blocked"),
            queue_succeeded = statusCount(counts, "succeeded"),
            items = {},
            auth_status = "not_run",
            marker_scan_status = "not_run",
            marker_scan_pages = 0,
            marker_matches_total = 0,
        }

        local active = {}
        local markers = {}
        for index, item in ipairs(rows) do
            local summary = summarizeItem(item)
            result.items[index] = summary
            if item.status ~= "succeeded" then
                active[#active + 1] = {
                    row = item,
                    summary = summary,
                }
                if type(item.local_annotation_id) == "string"
                    and item.local_annotation_id ~= "" then
                    markers[Identity.markerFor(item.local_annotation_id)] = summary
                end
            end
        end

        writeStage(stage_path, "auth_probe")
        local reader = Reader:new{
            http = Http:new(),
            config = config,
        }
        local auth_ok, auth_err = reader:validateToken()
        if not auth_ok then
            result.stage = "auth_probe"
            result.auth_status = auth_err and auth_err.kind or "unknown"
            result.auth_retryable = auth_err and auth_err.retryable == true or false
            writeStage(stage_path, "done_auth_failure")
            return result
        end
        result.auth_status = "passed"

        writeStage(stage_path, "marker_scan")
        if next(markers) ~= nil then
            local scan, scan_err = reader:iterateDocuments({
                category = "highlight",
                limit = 100,
                with_html_content = false,
                with_raw_source_url = false,
            }, function(remote)
                local summary = markers[remote.source]
                if summary then
                    summary.marker_matches = summary.marker_matches + 1
                    result.marker_matches_total = result.marker_matches_total + 1
                end
            end)
            if not scan then
                result.marker_scan_status =
                    scan_err and scan_err.kind or "unknown"
                result.stage = "marker_scan"
                writeStage(stage_path, "done_marker_scan_failure")
                return result
            end
            result.marker_scan_status = "passed"
            result.marker_scan_pages = scan.pages or 0
        else
            result.marker_scan_status = "no_active_items"
        end

        writeStage(stage_path, "parent_reads")
        local JSON = require("json")
        for _, entry in ipairs(active) do
            local item = entry.row
            local summary = entry.summary
            local decode_ok, payload = pcall(JSON.decode, item.payload_json)
            if not decode_ok or type(payload) ~= "table" then
                summary.parent_read = "payload_decode_failed"
                summary.match_status = "not_run"
            else
                local parent, parent_err = reader:getDocument(
                    item.reader_document_id,
                    true,
                    false
                )
                if not parent then
                    summary.parent_read =
                        parent_err and parent_err.kind or "unknown"
                    summary.match_status = "not_run"
                else
                    summary.parent_read = "ok"
                    local local_text = payload.local_text or payload.content
                    if type(local_text) ~= "string" or local_text == "" then
                        summary.match_status = "missing_local_text"
                    else
                        local exact, match = TextMatch.findExactSubstring(
                            parent.html_content,
                            local_text
                        )
                        if exact then
                            summary.match_status = "matched"
                            summary.match_mode = match and match.mode or "unknown"
                        else
                            summary.match_status =
                                match and match.status or "unmatched"
                        end
                    end
                end
            end
        end

        result.stage = "done"
        writeStage(stage_path, "done")
        return result
    end)

    if db then pcall(function() db:close() end) end
    pcall(function() config:close() end)

    if not ok then
        return nil, {
            kind = "worker",
            stage = readStage(stage_path),
            retryable = true,
            message = "Gate 13 reconnect diagnostic failed safely.",
        }
    end
    return report, probe_err
end

Worker._defaultStagePath = defaultStagePath
Worker._writeStage = writeStage
Worker._readStage = readStage
Worker._statusCount = statusCount
Worker._summarizeItem = summarizeItem

return Worker
