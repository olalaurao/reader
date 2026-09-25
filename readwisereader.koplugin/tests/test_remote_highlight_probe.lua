-- SPDX-License-Identifier: AGPL-3.0-only

local Probe = require("sync/remote_highlight_probe")

return function()
    local probe = Probe:new{
        documents = {
            getByLocalPath = function(_, path)
                assert(path == "/books/book.epub")
                return {
                    reader_id = "parent-1",
                    local_path = path,
                    local_format = "epub",
                    is_local_present = true,
                    is_managed = true,
                }
            end,
        },
        file_exists = function(path) return path == "/books/book.epub" end,
        reader = {
            iterateDocuments = function(_, options, callback)
                assert(options.category == "highlight")
                assert(options.limit == 100)
                assert(options.with_html_content == false)
                assert(options.with_raw_source_url == false)
                callback{
                    id = "h2", parent_id = "parent-1", content = "Second",
                    notes = "note", highlight_offset = 20, created_at = "2026-01-02",
                }
                callback{
                    id = "foreign", parent_id = "parent-2", content = "Ignore me",
                }
                callback{
                    id = "empty", parent_id = "parent-1", content = "",
                }
                callback{
                    id = "h1", parent_id = "parent-1", content = "First",
                    highlight_offset = 10, created_at = "2026-01-01",
                }
                return { pages = 2, unique = 4, duplicates = 1 }
            end,
        },
    }

    local report, err = probe:run("/books/book.epub")
    assert(err == nil)
    assert(report.reader_document_id == "parent-1")
    assert(report.local_format == "epub")
    assert(report.parent_highlight_records == 3)
    assert(report.highlights_with_text == 2)
    assert(report.highlights_with_notes == 1)
    assert(report.pages == 2)
    assert(report.records_scanned == 4)
    assert(report.duplicate_records_ignored == 1)
    assert(report.remote_highlights[1].id == "h1")
    assert(report.remote_highlights[2].id == "h2")
    assert(report.remote_highlights[2].note_present == true)
    assert(report.remote_highlights[2].notes == "note")
    assert(report.remote_highlights[2].parent_id == "parent-1")
    assert(report.remote_writes == 0 and report.local_writes == 0)

    local bad = Probe:new{
        documents = {
            getByLocalPath = function()
                return {
                    reader_id = "pdf-parent",
                    local_path = "/books/book.pdf",
                    local_format = "pdf",
                    is_local_present = true,
                    is_managed = true,
                }
            end,
        },
        file_exists = function() return true end,
        reader = { iterateDocuments = function() error("must not scan PDF in Gate 17A") end },
    }
    local no_report, format_err = bad:run("/books/book.pdf")
    assert(no_report == nil)
    assert(format_err.kind == "format")
end
