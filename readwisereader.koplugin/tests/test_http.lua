-- SPDX-License-Identifier: AGPL-3.0-only

local Http = require("api/http")

local function newSocketUtil()
    local s = {
        LARGE_BLOCK_TIMEOUT = 10,
        LARGE_TOTAL_TIMEOUT = 30,
        FILE_BLOCK_TIMEOUT = 15,
        FILE_TOTAL_TIMEOUT = 60,
        set_count = 0,
        reset_count = 0,
    }

    function s.table_sink(target)
        return function(chunk)
            if chunk then table.insert(target, chunk) end
            return 1
        end
    end

    function s:set_timeout()
        self.set_count = self.set_count + 1
    end

    function s:reset_timeout()
        self.reset_count = self.reset_count + 1
    end

    return s
end

local fakeLtn12 = {
    source = {
        string = function(value)
            return function()
                local result = value
                value = nil
                return result
            end
        end,
    },
}

return function()
    do
        local socketutil = newSocketUtil()
        local logged = {}
        local captured
        local http = Http:new{
            http = {
                request = function(request)
                    captured = request
                    return 1, 204, {}, "HTTP/1.1 204 No Content"
                end,
            },
            ltn12 = fakeLtn12,
            socketutil = socketutil,
            logger = {
                dbg = function(...)
                    for i = 1, select("#", ...) do
                        table.insert(logged, tostring(select(i, ...)))
                    end
                end,
            },
        }

        local response, err = http:request{
            method = "GET",
            url = "https://readwise.io/api/v2/auth/?secret=query",
            headers = { Authorization = "Token abc123" },
        }

        assert(err == nil)
        assert(response.status == 204)
        assert(captured.headers.Authorization == "Token abc123")
        assert(socketutil.set_count == 1)
        assert(socketutil.reset_count == 1)
        local log_text = table.concat(logged, " ")
        assert(log_text:find("abc123", 1, true) == nil)
        assert(log_text:find("secret=query", 1, true) == nil)
    end

    do
        local socketutil = newSocketUtil()
        local http = Http:new{
            http = {
                request = function()
                    return 1, 429, { ["Retry-After"] = "7" }, "HTTP/1.1 429 Too Many Requests"
                end,
            },
            ltn12 = fakeLtn12,
            socketutil = socketutil,
            logger = { dbg = function() end },
        }

        local response, err = http:request{ url = "https://readwise.io/" }
        assert(response == nil)
        assert(err.kind == "rate_limit")
        assert(err.retryable == true)
        assert(err.retry_after == 7)
    end

    do
        local socketutil = newSocketUtil()
        local http = Http:new{
            http = {
                request = function()
                    return nil, "timeout", nil, nil
                end,
            },
            ltn12 = fakeLtn12,
            socketutil = socketutil,
            logger = { dbg = function() end },
        }

        local response, err = http:request{ url = "https://readwise.io/" }
        assert(response == nil)
        assert(err.kind == "timeout")
        assert(err.retryable == true)
        assert(socketutil.reset_count == 1)
    end

    do
        local socketutil = newSocketUtil()
        local http = Http:new{
            http = {
                request = function(request)
                    assert(request.sink("1234") == 1)
                    local sink_ok = request.sink("5678")
                    assert(sink_ok == nil)
                    return nil, "response body exceeded configured limit", nil, nil
                end,
            },
            ltn12 = fakeLtn12,
            socketutil = socketutil,
            logger = { dbg = function() end },
        }

        local response, err = http:request{
            url = "https://example.com/large-image.jpg?signature=secret",
            timeout_class = "download",
            max_body_bytes = 6,
        }
        assert(response == nil)
        assert(err.kind == "too_large")
        assert(err.retryable == false)
        assert(err.limit == 6)
        assert(socketutil.reset_count == 1)
    end

    do
        local socketutil = newSocketUtil()
        local chunks = {}
        local http = Http:new{
            http = {
                request = function(request)
                    assert(request.sink("abc") == 1)
                    assert(request.sink("def") == 1)
                    assert(request.sink(nil) == 1)
                    return 1, 200, { ["Content-Type"] = "application/pdf" }, "HTTP/1.1 200 OK"
                end,
            },
            ltn12 = fakeLtn12,
            socketutil = socketutil,
            logger = { dbg = function() end },
        }

        local response, err = http:request{
            url = "https://signed.example/file.pdf?secret=redacted",
            timeout_class = "download",
            max_body_bytes = 10,
            sink = function(chunk)
                if chunk then chunks[#chunks + 1] = chunk end
                return 1
            end,
        }
        assert(err == nil)
        assert(response.status == 200)
        assert(response.body == nil)
        assert(response.bytes_received == 6)
        assert(table.concat(chunks) == "abcdef")
    end

    do
        local socketutil = newSocketUtil()
        local http = Http:new{
            http = {
                request = function(request)
                    local ok = request.sink("abc")
                    assert(ok == nil)
                    return nil, "disk full", nil, nil
                end,
            },
            ltn12 = fakeLtn12,
            socketutil = socketutil,
            logger = { dbg = function() end },
        }
        local response, err = http:request{
            url = "https://signed.example/file.pdf?secret=redacted",
            sink = function()
                return nil, "no space left on device"
            end,
        }
        assert(response == nil)
        assert(err.kind == "sink")
        assert(err.retryable == true)
        assert(err.detail:find("no space left", 1, true))
    end

    do
        local socketutil = newSocketUtil()
        local http = Http:new{
            http = {
                request = function()
                    error("boom")
                end,
            },
            ltn12 = fakeLtn12,
            socketutil = socketutil,
            logger = { dbg = function() end },
        }

        local response, err = http:request{ url = "https://readwise.io/" }
        assert(response == nil)
        assert(err.kind == "unknown")
        assert(socketutil.reset_count == 1)
    end



    do
        -- Gate 16 / log redaction: query strings can contain signed URLs or
        -- other private parameters. Logging must keep only the endpoint path.
        local logged = {}
        local http = Http:new{
            http = {
                request = function()
                    return 1, 200, {}, "HTTP/1.1 200 OK"
                end,
            },
            ltn12 = fakeLtn12,
            socketutil = newSocketUtil(),
            logger = {
                dbg = function(...)
                    local parts = {...}
                    logged[#logged + 1] = table.concat(parts, " ")
                end,
            },
        }
        local response, err = http:request{
            method = "GET",
            url = "https://example.com/file?token=super-secret&X-Amz-Signature=signed-private",
        }
        assert(err == nil)
        assert(response.status == 200)
        local line = table.concat(logged, "\n")
        assert(line:find("https://example.com/file", 1, true))
        assert(not line:find("super-secret", 1, true))
        assert(not line:find("signed-private", 1, true))
        assert(not line:find("X-Amz-Signature", 1, true))
    end


    do
        -- Gate 16 / huge response: enforce the byte ceiling even when a
        -- single incoming chunk alone exceeds it; the downstream sink must
        -- never receive that oversized chunk.
        local socketutil = newSocketUtil()
        local downstream_calls = 0
        local http = Http:new{
            http = {
                request = function(request)
                    local ok = request.sink(string.rep("x", 1025))
                    assert(ok == nil)
                    return nil, "response body exceeded configured limit", nil, nil
                end,
            },
            ltn12 = fakeLtn12,
            socketutil = socketutil,
            logger = { dbg = function() end },
        }
        local response, err = http:request{
            url = "https://example.com/huge",
            max_body_bytes = 1024,
            sink = function()
                downstream_calls = downstream_calls + 1
                return 1
            end,
        }
        assert(response == nil)
        assert(err.kind == "too_large")
        assert(err.limit == 1024)
        assert(downstream_calls == 0)
    end


    assert(Http._statusError(401, {}).kind == "auth")
    assert(Http._statusError(403, {}).kind == "auth")
    assert(Http._statusError(500, {}).retryable == true)
    assert(Http._networkError("host not found").kind == "offline")
    assert(Http._networkError("certificate verify failed").kind == "tls")
end
