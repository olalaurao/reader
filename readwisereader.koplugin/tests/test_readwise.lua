-- SPDX-License-Identifier: AGPL-3.0-only

local Readwise = require("api/readwise")

local function fakeConfig()
    return { getAccessToken = function() return "token" end }
end

return function()
    do
        local captured
        local api = Readwise:new{
            config = fakeConfig(),
            http = {
                request = function(_, request)
                    captured = request
                    return { status = 200, headers = {}, body = "list" }
                end,
            },
            json_decode = function(body)
                assert(body == "list")
                return {
                    count = 1,
                    next = nil,
                    previous = nil,
                    results = {
                        {
                            id = 123,
                            text = "Exact passage",
                            note = "Initial note",
                            color = "yellow",
                            updated = "2026-09-23T15:00:00Z",
                            book_id = 456,
                            external_id = "reader-highlight-1",
                            tags = { { id = 1, name = "gate8" } },
                        },
                    },
                }
            end,
        }
        local page, err = api:listHighlights{
            page_size = 1000,
            updated_after = "2026-09-23T14:59:00Z",
        }
        assert(err == nil)
        assert(page.count == 1)
        assert(page.results[1].id == 123)
        assert(page.results[1].external_id == "reader-highlight-1")
        assert(captured.method == "GET")
        assert(captured.url:find("page_size=1000", 1, true))
        assert(captured.url:find("updated__gt=2026%-09%-23T14%%3A59%%3A00Z"))
        assert(captured.headers.Authorization == "Token token")
    end

    do
        local calls = {}
        local api = Readwise:new{
            config = fakeConfig(),
            http = {
                request = function(_, request)
                    calls[#calls + 1] = request
                    if request.method == "DELETE" then
                        return { status = 204, headers = {}, body = "" }
                    end
                    return { status = 200, headers = {}, body = "detail" }
                end,
            },
            json_encode = function(payload)
                assert(payload.note == "v2 updated")
                assert(payload.color == "green")
                return "patch-json"
            end,
            json_decode = function()
                return {
                    id = 123,
                    text = "Exact passage",
                    note = "v2 updated",
                    color = "green",
                    external_id = "reader-highlight-1",
                    book_id = 456,
                }
            end,
        }

        local detail = assert(api:getHighlight(123))
        assert(detail.id == 123)
        assert(calls[1].url:find("/api/v2/highlights/123/", 1, true))

        local updated = assert(api:updateHighlight(123, {
            note = "v2 updated",
            color = "green",
        }))
        assert(updated.note == "v2 updated")
        assert(updated.color == "green")
        assert(calls[2].method == "PATCH")
        assert(calls[2].body == "patch-json")

        assert(api:deleteHighlight(123) == true)
        assert(calls[3].method == "DELETE")
    end

    do
        local captured
        local api = Readwise:new{
            config = fakeConfig(),
            http = {
                request = function(_, request)
                    captured = request
                    return { status = 200, headers = {}, body = "export" }
                end,
            },
            json_decode = function()
                return {
                    count = 1,
                    nextPageCursor = "cursor-2",
                    results = {
                        {
                            user_book_id = 456,
                            source = "reader",
                            external_id = "reader-parent-1",
                            highlights = {
                                {
                                    id = 123,
                                    external_id = "reader-highlight-1",
                                },
                            },
                        },
                    },
                }
            end,
        }
        local page = assert(api:exportUpdated{
            updated_after = "2026-09-23T15:00:00Z",
            include_deleted = true,
        })
        assert(page.next_page_cursor == "cursor-2")
        assert(page.results[1].external_id == "reader-parent-1")
        assert(captured.url:find("includeDeleted=true", 1, true))
        assert(captured.url:find("updatedAfter=2026%-09%-23T15%%3A00%%3A00Z"))
    end

    do
        local api = Readwise:new{
            config = fakeConfig(),
            http = { request = function() error("must not request") end },
        }
        local page, err = api:listHighlights{ page_size = 1001 }
        assert(page == nil)
        assert(err.kind == "client")
    end
end
