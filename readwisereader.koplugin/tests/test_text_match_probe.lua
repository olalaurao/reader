-- SPDX-License-Identifier: AGPL-3.0-only

local Probe = require("sync/text_match_probe")

return function()
    local scan_count = 0
    local reader_count = 0
    local probe = Probe:new{
        documents = {
            getByLocalPath = function(_, path)
                assert(path == "/Readwise/a.html")
                return {
                    reader_id = "doc-1",
                    local_path = path,
                    is_managed = true,
                    is_local_present = true,
                }
            end,
        },
        adapter = {
            scan = function(_, path, reader_id)
                scan_count = scan_count + 1
                assert(path == "/Readwise/a.html")
                assert(reader_id == "doc-1")
                return {
                    authoritative = true,
                    annotations = {
                        {
                            local_annotation_id = "ann-new",
                            text = 'She said "hello" - today.',
                        },
                        {
                            local_annotation_id = "ann-old",
                            text = "older text",
                        },
                    },
                }
            end,
        },
        reader = {
            getDocument = function(_, reader_id, with_html, with_raw)
                reader_count = reader_count + 1
                assert(reader_id == "doc-1")
                assert(with_html == true)
                assert(with_raw == false)
                return {
                    html_content = "<p>She said &ldquo;hello&rdquo; — today.</p>",
                }
            end,
        },
        file_exists = function(path)
            return path == "/Readwise/a.html"
        end,
    }

    local report = assert(probe:run("/Readwise/a.html"))
    assert(report.matched == true)
    assert(report.mode == "punctuation")
    assert(report.local_annotation_id == "ann-new")
    assert(report.reader_exact_text == "She said “hello” — today.")
    assert(report.remote_writes == 0)
    assert(scan_count == 1)
    assert(reader_count == 1)

    local ambiguous_probe = Probe:new{
        documents = {
            getByLocalPath = function()
                return {
                    reader_id = "doc-2",
                    local_path = "/Readwise/b.html",
                    is_managed = true,
                    is_local_present = true,
                }
            end,
        },
        adapter = {
            scan = function()
                return {
                    authoritative = true,
                    annotations = {{
                        local_annotation_id = "ann-2",
                        text = "same sentence",
                    }},
                }
            end,
        },
        reader = {
            getDocument = function()
                return {
                    html_content = "<p>same sentence</p><p>same sentence</p>",
                }
            end,
        },
        file_exists = function() return true end,
    }

    local ambiguous = assert(ambiguous_probe:run("/Readwise/b.html"))
    assert(ambiguous.matched == false)
    assert(ambiguous.status == "ambiguous")
    assert(ambiguous.remote_writes == 0)

    local missing_doc = Probe:new{
        documents = { getByLocalPath = function() return nil end },
        adapter = {},
        reader = {},
        file_exists = function() return true end,
    }
    local no_report, missing_err = missing_doc:run("/Readwise/missing.html")
    assert(no_report == nil)
    assert(missing_err.kind == "not_managed")
end
