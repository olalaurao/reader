-- SPDX-License-Identifier: AGPL-3.0-only

local Refresh = require("sync/content_refresh")
local Html = require("content/html")
local TextMatch = require("sync/text_match")
local Constants = require("constants")

local Reconcile = {}
Reconcile.__index = Reconcile

local function defaultFileExists(path)
    return require("libs/libkoreader-lfs").attributes(path, "mode") == "file"
end

local function readFile(path, max_bytes)
    local file = io.open(path, "rb")
    if not file then return nil, "io" end
    local content = file:read(max_bytes + 1)
    file:close()
    if type(content) ~= "string" then return nil, "io" end
    if #content > max_bytes then return nil, "too_large" end
    return content
end

function Reconcile:new(options)
    options = options or {}
    return setmetatable({
        documents = assert(options.documents, "documents repository is required"),
        reader = assert(options.reader, "Reader API is required"),
        file_exists = options.file_exists or defaultFileExists,
        read_file = options.read_file or readFile,
        max_article_checks = options.max_article_checks
            or Constants.CONTENT_REFRESH_RECONCILE_MAX_PER_SYNC,
        local_max_bytes = options.local_max_bytes
            or Constants.GATE15_LOCAL_HTML_PROBE_MAX_BYTES,
        remote_max_bytes = options.remote_max_bytes
            or Constants.GATE15_REMOTE_HTML_PROBE_MAX_BYTES,
    }, self)
end

function Reconcile:run()
    local report = {
        pending_seen = 0,
        article_checked = 0,
        metadata_only_acknowledged = 0,
        changed_retained = 0,
        raw_retained = 0,
        unverified_retained = 0,
        local_missing = 0,
        revision_races = 0,
        remote_errors = 0,
        pending_after = 0,
    }

    local pending = self.documents:listContentRefreshPending()
    report.pending_seen = #pending

    for _, document in ipairs(pending) do
        local is_raw = (document.category == "pdf" or document.category == "epub")
            and document.local_format ~= "html"

        if is_raw then
            report.raw_retained = report.raw_retained + 1
        elseif document.local_format ~= "html" then
            report.unverified_retained = report.unverified_retained + 1
        elseif report.article_checked >= self.max_article_checks then
            report.unverified_retained = report.unverified_retained + 1
        elseif document.is_local_present ~= true
            or type(document.local_path) ~= "string"
            or document.local_path == ""
            or not self.file_exists(document.local_path) then
            report.local_missing = report.local_missing + 1
        else
            report.article_checked = report.article_checked + 1
            local local_html = self.read_file(
                document.local_path,
                self.local_max_bytes
            )
            if not local_html then
                report.unverified_retained = report.unverified_retained + 1
            else
                local remote, remote_err = self.reader:getDocument(
                    document.reader_id,
                    true,
                    false,
                    self.remote_max_bytes
                )
                if not remote then
                    report.remote_errors = report.remote_errors + 1
                    report.unverified_retained =
                        report.unverified_retained + 1
                elseif type(document.content_refresh_remote_updated_at)
                        ~= "string"
                    or document.content_refresh_remote_updated_at == "" then
                    report.unverified_retained =
                        report.unverified_retained + 1
                elseif remote.updated_at
                        ~= document.content_refresh_remote_updated_at then
                    -- A newer Reader revision appeared after the metadata pass.
                    -- Never acknowledge stale evidence; the next Sync's
                    -- metadata scan will persist the newer pending revision.
                    report.revision_races = report.revision_races + 1
                    report.unverified_retained =
                        report.unverified_retained + 1
                elseif type(remote.html_content) ~= "string"
                    or remote.html_content == "" then
                    report.unverified_retained =
                        report.unverified_retained + 1
                else
                    local comparison = Refresh.compareVisible(
                        local_html,
                        remote.html_content,
                        Html,
                        TextMatch
                    )
                    if comparison == "same" then
                        self.documents:clearContentRefreshPending(
                            document.reader_id
                        )
                        report.metadata_only_acknowledged =
                            report.metadata_only_acknowledged + 1
                    elseif comparison == "different" then
                        report.changed_retained =
                            report.changed_retained + 1
                    else
                        report.unverified_retained =
                            report.unverified_retained + 1
                    end
                end
            end
        end
    end

    report.pending_after = self.documents:countContentRefreshPending()
    return report
end

Reconcile._readFile = readFile

return Reconcile
