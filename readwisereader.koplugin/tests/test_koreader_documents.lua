-- SPDX-License-Identifier: AGPL-3.0-only

local Documents = require("koreader/documents")

return function()
    local saved = {}
    local events = {}
    local opened

    local settings = {
        saveSetting = function(_, key, value)
            saved[key] = value
        end,
        flushCustomMetadata = function(_, path)
            saved.path = path
            return true
        end,
    }

    local adapter = Documents:new{
        deps = {
            DocSettings = {
                openSettingsFile = function()
                    return settings
                end,
            },
            Event = {
                new = function(_, name, arg)
                    return { name = name, arg = arg }
                end,
            },
            UIManager = {
                broadcastEvent = function(_, event)
                    events[#events + 1] = event
                end,
            },
            ReaderUI = {
                showReader = function(_, path)
                    opened = path
                end,
            },
        },
    }

    local ok, err = adapter:writeMetadata("/root/article.html", {
        title = "Title",
        author = "Author",
        summary = "Summary",
        site_name = "Site",
        tags = { "research", "deep work", "research", "line\nbreak", "  spaced  ", 42 },
    })
    assert(ok == true)
    assert(err == nil)
    assert(saved.path == "/root/article.html")
    assert(saved.doc_props.title == "Title")
    assert(saved.doc_props.authors == "Author")
    assert(saved.doc_props.description == "Summary")
    assert(saved.doc_props.series == "Site")
    assert(saved.doc_props.keywords == "research\ndeep work\nline break\nspaced")
    assert(saved.custom_props.title == "Title")
    assert(saved.custom_props.keywords == saved.doc_props.keywords)
    assert(Documents._tagsToKeywords({}) == "")
    assert(Documents._tagsToKeywords(nil) == nil)
    assert(events[1].name == "InvalidateMetadataCache")
    assert(events[1].arg == "/root/article.html")
    assert(events[2].name == "BookMetadataChanged")

    adapter:openDocument("/root/article.html")
    assert(events[3].name == "SetupShowReader")
    assert(opened == "/root/article.html")
end
