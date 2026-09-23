-- SPDX-License-Identifier: AGPL-3.0-only

local Images = {}
Images.__index = Images

local MIME_EXT = {
    ["image/jpeg"] = "jpg",
    ["image/png"] = "png",
    ["image/gif"] = "gif",
    ["image/webp"] = "webp",
    ["image/svg+xml"] = "svg",
}

local function headerValue(headers, wanted)
    wanted = wanted:lower()
    for key, value in pairs(headers or {}) do
        if type(key) == "string" and key:lower() == wanted then return value end
    end
end

local function escapeAttr(value)
    return tostring(value or "")
        :gsub("&", "&amp;")
        :gsub('"', "&quot;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
end

local function decodeAttr(value)
    return tostring(value or "")
        :gsub("&amp;", "&")
        :gsub("&quot;", '"')
        :gsub("&#39;", "'")
end

local function detectExt(body, headers)
    if type(body) ~= "string" or body == "" then return nil end
    if body:sub(1, 8) == "\137PNG\r\n\26\n" then return "png" end
    if body:sub(1, 3) == "\255\216\255" then return "jpg" end
    if body:sub(1, 6) == "GIF87a" or body:sub(1, 6) == "GIF89a" then return "gif" end
    if body:sub(1, 4) == "RIFF" and body:sub(9, 12) == "WEBP" then return "webp" end
    local head = body:sub(1, 1024):lower()
    if head:find("<svg", 1, true) then return "svg" end

    local content_type = headerValue(headers, "content-type")
    if type(content_type) == "string" then
        content_type = content_type:match("^%s*([^;]+)")
        if content_type then return MIME_EXT[content_type:lower()] end
    end
end

local function extractSrc(tag)
    return tag:match('[sS][rR][cC]%s*=%s*"([^"]*)"')
        or tag:match("[sS][rR][cC]%s*=%s*'([^']*)'")
        or tag:match("[sS][rR][cC]%s*=%s*([^%s>]+)")
end

local function extractAlt(tag)
    return tag:match('[aA][lL][tT]%s*=%s*"([^"]*)"')
        or tag:match("[aA][lL][tT]%s*=%s*'([^']*)'")
        or ""
end

local function placeholder(tag, reason)
    local alt = decodeAttr(extractAlt(tag))
    if alt == "" then alt = "Image" end
    return '<span class="rw-image-placeholder">[' .. escapeAttr(alt) .. " — " .. escapeAttr(reason) .. "]</span>"
end

local function defaultResolve(src, base)
    if src:match("^https?://") then return src end
    if src:sub(1, 2) == "//" then return "https:" .. src end
    if type(base) ~= "string" or base == "" then return nil end
    local ok, socket_url = pcall(require, "socket.url")
    if not ok or not socket_url then return nil end
    local absolute = socket_url.absolute(base, src)
    if type(absolute) == "string" and absolute:match("^https?://") then return absolute end
end

function Images:new(options)
    options = options or {}
    return setmetatable({
        http = assert(options.http, "http is required"),
        installer = assert(options.installer, "installer is required"),
        enabled = options.enabled ~= false,
        per_image_max = tonumber(options.per_image_max) or (2 * 1024 * 1024),
        total_max = tonumber(options.total_max) or (8 * 1024 * 1024),
        max_images = tonumber(options.max_images) or 20,
        resolve_url = options.resolve_url or defaultResolve,
        remove = options.remove or os.remove,
    }, self)
end

function Images:localize(document, absolute_asset_dir, relative_asset_dir)
    local html = assert(document.html_content, "document.html_content is required")
    local report = {
        downloaded = 0,
        reused = 0,
        failed = 0,
        skipped = 0,
        bytes = 0,
        new_paths = {},
    }
    local seen = {}
    local index = 0
    local attempts = 0
    local budget_used = 0

    local processed = html:gsub("<[iI][mM][gG][^>]*>", function(tag)
        local raw_src = extractSrc(tag)
        if not raw_src or raw_src == "" then
            report.failed = report.failed + 1
            return placeholder(tag, "missing source")
        end

        if not self.enabled then
            report.skipped = report.skipped + 1
            return placeholder(tag, "image download disabled")
        end

        local src = decodeAttr(raw_src)
        if src:match("^data:") then
            report.skipped = report.skipped + 1
            return placeholder(tag, "embedded image skipped")
        end

        local url = self.resolve_url(src, document.source_url or document.url)
        if not url then
            report.failed = report.failed + 1
            return placeholder(tag, "image unavailable")
        end

        if seen[url] then
            return string.format('<img src="%s" alt="%s">', seen[url], escapeAttr(decodeAttr(extractAlt(tag))))
        end

        if attempts >= self.max_images or budget_used >= self.total_max then
            report.skipped = report.skipped + 1
            return placeholder(tag, "image limit reached")
        end

        local remaining = self.total_max - budget_used
        local body_limit = math.min(self.per_image_max, remaining)
        if body_limit <= 0 then
            report.skipped = report.skipped + 1
            return placeholder(tag, "image limit reached")
        end

        attempts = attempts + 1
        local response, err = self.http:request{
            method = "GET",
            url = url,
            headers = { ["Accept"] = "image/*" },
            timeout_class = "download",
            max_body_bytes = body_limit,
        }
        if not response then
            if err and err.kind == "too_large" then report.skipped = report.skipped + 1
            else report.failed = report.failed + 1 end
            return placeholder(tag, err and err.kind == "too_large" and "image too large" or "image unavailable")
        end

        budget_used = budget_used + #response.body
        local ext = detectExt(response.body, response.headers)
        if not ext then
            report.failed = report.failed + 1
            return placeholder(tag, "unsupported image")
        end

        index = index + 1
        local filename = string.format("img-%03d.%s", index, ext)
        local absolute = absolute_asset_dir .. "/" .. filename
        local relative = relative_asset_dir .. "/" .. filename

        if self.installer:fileExists(absolute) then
            report.reused = report.reused + 1
        else
            local installed = self.installer:install(response.body, absolute)
            if not installed then
                report.failed = report.failed + 1
                return placeholder(tag, "image write failed")
            end
            report.downloaded = report.downloaded + 1
            report.bytes = report.bytes + #response.body
            report.new_paths[#report.new_paths + 1] = absolute
        end

        seen[url] = relative
        return string.format('<img src="%s" alt="%s">', relative, escapeAttr(decodeAttr(extractAlt(tag))))
    end)

    -- A rewritten local <img> is the only source CRengine should consider.
    processed = processed:gsub("<[sS][oO][uU][rR][cC][eE][^>]*>", "")
    processed = processed:gsub("<[pP][iI][cC][tT][uU][rR][eE][^>]*>", "")
    processed = processed:gsub("</[pP][iI][cC][tT][uU][rR][eE]%s*>", "")

    return processed, report
end

function Images:cleanup(paths)
    for _, path in ipairs(paths or {}) do pcall(self.remove, path) end
end

Images._detectExt = detectExt
Images._extractSrc = extractSrc
Images._defaultResolve = defaultResolve

return Images
