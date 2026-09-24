-- SPDX-License-Identifier: AGPL-3.0-only

local Status = require("koreader/status")

local function deps(data, source_candidate, book_status)
    return {
        DocSettings = {
            open = function(_, path)
                assert(path == "/book.html")
                return {
                    source_candidate = source_candidate,
                    readSetting = function(_, key)
                        return data and data[key] or nil
                    end,
                }
            end,
        },
        BookList = {
            getBookStatus = function(path)
                assert(path == "/book.html")
                return book_status
            end,
        },
    }
end

return function()
    do
        local status = Status:new{
            deps = deps({
                summary = {
                    status = "complete",
                    modified = "2026-09-24",
                },
                percent_finished = 0.73,
                annotations = {
                    { page = "/body/DocFragment[1]" },
                    { page = "/body/DocFragment[2]" },
                },
                last_xpointer = "/body/DocFragment[3]",
                partial_md5_checksum = "abc123",
            }, "/book.sdr/metadata.html.lua", "complete"),
        }
        local report = assert(status:scan("/book.html"))
        assert(report.sidecar_present == true)
        assert(report.sidecar_status == "complete")
        assert(report.sidecar_modified == "2026-09-24")
        assert(report.percent_finished == 0.73)
        assert(report.booklist_status == "complete")
        assert(report.annotation_count == 2)
        assert(report.has_annotations == true)
        assert(report.last_xpointer_present == true)
        assert(report.last_page_present == false)
        assert(report.partial_md5_checksum_present == true)
        assert(report.has_progress == true)
        assert(report.has_reading_state == true)
        assert(report.status_known == true)
        assert(report.finished == true)
        assert(Status.isCanonicalFinished("complete") == true)
        assert(Status.isCanonicalFinished("reading") == false)
    end

    do
        local status = Status:new{
            deps = deps({
                summary = { status = "reading" },
                percent_finished = 0,
                last_page = 4,
            }, "/book.sdr/metadata.html.lua", "reading"),
        }
        local report = assert(status:scan("/book.html"))
        assert(report.finished == false)
        assert(report.status_known == true)
        assert(report.sidecar_status == "reading")
        assert(report.last_page_present == true)
        assert(report.has_progress == true)
        assert(report.has_reading_state == true)
    end

    do
        local status = Status:new{
            deps = deps({
                summary = { status = "something-new" },
            }, "/book.sdr/metadata.html.lua", "reading"),
        }
        local report = assert(status:scan("/book.html"))
        assert(report.finished == false)
        assert(report.status_known == false)
    end

    do
        local status = Status:new{
            deps = deps({}, nil, "new"),
        }
        local report = assert(status:scan("/book.html"))
        assert(report.sidecar_present == false)
        assert(report.sidecar_status == nil)
        assert(report.finished == false)
    end

    do
        local status = Status:new{
            deps = {
                DocSettings = {
                    open = function()
                        error("broken sidecar")
                    end,
                },
                BookList = {},
            },
        }
        local report, err = status:scan("/book.html")
        assert(report == nil)
        assert(err.kind == "sidecar")
    end
end
