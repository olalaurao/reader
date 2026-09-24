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
