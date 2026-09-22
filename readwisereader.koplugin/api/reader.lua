-- SPDX-License-Identifier: AGPL-3.0-only

local Constants = require("constants")

local Reader = {}
Reader.__index = Reader

local QUERY_ORDER = {
    "id",
    "updatedAfter",
    "location",
    "category",
    "tag",
    "limit",
    "pageCursor",
    "withHtmlContent",
    "withRawSourceUrl",
}

local function percentEncode(value)
    return (tostring(value):gsub("([^A-Za-z0-9%-._~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function addQueryValue(parts, key, value)
    if value == nil then
        return
    end
    if type(value) == "table" then
        for _, item in ipairs(value) do
            parts[#parts + 1] = percentEncode(key) .. "=" .. percentEncode(item)
        end
        return
    end
    parts[#parts + 1] = percentEncode(key) .. "=" .. percentEncode(value)
end

local function buildListUrl(options)
    options = options or {}
    local limit = tonumber(options.limit) or 100
    if limit < 1 or limit > 100 or limit ~= math.floor(limit) then
        return nil, {
            kind = "client",
            retryable = false,
            message = "Reader LIST limit must be an integer from 1 to 100.",
        }
    end

    local values = {
        id = options.id,
        updatedAfter = options.updated_after,
        location = options.location,
        category = options.category,
        tag = options.tags or options.tag,
        limit = limit,
        pageCursor = options.page_cursor,
        withHtmlContent = options.with_html_content == true and "true" or "false",
        withRawSourceUrl = options.with_raw_source_url == true and "true" or "false",
    }

    local parts = {}
    for _, key in ipairs(QUERY_ORDER) do
        addQueryValue(parts, key, values[key])
    end
    return Constants.READER_LIST_URL .. "?" .. table.concat(parts, "&")
end

local function normalizeDocument(raw)
    if type(raw) ~= "table" or type(raw.id) ~= "string" or raw.id == "" then
        return nil, {
            kind = "decode",
            retryable = false,
            message = "Reader returned a document without a valid id.",
        }
    end

    return {
        id = raw.id,
        url = raw.url,
        source_url = raw.source_url,
        title = raw.title,
        author = raw.author,
        source = raw.source,
        category = raw.category,
        location = raw.location,
        tags = raw.tags,
        site_name = raw.site_name,
        word_count = raw.word_count,
        reading_time = raw.reading_time,
        created_at = raw.created_at,
        updated_at = raw.updated_at,
        notes = raw.notes,
        summary = raw.summary,
        image_url = raw.image_url,
        parent_id = raw.parent_id,
        reading_progress = raw.reading_progress,
        first_opened_at = raw.first_opened_at,
        last_opened_at = raw.last_opened_at,
        saved_at = raw.saved_at,
        last_moved_at = raw.last_moved_at,
        html_content = raw.html_content,
        raw_source_url = raw.raw_source_url,
        raw_source_available = type(raw.raw_source_url) == "string" and raw.raw_source_url ~= "",
    }
end

local function defaultJson()
    return require("json")
end

function Reader:new(options)
    options = options or {}
    return setmetatable({
        http = assert(options.http, "http is required"),
        config = assert(options.config, "config is required"),
        json = options.json,
    }, self)
end

function Reader:_getToken()
    local token = self.config:getAccessToken()
    if token then
        return token
    end
    return nil, {
        kind = "auth",
        retryable = false,
        message = "Access token is not configured.",
    }
end

function Reader:_decodeJson(body)
    local json = self.json or defaultJson()
    local ok, result = pcall(json.decode, body, json.decode.simple)
    if not ok or type(result) ~= "table" then
        return nil, {
            kind = "decode",
            retryable = false,
            message = "Reader returned malformed JSON.",
        }
    end
    return result
end

function Reader:validateToken()
    local token, token_err = self:_getToken()
    if not token then
        return nil, token_err
    end

    local response, err = self.http:request{
        method = "GET",
        url = Constants.AUTH_URL,
        headers = {
            ["Accept"] = "application/json",
            ["Authorization"] = "Token " .. token,
        },
        timeout_class = "api",
    }

    if not response then
        return nil, err
    end

    if response.status ~= 204 then
        return nil, {
            kind = "unknown",
            status = response.status,
            retryable = false,
            message = "Authentication returned an unexpected success status.",
        }
    end

    return true
end

function Reader:listDocuments(options)
    options = options or {}
    local token, token_err = self:_getToken()
    if not token then
        return nil, token_err
    end

    local request_url, url_err = buildListUrl(options)
    if not request_url then
        return nil, url_err
    end

    local response, err = self.http:request{
        method = "GET",
        url = request_url,
        headers = {
            ["Accept"] = "application/json",
            ["Authorization"] = "Token " .. token,
        },
        timeout_class = "api",
    }
    if not response then
        return nil, err
    end

    local payload, decode_err = self:_decodeJson(response.body)
    if not payload then
        return nil, decode_err
    end
    if type(payload.results) ~= "table" then
        return nil, {
            kind = "decode",
            retryable = false,
            message = "Reader LIST response did not contain a results array.",
        }
    end

    local next_cursor = payload.nextPageCursor
    if next_cursor ~= nil and (type(next_cursor) ~= "string" or next_cursor == "") then
        return nil, {
            kind = "decode",
            retryable = false,
            message = "Reader LIST response contained an invalid next-page cursor.",
        }
    end

    local documents = {}
    for index, raw in ipairs(payload.results) do
        local document, document_err = normalizeDocument(raw)
        if not document then
            document_err.index = index
            return nil, document_err
        end
        documents[#documents + 1] = document
    end

    return {
        results = documents,
        next_page_cursor = next_cursor,
    }
end

Reader._percentEncode = percentEncode
Reader._buildListUrl = buildListUrl
Reader._normalizeDocument = normalizeDocument

return Reader
