-- SPDX-License-Identifier: AGPL-3.0-only

local Reader = require("api/reader")

local function fakeJsonDecode(value)
    return function()
        if value == "__throw__" then
            error("bad json")
        end
        return value
    end
end

return function()
    do
        local captured
        local reader = Reader:new{
            config = {
                getAccessToken = function()
                    return "abc123"
                end,
            },
            http = {
                request = function(_, options)
                    captured = options
                    return { status = 204, headers = {}, body = "" }
                end,
            },
        }

        local ok, err = reader:validateToken()
        assert(ok == true)
        assert(err == nil)
        assert(captured.method == "GET")
        assert(captured.headers.Authorization == "Token abc123")
    end

    do
        local called = false
        local reader = Reader:new{
            config = {
                getAccessToken = function()
                    return nil
                end,
            },
            http = {
                request = function()
                    called = true
                end,
            },
        }

        local ok, err = reader:validateToken()
        assert(ok == nil)
        assert(err.kind == "auth")
        assert(called == false)
    end

    do
        local reader = Reader:new{
            config = {
                getAccessToken = function()
                    return "abc123"
                end,
            },
            http = {
                request = function()
                    return nil, { kind = "auth", retryable = false }
                end,
            },
        }

        local ok, err = reader:validateToken()
        assert(ok == nil)
        assert(err.kind == "auth")
    end

    do
        local captured
        local reader = Reader:new{
            config = {
                getAccessToken = function()
                    return "reader-token"
                end,
            },
            http = {
                request = function(_, options)
                    captured = options
                    return {
                        status = 200,
                        headers = {},
                        body = "{}",
                    }
                end,
            },
            json_decode = fakeJsonDecode({
                results = {
                    {
                        id = "doc-1",
                        title = "Título ç",
                        author = "Author",
                        category = "article",
                        location = "new",
                        tags = {
                            ["tag-key-2"] = { name = "deep work" },
                            ["tag-key-1"] = { name = "research" },
                        },
                        parent_id = nil,
                        updated_at = "2026-09-22T10:00:00Z",
                        saved_at = "2026-09-20T10:00:00Z",
                    },
                    {
                        id = "child-1",
                        title = "Highlight",
                        category = "highlight",
                        parent_id = "doc-1",
                    },
                },
                nextPageCursor = "cursor/2 + next",
            }),
        }

        local page, err = reader:listDocuments{
            updated_after = "2026-09-22T10:00:00Z",
            location = "new",
            category = "article",
            tags = { "koreader", "deep work" },
            page_cursor = "cursor/1",
        }

        assert(err == nil)
        assert(#page.results == 2)
        assert(page.results[1].id == "doc-1")
        assert(page.results[1].title == "Título ç")
        assert(page.results[1].tags[1] == "deep work")
        assert(page.results[1].tags[2] == "research")
        assert(Reader._normalizeTags({ "z", "a", "z" })[1] == "a")
        assert(Reader._normalizeTags({
            alpha = { name = "Alpha" },
            beta = { name = "Beta" },
        })[2] == "Beta")
        assert(page.results[2].parent_id == "doc-1")
        assert(page.next_page_cursor == "cursor/2 + next")
        assert(captured.method == "GET")
        assert(captured.headers.Authorization == "Token reader-token")
        assert(captured.url:find("limit=100", 1, true))
        assert(captured.url:find("withHtmlContent=false", 1, true))
        assert(captured.url:find("withRawSourceUrl=false", 1, true))
        assert(captured.url:find("updatedAfter=2026%-09%-22T10%%3A00%%3A00Z"))
        assert(captured.url:find("pageCursor=cursor%%2F1"))
        assert(captured.url:find("tag=koreader", 1, true))
        assert(captured.url:find("tag=deep%%20work"))
    end

    do
        local reader = Reader:new{
            config = { getAccessToken = function() return "token" end },
            http = {
                request = function()
                    return { status = 200, headers = {}, body = "not-json" }
                end,
            },
            json_decode = fakeJsonDecode("__throw__"),
        }
        local page, err = reader:listDocuments()
        assert(page == nil)
        assert(err.kind == "decode")
    end

    do
        local reader = Reader:new{
            config = { getAccessToken = function() return "token" end },
            http = {
                request = function()
                    return { status = 200, headers = {}, body = "{}" }
                end,
            },
            json_decode = fakeJsonDecode({ nextPageCursor = nil }),
        }
        local page, err = reader:listDocuments()
        assert(page == nil)
        assert(err.kind == "decode")
    end

    do
        local reader = Reader:new{
            config = { getAccessToken = function() return "token" end },
            http = {
                request = function()
                    return { status = 200, headers = {}, body = "{}" }
                end,
            },
            json_decode = fakeJsonDecode({
                results = {},
                nextPageCursor = 42,
            }),
        }
        local page, err = reader:listDocuments()
        assert(page == nil)
        assert(err.kind == "decode")
    end

    do
        local reader = Reader:new{
            config = { getAccessToken = function() return "token" end },
            http = {
                request = function()
                    return { status = 200, headers = {}, body = "{}" }
                end,
            },
            json_decode = fakeJsonDecode({
                results = {
                    { title = "missing id" },
                },
            }),
        }
        local page, err = reader:listDocuments()
        assert(page == nil)
        assert(err.kind == "decode")
        assert(err.index == 1)
    end

    do
        local reader = Reader:new{
            config = { getAccessToken = function() return "token" end },
            http = {
                request = function()
                    return nil, {
                        kind = "rate_limit",
                        retryable = true,
                        retry_after = 12,
                    }
                end,
            },
            json_decode = fakeJsonDecode({}),
        }
        local page, err = reader:listDocuments()
        assert(page == nil)
        assert(err.kind == "rate_limit")
        assert(err.retry_after == 12)
    end

    do
        local url, err = Reader._buildListUrl{ limit = 101 }
        assert(url == nil)
        assert(err.kind == "client")
    end
    do
        local captured
        local reader = Reader:new{
            config = { getAccessToken = function() return "test-token" end },
            http = {
                request = function(_, request)
                    captured = request
                    return { status = 200, headers = {}, body = "doc-body" }
                end,
            },
            json_decode = function()
                return {
                    results = {
                        {
                            id = "doc/with space",
                            category = "article",
                            html_content = "<p>Olá</p>",
                        },
                    },
                }
            end,
            list_min_interval = 0,
        }

        local document, err = reader:getDocument("doc/with space", true, false)
        assert(err == nil)
        assert(document.id == "doc/with space")
        assert(document.html_content == "<p>Olá</p>")
        assert(captured.url:find("id=doc%2Fwith%20space", 1, true))
        assert(captured.url:find("withHtmlContent=true", 1, true))
        assert(captured.url:find("withRawSourceUrl=false", 1, true))
    end

    do
        local reader = Reader:new{
            config = { getAccessToken = function() return "test-token" end },
            http = {
                request = function()
                    return { status = 200, headers = {}, body = "empty" }
                end,
            },
            json_decode = function()
                return { results = {} }
            end,
            list_min_interval = 0,
        }
        local document, err = reader:getDocument("missing", true, false)
        assert(document == nil)
        assert(err.kind == "not_found")
    end


    do
        local calls = 0
        local reader = Reader:new{
            config = { getAccessToken = function() return "test-token" end },
            http = {
                request = function(_, request)
                    calls = calls + 1
                    if request.url:find("/api/v3/tags/", 1, true) then
                        return { status = 200, headers = {}, body = "tags" }
                    end
                    assert(request.url:find("tag=gate4a%-tag%-test"))
                    return { status = 200, headers = {}, body = "docs" }
                end,
            },
            json_decode = function(body)
                if body == "tags" then
                    return {
                        results = {
                            { key = "other", name = "Other" },
                            { key = "gate4a-tag-test", name = "gate4a-tag-test" },
                        },
                        nextPageCursor = nil,
                    }
                end
                return {
                    results = {
                        {
                            id = "doc-1",
                            category = "article",
                            location = "new",
                            parent_id = nil,
                            tags = {
                                ["gate4a-tag-test"] = { name = "gate4a-tag-test" },
                            },
                        },
                    },
                    nextPageCursor = nil,
                }
            end,
            list_min_interval = 0,
        }

        local report, err = reader:diagnoseTag("gate4a-tag-test")
        assert(err == nil)
        assert(report.tag_found == true)
        assert(report.tag_key == "gate4a-tag-test")
        assert(report.document_pages == 1)
        assert(#report.documents == 1)
        assert(report.documents[1].id == "doc-1")
        assert(report.documents[1].tags[1] == "gate4a-tag-test")
        assert(calls == 2)
    end

    do
        local reader = Reader:new{
            config = { getAccessToken = function() return "test-token" end },
            http = {
                request = function()
                    return { status = 200, headers = {}, body = "tags" }
                end,
            },
            json_decode = function()
                return {
                    results = {
                        { key = "other", name = "Other" },
                    },
                    nextPageCursor = nil,
                }
            end,
            list_min_interval = 0,
        }
        local report, err = reader:diagnoseTag("gate4a-tag-test")
        assert(err == nil)
        assert(report.tag_found == false)
        assert(#report.documents == 0)
    end

end
