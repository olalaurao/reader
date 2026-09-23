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

    local saved_bookshelf_repo = package.loaded["lib/bookshelf_book_repository"]
    local light_invalidations, book_invalidations = 0, 0
    package.loaded["lib/bookshelf_book_repository"] = {
        invalidateLightMeta = function()
            light_invalidations = light_invalidations + 1
        end,
        invalidateBookCache = function(reason)
            assert(reason == "ReadwiseReader metadata sync")
            book_invalidations = book_invalidations + 1
        end,
    }
    assert(adapter:refreshExternalMetadataCaches() == true)
    assert(light_invalidations == 1)
    assert(book_invalidations == 1)
    package.loaded["lib/bookshelf_book_repository"] = nil
    assert(adapter:refreshExternalMetadataCaches() == true)
    package.loaded["lib/bookshelf_book_repository"] = saved_bookshelf_repo

    adapter:openDocument("/root/article.html")
    assert(events[3].name == "SetupShowReader")
    assert(opened == "/root/article.html")
end
