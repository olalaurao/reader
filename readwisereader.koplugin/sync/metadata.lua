-- SPDX-License-Identifier: AGPL-3.0-only

local Metadata = {}
Metadata.__index = Metadata

local function increment(bucket, key)
    key = key or "unknown"
    bucket[key] = (bucket[key] or 0) + 1
end

function Metadata:new(options)
    options = options or {}
    return setmetatable({
        reader = assert(options.reader, "reader is required"),
    }, self)
end

function Metadata:scan(options)
    options = options or {}
    local report = {
        top_level_documents = 0,
        child_records = 0,
        by_location = {},
        by_category = {},
    }

    local pagination, err = self.reader:iterateDocuments({
        limit = 100,
        with_html_content = false,
        with_raw_source_url = false,
        is_cancelled = options.is_cancelled,
    }, function(document)
        local is_child = type(document.parent_id) == "string" and document.parent_id ~= ""
        if is_child then
            report.child_records = report.child_records + 1
            return
        end

        report.top_level_documents = report.top_level_documents + 1
        increment(report.by_location, document.location)
        increment(report.by_category, document.category)
    end)

    if not pagination then
        return nil, err
    end

    report.pages = pagination.pages
    report.api_records = pagination.received
    report.unique_records = pagination.unique
    report.duplicates_ignored = pagination.duplicates
    return report
end

Metadata._increment = increment

return Metadata
