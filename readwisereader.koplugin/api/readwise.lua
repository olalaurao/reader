-- SPDX-License-Identifier: AGPL-3.0-only

local Constants = require("constants")

local Readwise = {}
Readwise.__index = Readwise

local function percentEncode(value)
    return (tostring(value):gsub("([^A-Za-z0-9%-._~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function defaultJsonDecode(body)
    local JSON = require("json")
    return JSON.decode(body, JSON.decode.simple)
end

local function defaultJsonEncode(value)
    return require("json").encode(value)
end

local function queryUrl(base, values)
    local keys = {}
    for key, value in pairs(values or {}) do
        if value ~= nil then keys[#keys + 1] = key end
    end
    table.sort(keys)
    if #keys == 0 then return base end
    local parts = {}
    for _, key in ipairs(keys) do
        local value = values[key]
        parts[#parts + 1] = percentEncode(key) .. "=" .. percentEncode(value)
    end
    return base .. "?" .. table.concat(parts, "&")
end

local function normalizeHighlight(raw)
    if type(raw) ~= "table" or tonumber(raw.id) == nil then
        return nil
    end
    return {
        id = tonumber(raw.id),
        text = raw.text,
        note = raw.note,
        location = raw.location,
        location_type = raw.location_type,
        highlighted_at = raw.highlighted_at,
        created_at = raw.created_at,
        updated = raw.updated or raw.updated_at,
        url = raw.url,
        color = raw.color,
        book_id = tonumber(raw.book_id),
        external_id = raw.external_id,
        tags = raw.tags,
        end_location = raw.end_location,
        readwise_url = raw.readwise_url,
        is_deleted = raw.is_deleted == true,
    }
end

function Readwise:new(options)
    options = options or {}
    return setmetatable({
        http = assert(options.http, "http is required"),
        config = assert(options.config, "config is required"),
        json_decode = options.json_decode,
        json_encode = options.json_encode,
    }, self)
end

function Readwise:_getToken()
    local token = self.config:getAccessToken()
    if token then return token end
    return nil, {
        kind = "auth",
        retryable = false,
        message = "Access token is not configured.",
    }
end

function Readwise:_decodeJson(body)
    local decode = self.json_decode or defaultJsonDecode
    local ok, result = pcall(decode, body)
    if not ok or type(result) ~= "table" then
        return nil, {
            kind = "decode",
            retryable = false,
            message = "Readwise returned malformed JSON.",
        }
    end
    return result
end

function Readwise:_encodeJson(value)
    local encode = self.json_encode or defaultJsonEncode
    local ok, result = pcall(encode, value)
    if not ok or type(result) ~= "string" then
        return nil, {
            kind = "encode",
            retryable = false,
            message = "Readwise request payload could not be encoded.",
        }
    end
    return result
end

function Readwise:_request(method, url, payload)
    local token, token_err = self:_getToken()
    if not token then return nil, token_err end

    local body
    if payload ~= nil then
        local encode_err
        body, encode_err = self:_encodeJson(payload)
        if not body then return nil, encode_err end
    end

    local headers = {
        ["Accept"] = "application/json",
        ["Authorization"] = "Token " .. token,
    }
    if body ~= nil then headers["Content-Type"] = "application/json" end

    return self.http:request{
        method = method,
        url = url,
        headers = headers,
        body = body,
        timeout_class = "api",
    }
end

function Readwise:listHighlights(options)
    options = options or {}
    local page_size = tonumber(options.page_size) or 100
    if page_size < 1 or page_size > 1000 or page_size ~= math.floor(page_size) then
        return nil, {
            kind = "client",
            retryable = false,
            message = "Readwise Highlight LIST page_size must be an integer from 1 to 1000.",
        }
    end

    local url = queryUrl(Constants.READWISE_HIGHLIGHTS_URL, {
        page_size = page_size,
        page = options.page,
        book_id = options.book_id,
        updated__gt = options.updated_after,
        updated__lt = options.updated_before,
        highlighted_at__gt = options.highlighted_after,
        highlighted_at__lt = options.highlighted_before,
    })
    local response, err = self:_request("GET", url)
    if not response then return nil, err end

    local payload, decode_err = self:_decodeJson(response.body)
    if not payload then return nil, decode_err end
    if type(payload.results) ~= "table" then
        return nil, {
            kind = "decode",
            retryable = false,
            message = "Readwise Highlight LIST response did not contain results.",
        }
    end

    local results = {}
    for _, raw in ipairs(payload.results) do
        local item = normalizeHighlight(raw)
        if item then results[#results + 1] = item end
    end
    return {
        count = tonumber(payload.count) or #results,
        next = payload.next,
        previous = payload.previous,
        results = results,
    }
end

function Readwise:getHighlight(highlight_id)
    highlight_id = tonumber(highlight_id)
    if not highlight_id then
        return nil, {
            kind = "client",
            retryable = false,
            message = "Readwise highlight id is required.",
        }
    end
    local response, err = self:_request(
        "GET",
        Constants.READWISE_HIGHLIGHTS_URL .. tostring(highlight_id) .. "/"
    )
    if not response then return nil, err end
    local payload, decode_err = self:_decodeJson(response.body)
    if not payload then return nil, decode_err end
    local highlight = normalizeHighlight(payload)
    if not highlight then
        return nil, {
            kind = "decode",
            retryable = false,
            message = "Readwise Highlight DETAIL response was invalid.",
        }
    end
    return highlight
end

function Readwise:updateHighlight(highlight_id, patch)
    highlight_id = tonumber(highlight_id)
    if not highlight_id or type(patch) ~= "table" then
        return nil, {
            kind = "client",
            retryable = false,
            message = "Readwise highlight id and update payload are required.",
        }
    end
    local response, err = self:_request(
        "PATCH",
        Constants.READWISE_HIGHLIGHTS_URL .. tostring(highlight_id) .. "/",
        patch
    )
    if not response then return nil, err end
    local payload, decode_err = self:_decodeJson(response.body)
    if not payload then return nil, decode_err end
    local highlight = normalizeHighlight(payload)
    if not highlight then
        return nil, {
            kind = "decode",
            retryable = false,
            message = "Readwise Highlight UPDATE response was invalid.",
        }
    end
    return highlight
end

function Readwise:deleteHighlight(highlight_id)
    highlight_id = tonumber(highlight_id)
    if not highlight_id then
        return nil, {
            kind = "client",
            retryable = false,
            message = "Readwise highlight id is required.",
        }
    end
    local response, err = self:_request(
        "DELETE",
        Constants.READWISE_HIGHLIGHTS_URL .. tostring(highlight_id) .. "/"
    )
    if not response then return nil, err end
    if response.status ~= 204 then
        return nil, {
            kind = "unknown",
            status = response.status,
            retryable = false,
            message = "Readwise highlight delete returned an unexpected success status.",
        }
    end
    return true
end

function Readwise:exportUpdated(options)
    options = options or {}
    local url = queryUrl(Constants.READWISE_EXPORT_URL, {
        updatedAfter = options.updated_after,
        pageCursor = options.page_cursor,
        includeDeleted = options.include_deleted and "true" or nil,
    })
    local response, err = self:_request("GET", url)
    if not response then return nil, err end
    local payload, decode_err = self:_decodeJson(response.body)
    if not payload then return nil, decode_err end
    if type(payload.results) ~= "table" then
        return nil, {
            kind = "decode",
            retryable = false,
            message = "Readwise Export response did not contain results.",
        }
    end
    return {
        count = tonumber(payload.count) or #payload.results,
        next_page_cursor = payload.nextPageCursor,
        results = payload.results,
    }
end

Readwise._percentEncode = percentEncode
Readwise._queryUrl = queryUrl
Readwise._normalizeHighlight = normalizeHighlight

return Readwise
