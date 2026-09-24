-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = {}

local function defaultStagePath()
    return require("datastorage"):getSettingsDir()
        .. "/readwisereader_gate13c_probe.stage"
end

local function defaultSnapshotPath()
    return require("datastorage"):getSettingsDir()
        .. "/readwisereader_gate13c_probe.json"
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

local function writeSnapshot(path, report)
    local JSON = require("json")
    local ok, encoded = pcall(JSON.encode, report)
    if not ok or type(encoded) ~= "string" then return false end
    local file = io.open(path, "w")
    if not file then return false end
    file:write(encoded)
    file:close()
    return true
end

local function readSnapshot(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local raw = file:read("*all")
    file:close()
    if type(raw) ~= "string" or raw == "" then return nil end
    local JSON = require("json")
    local ok, decoded = pcall(JSON.decode, raw)
    if not ok or type(decoded) ~= "table" then return nil end
    return decoded
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
        parent_metadata = "not_run",
        parent_html = "not_run",
        parent_html_bytes = 0,
        match_status = "not_run",
    }
end

local function persist(stage_path, snapshot_path, stage, result)
    result.stage = stage
    writeStage(stage_path, stage)
    writeSnapshot(snapshot_path, result)
end

function Worker:lastStage(stage_path)
    return readStage(stage_path or defaultStagePath())
end

function Worker:lastSnapshot(snapshot_path)
    return readSnapshot(snapshot_path or defaultSnapshotPath())
end

function Worker:run(options)
    options = options or {}
    local stage_path = options.stage_path or defaultStagePath()
    local snapshot_path = options.snapshot_path or defaultSnapshotPath()
    local parent_limit = tonumber(options.parent_max_body_bytes)

    local Constants = require("constants")
    if not parent_limit or parent_limit <= 0 then
        parent_limit = Constants.GATE13_PARENT_PROBE_MAX_BYTES
    end

    writeStage(stage_path, "bootstrap")

    local Config = require("config")
    local DB = require("storage/db")
    local Queue = require("storage/queue")
    local Http = require("api/http")
    local Reader = require("api/reader")
    local Identity = require("sync/annotation_identity")

    local config = Config:new()
    local db

    local ok, report, probe_err = pcall(function()
        db = DB:new()
        local queue = Queue:new{ db = db }
        local rows = queue:listCreateDiagnostics(10)
        local counts = queue:countCreateStatuses()

        local result = {
            stage = "queue_snapshot",
            remote_writes = 0,
            parent_probe_max_bytes = parent_limit,
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
            parent_probe_mode = "bounded_fetch_only",
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
        persist(stage_path, snapshot_path, "queue_snapshot", result)

        local reader = Reader:new{
            http = Http:new(),
            config = config,
        }

        persist(stage_path, snapshot_path, "auth_probe", result)
        local auth_ok, auth_err = reader:validateToken()
        if not auth_ok then
            result.auth_status = auth_err and auth_err.kind or "unknown"
            result.auth_retryable = auth_err and auth_err.retryable == true or false
            persist(stage_path, snapshot_path, "done_auth_failure", result)
            return result
        end
        result.auth_status = "passed"
        persist(stage_path, snapshot_path, "auth_passed", result)

        persist(stage_path, snapshot_path, "marker_scan", result)
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
                persist(stage_path, snapshot_path, "done_marker_scan_failure", result)
                return result
            end
            result.marker_scan_status = "passed"
            result.marker_scan_pages = scan.pages or 0
        else
            result.marker_scan_status = "no_active_items"
        end
        persist(stage_path, snapshot_path, "marker_scan_passed", result)

        for index, entry in ipairs(active) do
            local item = entry.row
            local summary = entry.summary

            persist(
                stage_path,
                snapshot_path,
                "parent_" .. tostring(index) .. "_metadata_fetch",
                result
            )
            local metadata_parent, metadata_err = reader:getDocument(
                item.reader_document_id,
                false,
                false,
                parent_limit
            )
            if not metadata_parent then
                summary.parent_metadata =
                    metadata_err and metadata_err.kind or "unknown"
                summary.parent_html = "not_run"
                persist(
                    stage_path,
                    snapshot_path,
                    "parent_" .. tostring(index) .. "_metadata_failed",
                    result
                )
            else
                summary.parent_metadata = "ok"
                persist(
                    stage_path,
                    snapshot_path,
                    "parent_" .. tostring(index) .. "_metadata_ok",
                    result
                )

                persist(
                    stage_path,
                    snapshot_path,
                    "parent_" .. tostring(index) .. "_html_fetch",
                    result
                )
                local parent, parent_err = reader:getDocument(
                    item.reader_document_id,
                    true,
                    false,
                    parent_limit
                )
                if not parent then
                    summary.parent_html =
                        parent_err and parent_err.kind or "unknown"
                    persist(
                        stage_path,
                        snapshot_path,
                        "parent_" .. tostring(index) .. "_html_failed",
                        result
                    )
                else
                    summary.parent_html = "ok"
                    summary.parent_html_bytes =
                        type(parent.html_content) == "string"
                        and #parent.html_content or 0
                    persist(
                        stage_path,
                        snapshot_path,
                        "parent_" .. tostring(index) .. "_html_ok",
                        result
                    )
                end
            end
        end

        persist(stage_path, snapshot_path, "done_fetch_only", result)
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
Worker._defaultSnapshotPath = defaultSnapshotPath
Worker._writeStage = writeStage
Worker._readStage = readStage
Worker._writeSnapshot = writeSnapshot
Worker._readSnapshot = readSnapshot
Worker._statusCount = statusCount
Worker._summarizeItem = summarizeItem
Worker._persist = persist

return Worker
