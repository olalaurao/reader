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
end
