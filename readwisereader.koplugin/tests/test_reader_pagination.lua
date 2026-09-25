-- SPDX-License-Identifier: AGPL-3.0-only

local Reader = require("api/reader")

local function sequenceReader(pages, options)
    options = options or {}
    local call_index = 0
    local captured = {}
    local reader = Reader:new{
        config = {
            getAccessToken = function()
                return "test-token"
            end,
        },
        http = {
            request = function(_, options)
                call_index = call_index + 1
                captured[call_index] = options
                local page = pages[call_index]
                if page and page.error then
                    return nil, page.error
                end
                return {
                    status = 200,
                    headers = {},
                    body = tostring(call_index),
                }
            end,
        },
        json_decode = function(body)
            return pages[tonumber(body)]
        end,
        clock = options.clock,
        sleep = options.sleep,
        list_min_interval = options.list_min_interval or 0,
    }
    return reader, captured
end

return function()
    do
        local reader, captured = sequenceReader({
            {
                results = {
                    { id = "a", location = "new" },
                    { id = "b", location = "later" },
                },
                nextPageCursor = "cursor-2",
            },
            {
                results = {
                    { id = "b", location = "later" },
                    { id = "c", location = "archive" },
                },
            },
        })
        local ids = {}
        local report, err = reader:iterateDocuments({}, function(document)
            ids[#ids + 1] = document.id
        end)
        assert(err == nil)
        assert(report.pages == 2)
        assert(report.received == 4)
        assert(report.unique == 3)
        assert(report.duplicates == 1)
        assert(table.concat(ids, ",") == "a,b,c")
        assert(captured[1].url:find("limit=100", 1, true))
        assert(captured[2].url:find("pageCursor=cursor%-2"))
    end

    do
        local reader = sequenceReader({
            {
                results = { { id = "a" } },
                nextPageCursor = "same",
            },
            {
                results = { { id = "b" } },
                nextPageCursor = "same",
            },
        })
        local report, err = reader:iterateDocuments({}, function() end)
        assert(report == nil)
        assert(err.kind == "pagination")
        assert(err.cursor == "same")
        assert(err.report.pages == 2)
    end

    do
        local reader = sequenceReader({
            {
                results = {},
                nextPageCursor = "impossible-next",
            },
        })
        local report, err = reader:iterateDocuments({}, function() end)
        assert(report == nil)
        assert(err.kind == "pagination")
        assert(err.report.pages == 1)
    end

    do
        local reader = sequenceReader({
            {
                results = {
                    { id = "a" },
                    { id = "b" },
                },
            },
        })
        local seen = 0
        local report, err = reader:iterateDocuments({
            is_cancelled = function()
                return seen >= 1
            end,
        }, function()
            seen = seen + 1
        end)
        assert(report == nil)
        assert(err.kind == "cancelled")
        assert(err.report.unique == 1)
    end

    do
        local now = 0
        local sleeps = {}
        local call_index = 0
        local responses = {
            {
                results = { { id = "a" } },
                nextPageCursor = "cursor-2",
            },
            {
                error = {
                    kind = "rate_limit",
                    retryable = true,
                    retry_after = 7,
                },
            },
            {
                results = { { id = "b" } },
            },
        }
        local reader = Reader:new{
            config = { getAccessToken = function() return "test-token" end },
            http = {
                request = function()
                    call_index = call_index + 1
                    local response = responses[call_index]
                    if response.error then
                        return nil, response.error
                    end
                    return { status = 200, headers = {}, body = tostring(call_index) }
                end,
            },
            json_decode = function(body)
                return responses[tonumber(body)]
            end,
            clock = function() return now end,
            sleep = function(seconds)
                sleeps[#sleeps + 1] = seconds
                now = now + seconds
            end,
            list_min_interval = 0,
        }

        local report, err = reader:iterateDocuments({}, function() end)
        assert(err == nil)
        assert(report.pages == 2)
        assert(report.unique == 2)
        assert(call_index == 3)
        local slept_total = 0
        for _, seconds in ipairs(sleeps) do
            slept_total = slept_total + seconds
        end
        assert(slept_total >= 7)
    end

    do
        local now = 0
        local call_index = 0
        local reader = Reader:new{
            config = { getAccessToken = function() return "test-token" end },
            http = {
                request = function()
                    call_index = call_index + 1
                    return nil, {
                        kind = "rate_limit",
                        retryable = true,
                        retry_after = 1,
                    }
                end,
            },
            json_decode = function() return {} end,
            clock = function() return now end,
            sleep = function(seconds) now = now + seconds end,
            list_min_interval = 0,
        }

        local report, err = reader:iterateDocuments({}, function() end)
        assert(report == nil)
        assert(err.kind == "rate_limit")
        assert(err.retry_after == 1)
        assert(err.page == 1)
        assert(err.report.pages == 0)
        assert(call_index == 3)
    end


    do
        -- Gate 16 / malformed remote item: a bad document must fail closed
        -- with a bounded decode error instead of reaching the callback.
        local reader = sequenceReader({
            {
                results = {
                    { id = "valid" },
                    { title = "missing id" },
                },
            },
        })
        local callbacks = 0
        local report, err = reader:iterateDocuments({}, function()
            callbacks = callbacks + 1
        end)
        assert(report == nil)
        assert(err.kind == "decode")
        assert(err.index == 2)
        assert(err.page == 1)
        assert(callbacks == 0)
    end


    do
        local reader = sequenceReader({
            {
                results = { { id = "a" } },
            },
        })
        local report, err = reader:iterateDocuments({}, function()
            error("synthetic callback error")
        end)
        assert(report == nil)
        assert(err.kind == "callback")
        assert(err.report.pages == 1)
    end

    do
        local now = 0
        local sleeps = {}
        local request_times = {}
        local pages = {}
        for i = 1, 21 do
            pages[i] = {
                results = { { id = "doc-" .. tostring(i) } },
                nextPageCursor = i < 21 and ("cursor-" .. tostring(i + 1)) or nil,
            }
        end

        local call_index = 0
        local reader = Reader:new{
            config = { getAccessToken = function() return "test-token" end },
            http = {
                request = function()
                    call_index = call_index + 1
                    request_times[call_index] = now
                    return { status = 200, headers = {}, body = tostring(call_index) }
                end,
            },
            json_decode = function(body)
                return pages[tonumber(body)]
            end,
            clock = function()
                return now
            end,
            sleep = function(seconds)
                sleeps[#sleeps + 1] = seconds
                now = now + seconds
            end,
            list_min_interval = 3.1,
        }

        local report, err = reader:iterateDocuments({}, function() end)
        assert(err == nil)
        assert(report.pages == 21)
        assert(report.unique == 21)
        assert(#request_times == 21)
        assert(request_times[1] == 0)
        assert(request_times[21] >= 62)
        for i = 2, #request_times do
            assert(request_times[i] - request_times[i - 1] >= 3.099)
        end
        assert(#sleeps > 0)
    end


    do
        -- Gate 16 / large-library deterministic stress: pagination must stay
        -- bounded to one page plus ID/cursor sets rather than accumulating
        -- document payloads. Exercise a corpus materially larger than the
        -- current real library without Reader/network access.
        local page_count = 120
        local per_page = 100
        local now = 0
        local requests = 0
        local reader = Reader:new{
            config = { getAccessToken = function() return "test-token" end },
            http = {
                request = function()
                    requests = requests + 1
                    return { status = 200, headers = {}, body = tostring(requests) }
                end,
            },
            json_decode = function(body)
                local page_no = tonumber(body)
                local results = {}
                for item = 1, per_page do
                    results[item] = {
                        id = string.format("stress-%03d-%03d", page_no, item),
                    }
                end
                return {
                    results = results,
                    nextPageCursor = page_no < page_count
                        and ("stress-cursor-" .. tostring(page_no + 1))
                        or nil,
                }
            end,
            clock = function() return now end,
            sleep = function(seconds) now = now + seconds end,
            list_min_interval = 0,
        }

        local callbacks = 0
        local report, err = reader:iterateDocuments({}, function()
            callbacks = callbacks + 1
        end)
        assert(err == nil)
        assert(report.pages == page_count)
        assert(report.received == page_count * per_page)
        assert(report.unique == page_count * per_page)
        assert(report.duplicates == 0)
        assert(callbacks == page_count * per_page)
        assert(requests == page_count)
    end


    do
        local now = 0
        local cancelled = false
        local requests = 0
        local reader = Reader:new{
            config = { getAccessToken = function() return "test-token" end },
            http = {
                request = function()
                    requests = requests + 1
                    return { status = 200, headers = {}, body = tostring(requests) }
                end,
            },
            json_decode = function(body)
                if tonumber(body) == 1 then
                    return {
                        results = { { id = "a" } },
                        nextPageCursor = "cursor-2",
                    }
                end
                return { results = { { id = "b" } } }
            end,
            clock = function()
                return now
            end,
            sleep = function(seconds)
                now = now + seconds
                cancelled = true
            end,
            list_min_interval = 3.1,
        }

        local report, err = reader:iterateDocuments({
            is_cancelled = function()
                return cancelled
            end,
        }, function() end)
        assert(report == nil)
        assert(err.kind == "cancelled")
        assert(requests == 1)
    end
end
