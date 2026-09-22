-- SPDX-License-Identifier: AGPL-3.0-only

local Metadata = require("sync/metadata")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

return function()
    do
        local captured_options
        local scanner = Metadata:new{
            reader = {
                iterateDocuments = function(_, options, callback)
                    captured_options = options
                    callback({ id = "doc-1", location = "new", category = "article" })
                    callback({ id = "child-1", parent_id = "doc-1", location = "new", category = "highlight" })
                    callback({ id = "doc-2", location = "later", category = "pdf" })
                    callback({ id = "doc-3", location = nil, category = nil })
                    return {
                        pages = 3,
                        received = 5,
                        unique = 4,
                        duplicates = 1,
                    }
                end,
            },
        }

        local report, err = scanner:scan()
        assert(err == nil)
        assertEqual(report.top_level_documents, 3)
        assertEqual(report.child_records, 1)
        assertEqual(report.pages, 3)
        assertEqual(report.api_records, 5)
        assertEqual(report.unique_records, 4)
        assertEqual(report.duplicates_ignored, 1)
        assertEqual(report.by_location.new, 1)
        assertEqual(report.by_location.later, 1)
        assertEqual(report.by_location.unknown, 1)
        assertEqual(report.by_category.article, 1)
        assertEqual(report.by_category.pdf, 1)
        assertEqual(report.by_category.unknown, 1)
        assertEqual(captured_options.limit, 100)
        assertEqual(captured_options.with_html_content, false)
        assertEqual(captured_options.with_raw_source_url, false)
    end

    do
        local scanner = Metadata:new{
            reader = {
                iterateDocuments = function()
                    return nil, {
                        kind = "rate_limit",
                        retryable = true,
                        retry_after = 30,
                    }
                end,
            },
        }
        local report, err = scanner:scan()
        assert(report == nil)
        assertEqual(err.kind, "rate_limit")
        assertEqual(err.retry_after, 30)
    end
end
