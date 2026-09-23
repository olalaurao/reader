-- SPDX-License-Identifier: AGPL-3.0-only

local RawSource = {}
RawSource.__index = RawSource

local function defaultDiskUsage(path)
    return require("util").diskUsage(path)
end

local function startsWith(value, prefix)
    return type(value) == "string" and value:sub(1, #prefix) == prefix
end

local function validateMagic(category, prefix)
    if category == "pdf" then
        return startsWith(prefix, "%PDF-")
    elseif category == "epub" then
        return startsWith(prefix, "PK\003\004")
            or startsWith(prefix, "PK\005\006")
            or startsWith(prefix, "PK\007\008")
    end
    return false
end

function RawSource:new(options)
    options = options or {}
    return setmetatable({
        http = assert(options.http, "http is required"),
        installer = assert(options.installer, "installer is required"),
        download_root = assert(options.download_root, "download_root is required"),
        max_bytes = assert(tonumber(options.max_bytes), "max_bytes is required"),
        min_free_bytes = tonumber(options.min_free_bytes) or 0,
        disk_usage = options.disk_usage or defaultDiskUsage,
    }, self)
end

function RawSource:download(document, final_path)
    assert(type(document) == "table", "document is required")
    assert(type(final_path) == "string" and final_path ~= "", "final_path is required")

    local category = document.category
    if category ~= "pdf" and category ~= "epub" then
        return nil, {
            kind = "content",
            stage = "raw_category",
            retryable = false,
            message = "Raw source download is only supported for PDF and EPUB documents.",
        }
    end

    local raw_url = document.raw_source_url
    if type(raw_url) ~= "string" or raw_url == "" then
        return nil, {
            kind = "raw_unavailable",
            stage = "raw_url",
            retryable = false,
            message = "Reader did not provide a distributable raw source URL.",
        }
    end
    if not raw_url:match("^https://") then
        return nil, {
            kind = "raw_unavailable",
            stage = "raw_url",
            retryable = false,
            message = "Reader returned an unsafe raw source URL.",
        }
    end

    local usage = self.disk_usage(self.download_root)
    local available = usage and tonumber(usage.available)
    if available and available < self.min_free_bytes then
        return nil, {
            kind = "no_space",
            stage = "preflight",
            retryable = true,
            message = "Not enough free space remains for a raw Reader document.",
            available = available,
            reserve = self.min_free_bytes,
        }
    end

    local prefix = ""
    local installed, err = self.installer:installStream(
        final_path,
        function(file_sink)
            local response, request_err = self.http:request{
                method = "GET",
                url = raw_url,
                headers = {
                    ["Accept"] = category == "pdf"
                        and "application/pdf,application/octet-stream;q=0.9,*/*;q=0.1"
                        or "application/epub+zip,application/zip;q=0.9,application/octet-stream;q=0.8,*/*;q=0.1",
                },
                timeout_class = "download",
                max_body_bytes = self.max_bytes,
                sink = function(chunk)
                    if chunk and #prefix < 16 then
                        local needed = 16 - #prefix
                        prefix = prefix .. chunk:sub(1, needed)
                    end
                    return file_sink(chunk)
                end,
            }
            if not response then return nil, request_err end
            return response
        end,
        function(_, bytes)
            if bytes <= 0 or not validateMagic(category, prefix) then
                return nil, {
                    kind = "raw_invalid",
                    stage = "validate",
                    retryable = false,
                    message = "Reader raw source did not match the expected file format.",
                }
            end
            return true
        end
    )

    -- The signed raw_source_url is intentionally never returned or stored.
    if not installed then return nil, err end
    return {
        path = installed.path,
        bytes = installed.bytes,
        format = category,
        download_strategy = "reader_raw_source",
        durability_warning = installed.durability_warning,
    }
end

function RawSource:isFallbackEligible(err)
    if not err then return false end
    return err.kind == "raw_unavailable"
        or err.kind == "raw_invalid"
        or err.kind == "too_large"
        or (err.kind == "client" and err.retryable == false)
end

RawSource._validateMagic = validateMagic

return RawSource
