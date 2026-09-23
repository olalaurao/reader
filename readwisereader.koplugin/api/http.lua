-- SPDX-License-Identifier: AGPL-3.0-only

local Http = {}
Http.__index = Http

local function headerValue(headers, wanted)
    if type(headers) ~= "table" then
        return nil
    end
    wanted = string.lower(wanted)
    for key, value in pairs(headers) do
        if type(key) == "string" and string.lower(key) == wanted then
            return value
        end
    end
    return nil
end

local function safeUrl(url)
    if type(url) ~= "string" then
        return "<invalid-url>"
    end
    return url:match("^([^?]+)") or url
end

local function networkError(message)
    local text = string.lower(tostring(message or ""))

    if text:find("timeout", 1, true) or text:find("sink timeout", 1, true) then
        return { kind = "timeout", retryable = true, message = "The request timed out." }
    end

    if text:find("certificate", 1, true)
        or text:find("ssl", 1, true)
        or text:find("tls", 1, true)
        or text:find("wantread", 1, true)
    then
        return { kind = "tls", retryable = false, message = "TLS negotiation failed." }
    end

    if text:find("host not found", 1, true)
        or text:find("network is unreachable", 1, true)
        or text:find("no route to host", 1, true)
        or text:find("not connected", 1, true)
        or text:find("connection refused", 1, true)
    then
        return { kind = "offline", retryable = true, message = "Network is unavailable." }
    end

    return { kind = "unknown", retryable = true, message = "The network request failed." }
end

local function statusError(status, headers)
    local err = {
        status = status,
        retryable = false,
        message = "The server returned an unexpected response.",
    }

    if status == 401 or status == 403 then
        err.kind = "auth"
        err.message = "Authentication was rejected."
    elseif status == 408 then
        err.kind = "timeout"
        err.retryable = true
        err.message = "The server timed out the request."
    elseif status == 429 then
        err.kind = "rate_limit"
        err.retryable = true
        err.message = "The server rate limit was reached."
        local retry_after = headerValue(headers, "retry-after")
        if retry_after ~= nil then
            err.retry_after = tonumber(retry_after)
        end
    elseif status and status >= 400 and status < 500 then
        err.kind = "client"
        err.message = "The server rejected the request."
    elseif status and status >= 500 then
        err.kind = "server"
        err.retryable = true
        err.message = "The server reported an error."
    else
        err.kind = "unknown"
    end

    return err
end

function Http:new(deps)
    deps = deps or {}
    return setmetatable({
        http = deps.http or require("socket.http"),
        ltn12 = deps.ltn12 or require("ltn12"),
        socketutil = deps.socketutil or require("socketutil"),
        logger = deps.logger or require("logger"),
    }, self)
end

function Http:request(options)
    options = options or {}
    local method = options.method or "GET"
    local url = assert(options.url, "url is required")
    local sink = {}
    local custom_sink = options.sink
    local max_body_bytes = tonumber(options.max_body_bytes)
    if max_body_bytes and max_body_bytes <= 0 then max_body_bytes = nil end
    local received = 0
    local body_too_large = false
    local sink_failed = false
    local sink_error

    local downstream = custom_sink or self.socketutil.table_sink(sink)
    local response_sink = function(chunk)
        if chunk ~= nil then
            received = received + #chunk
            if max_body_bytes and received > max_body_bytes then
                body_too_large = true
                return nil, "response body exceeded configured limit"
            end
        end

        local ok, err = downstream(chunk)
        if ok == nil or ok == false then
            sink_failed = true
            sink_error = err
            return nil, err
        end
        return ok
    end

    local request = {
        method = method,
        url = url,
        headers = options.headers or {},
        sink = response_sink,
    }

    if options.body ~= nil then
        request.source = self.ltn12.source.string(options.body)
        if request.headers["Content-Length"] == nil and request.headers["content-length"] == nil then
            request.headers["Content-Length"] = tostring(#options.body)
        end
    end

    local block_timeout = self.socketutil.LARGE_BLOCK_TIMEOUT or 10
    local total_timeout = self.socketutil.LARGE_TOTAL_TIMEOUT or 30
    if options.timeout_class == "download" then
        block_timeout = self.socketutil.FILE_BLOCK_TIMEOUT or 15
        total_timeout = self.socketutil.FILE_TOTAL_TIMEOUT or 60
    end

    self.socketutil:set_timeout(block_timeout, total_timeout)

    if self.logger and self.logger.dbg then
        self.logger.dbg("ReadwiseReader: [API] request", method, safeUrl(url))
    end

    local call = { pcall(self.http.request, request) }
    self.socketutil:reset_timeout()

    if body_too_large then
        return nil, {
            kind = "too_large",
            retryable = false,
            message = "The response body exceeded the configured size limit.",
            limit = max_body_bytes,
        }
    end

    if sink_failed then
        return nil, {
            kind = "sink",
            retryable = true,
            message = "The response could not be written safely.",
            detail = sink_error and tostring(sink_error) or nil,
        }
    end

    if not call[1] then
        return nil, {
            kind = "unknown",
            retryable = true,
            message = "The HTTP stack raised an unexpected error.",
        }
    end

    local first, code, headers, status_line = call[2], call[3], call[4], call[5]
    if first == nil or headers == nil then
        return nil, networkError(code or status_line)
    end

    local status = tonumber(code)
    if not status then
        return nil, networkError(code)
    end

    if status >= 200 and status < 300 then
        return {
            status = status,
            headers = headers,
            body = custom_sink and nil or table.concat(sink),
            bytes_received = received,
        }
    end

    return nil, statusError(status, headers)
end

Http._headerValue = headerValue
Http._safeUrl = safeUrl
Http._networkError = networkError
Http._statusError = statusError

return Http
