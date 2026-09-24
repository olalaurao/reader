-- SPDX-License-Identifier: AGPL-3.0-only

local Status = {}
Status.__index = Status

local KNOWN = {
    reading = true,
    abandoned = true,
    complete = true,
}

local function defaultDependencies()
    return {
        DocSettings = require("docsettings"),
        BookList = require("ui/widget/booklist"),
    }
end

function Status:new(options)
    options = options or {}
    return setmetatable({
        deps = options.deps or defaultDependencies(),
    }, self)
end

function Status:scan(local_path)
    if type(local_path) ~= "string" or local_path == "" then
        return nil, {
            kind = "path",
            retryable = false,
            message = "Current document path is unavailable.",
        }
    end

    local open_ok, settings = pcall(
        self.deps.DocSettings.open,
        self.deps.DocSettings,
        local_path
    )
    if not open_ok or not settings then
        return nil, {
            kind = "sidecar",
            retryable = true,
            message = "KOReader document settings could not be opened safely.",
        }
    end

    local result = {
        local_path = local_path,
        sidecar_present = settings.source_candidate ~= nil,
        sidecar_source = settings.source_candidate,
        sidecar_status = nil,
        sidecar_modified = nil,
        percent_finished = nil,
        booklist_status = nil,
        annotation_count = 0,
        last_xpointer_present = false,
        last_page_present = false,
        partial_md5_checksum_present = false,
        has_progress = false,
        has_annotations = false,
        has_reading_state = false,
        status_known = false,
        finished = false,
    }

    if settings.source_candidate then
        local summary_ok, summary = pcall(
            settings.readSetting,
            settings,
            "summary"
        )
        if not summary_ok then
            return nil, {
                kind = "sidecar",
                retryable = true,
                message = "KOReader summary could not be read safely.",
            }
        end
        if type(summary) == "table" then
            result.sidecar_status = summary.status
            result.sidecar_modified = summary.modified
            result.status_known = KNOWN[summary.status] == true
            result.finished = summary.status == "complete"
        end

        local percent_ok, percent = pcall(
            settings.readSetting,
            settings,
            "percent_finished"
        )
        if percent_ok then
            result.percent_finished = tonumber(percent)
        end

        local annotations_ok, annotations = pcall(
            settings.readSetting,
            settings,
            "annotations"
        )
        if annotations_ok and type(annotations) == "table" then
            result.annotation_count = #annotations
            result.has_annotations = #annotations > 0
        end

        local xpointer_ok, xpointer = pcall(
            settings.readSetting,
            settings,
            "last_xpointer"
        )
        if xpointer_ok then
            result.last_xpointer_present =
                type(xpointer) == "string" and xpointer ~= ""
        end

        local page_ok, last_page = pcall(
            settings.readSetting,
            settings,
            "last_page"
        )
        if page_ok then
            result.last_page_present = last_page ~= nil
        end

        local md5_ok, partial_md5 = pcall(
            settings.readSetting,
            settings,
            "partial_md5_checksum"
        )
        if md5_ok then
            result.partial_md5_checksum_present =
                type(partial_md5) == "string" and partial_md5 ~= ""
        end

        result.has_progress =
            (type(result.percent_finished) == "number"
                and result.percent_finished > 0)
            or result.last_xpointer_present
            or result.last_page_present
        result.has_reading_state =
            result.has_progress or result.has_annotations
    end

    if self.deps.BookList and type(self.deps.BookList.getBookStatus) == "function" then
        local book_ok, book_status = pcall(
            self.deps.BookList.getBookStatus,
            local_path
        )
        if book_ok then result.booklist_status = book_status end
    end

    return result
end

function Status.isCanonicalFinished(status)
    return status == "complete"
end

Status._KNOWN = KNOWN

return Status
