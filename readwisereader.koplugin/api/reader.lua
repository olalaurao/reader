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

local function normalizeTags(raw_tags)
    if type(raw_tags) ~= "table" then return {} end

    local out, seen = {}, {}
    local function add(value)
        if type(value) ~= "string" then return end
        local tag = value:match("^%s*(.-)%s*$")
        if tag ~= "" and not seen[tag] then
            seen[tag] = true
            out[#out + 1] = tag
        end
    end

    -- Reader's Document LIST currently returns tags as an object whose values
    -- are tag records (with a `name` field), while create/update endpoints
    -- accept arrays of strings. Accept both shapes at the API boundary so the
    -- rest of the plugin always sees one canonical array of tag names.
    for _, value in pairs(raw_tags) do
        if type(value) == "string" then
            add(value)
        elseif type(value) == "table" then
            add(value.name)
        end
    end
    table.sort(out)
    return out
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
        tags = normalizeTags(raw.tags),
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

local function defaultJsonDecode(body)
    local JSON = require("json")
    return JSON.decode(body, JSON.decode.simple)
end

local function defaultClock()
    return require("socket").gettime()
end

local function defaultSleep(seconds)
    require("socket").sleep(seconds)
end

function Reader:new(options)
    options = options or {}
    return setmetatable({
        http = assert(options.http, "http is required"),
        config = assert(options.config, "config is required"),
        json_decode = options.json_decode,
        clock = options.clock or defaultClock,
        sleep = options.sleep or defaultSleep,
        list_min_interval = options.list_min_interval or Constants.READER_LIST_MIN_INTERVAL_SECONDS,
        last_list_request_at = nil,
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
    local decode = self.json_decode or defaultJsonDecode
    local ok, result = pcall(decode, body)
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

function Reader:_sleepCancelable(seconds, is_cancelled)
    local remaining = math.max(tonumber(seconds) or 0, 0)
    while remaining > 0 do
        if is_cancelled and is_cancelled() then
            return nil, {
                kind = "cancelled",
                retryable = false,
                message = "Reader metadata scan was cancelled.",
            }
        end

        local slice = math.min(remaining, 0.25)
        self.sleep(slice)
        remaining = remaining - slice
    end

    if is_cancelled and is_cancelled() then
        return nil, {
            kind = "cancelled",
            retryable = false,
            message = "Reader metadata scan was cancelled.",
        }
    end
    return true
end

function Reader:_waitForListSlot(is_cancelled)
    local last_request_at = self.last_list_request_at
    if last_request_at ~= nil then
        local now = self.clock()
        local remaining = self.list_min_interval - (now - last_request_at)
        -- Ignore sub-millisecond floating-point residue; neither LuaSocket
        -- timers nor the device scheduler can meaningfully honor it.
        while remaining > 0.001 do
            if is_cancelled and is_cancelled() then
                return nil, {
                    kind = "cancelled",
                    retryable = false,
                    message = "Reader metadata scan was cancelled.",
                }
            end

            -- Keep sleeps short so a future in-process caller can cooperate
            -- with cancellation instead of entering one long rate-limit sleep.
            local slice = math.min(remaining, 0.25)
            local slept, sleep_err = self:_sleepCancelable(slice, is_cancelled)
            if not slept then
                return nil, sleep_err
            end
            now = self.clock()
            remaining = self.list_min_interval - (now - last_request_at)
        end
    end

    if is_cancelled and is_cancelled() then
        return nil, {
            kind = "cancelled",
            retryable = false,
            message = "Reader metadata scan was cancelled.",
        }
    end

    self.last_list_request_at = self.clock()
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

    local allowed, limit_err = self:_waitForListSlot(options.is_cancelled)
    if not allowed then
        return nil, limit_err
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

function Reader:getDocument(reader_id, with_html_content, with_raw_source_url)
    if type(reader_id) ~= "string" or reader_id == "" then
        return nil, {
            kind = "client",
            retryable = false,
            message = "Reader document id is required.",
        }
    end

    local page, err = self:listDocuments{
        id = reader_id,
        limit = 1,
        with_html_content = with_html_content == true,
        with_raw_source_url = with_raw_source_url == true,
    }
    if not page then
        return nil, err
    end

    for _, document in ipairs(page.results) do
        if document.id == reader_id then
            return document
        end
    end

    return nil, {
        kind = "not_found",
        retryable = false,
        message = "Reader document was not found.",
    }
end

local function copyOptions(options)
    local copy = {}
    for key, value in pairs(options or {}) do
        copy[key] = value
    end
    return copy
end

function Reader:iterateDocuments(options, callback)
    options = options or {}
    callback = callback or function() end

    local cursor = options.page_cursor
    local seen_cursors = {}
    local seen_document_ids = {}
    local report = {
        pages = 0,
        received = 0,
        unique = 0,
        duplicates = 0,
    }

    while true do
        if options.is_cancelled and options.is_cancelled() then
            return nil, {
                kind = "cancelled",
                retryable = false,
                message = "Reader metadata scan was cancelled.",
                report = report,
            }
        end

        if cursor ~= nil then
            if seen_cursors[cursor] then
                return nil, {
                    kind = "pagination",
                    retryable = false,
                    message = "Reader returned a repeated page cursor.",
                    cursor = cursor,
                    report = report,
                }
            end
            seen_cursors[cursor] = true
        end

        local page_options = copyOptions(options)
        page_options.page_cursor = cursor

        local page
        local err
        local rate_limit_retries = 0
        while true do
            page, err = self:listDocuments(page_options)
            if page then
                break
            end

            local can_retry_rate_limit = err
                and err.kind == "rate_limit"
                and rate_limit_retries < Constants.READER_LIST_MAX_RATE_LIMIT_RETRIES
            if not can_retry_rate_limit then
                if err then
                    err.page = report.pages + 1
                    err.report = report
                end
                return nil, err
            end

            rate_limit_retries = rate_limit_retries + 1
            local retry_delay = tonumber(err.retry_after)
                or (Constants.READER_LIST_RATE_LIMIT_BACKOFF_SECONDS[rate_limit_retries] or 15)
            local slept, sleep_err = self:_sleepCancelable(retry_delay, options.is_cancelled)
            if not slept then
                sleep_err.page = report.pages + 1
                sleep_err.report = report
                return nil, sleep_err
            end
        end

        report.pages = report.pages + 1
        if #page.results == 0 and page.next_page_cursor ~= nil then
            return nil, {
                kind = "pagination",
                retryable = false,
                message = "Reader returned an empty page with another cursor.",
                cursor = page.next_page_cursor,
                report = report,
            }
        end

        for _, document in ipairs(page.results) do
            if options.is_cancelled and options.is_cancelled() then
                return nil, {
                    kind = "cancelled",
                    retryable = false,
                    message = "Reader metadata scan was cancelled.",
                    report = report,
                }
            end

            report.received = report.received + 1
            if seen_document_ids[document.id] then
                report.duplicates = report.duplicates + 1
            else
                seen_document_ids[document.id] = true
                report.unique = report.unique + 1
                local ok, callback_result = pcall(callback, document, report)
                if not ok then
                    return nil, {
                        kind = "callback",
                        retryable = false,
                        message = "Reader document callback failed.",
                        report = report,
                    }
                end
                if callback_result == false then
                    return nil, {
                        kind = "cancelled",
                        retryable = false,
                        message = "Reader metadata scan was cancelled.",
                        report = report,
                    }
                end
            end
        end

        local next_cursor = page.next_page_cursor
        if next_cursor == nil then
            break
        end
        if seen_cursors[next_cursor] then
            return nil, {
                kind = "pagination",
                retryable = false,
                message = "Reader returned a repeated page cursor.",
                cursor = next_cursor,
                report = report,
            }
        end
        cursor = next_cursor
    end

    return report
end

Reader._percentEncode = percentEncode
Reader._buildListUrl = buildListUrl
Reader._normalizeTags = normalizeTags
Reader._normalizeDocument = normalizeDocument

return Reader
