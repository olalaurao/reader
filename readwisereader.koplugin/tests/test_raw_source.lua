-- SPDX-License-Identifier: AGPL-3.0-only

local RawSource = require("content/raw_source")

local function installer()
    local state = { installed = {} }
    return {
        state = state,
        installStream = function(_, final_path, producer, validator)
            local chunks = {}
            local response, err = producer(function(chunk)
                if chunk then chunks[#chunks + 1] = chunk end
                return 1
            end)
            if not response then return nil, err end
            local body = table.concat(chunks)
            local ok, validation_err = validator(final_path .. ".tmp", #body, response)
            if not ok then return nil, validation_err end
            state.installed[final_path] = body
            return {
                path = final_path,
                bytes = #body,
                producer_result = response,
            }
        end,
    }
end

return function()
    do
        local inst = installer()
        local raw = RawSource:new{
            http = {
                request = function(_, request)
                    assert(request.url == "https://signed.example/test.pdf?secret=1")
                    assert(request.max_body_bytes == 1024)
                    assert(request.sink("%PDF-1.7\nbody") == 1)
                    return {
                        status = 200,
                        headers = { ["Content-Type"] = "application/pdf" },
                        bytes_received = #"%PDF-1.7\nbody",
                    }
                end,
            },
            installer = inst,
            download_root = "/root",
            max_bytes = 1024,
            min_free_bytes = 100,
            disk_usage = function() return { available = 1000 } end,
        }
        local result, err = raw:download({
            id = "p1",
            category = "pdf",
            raw_source_url = "https://signed.example/test.pdf?secret=1",
        }, "/root/PDF/p1.pdf")
        assert(err == nil)
        assert(result.format == "pdf")
        assert(result.download_strategy == "reader_raw_source")
        assert(inst.state.installed["/root/PDF/p1.pdf"] == "%PDF-1.7\nbody")
    end

    do
        local inst = installer()
        local raw = RawSource:new{
            http = {
                request = function(_, request)
                    assert(request.sink("PK\003\004epub") == 1)
                    return { status = 200, headers = {}, bytes_received = 8 }
                end,
            },
            installer = inst,
            download_root = "/root",
            max_bytes = 1024,
            min_free_bytes = 0,
            disk_usage = function() return { available = 1000 } end,
        }
        local result, err = raw:download({
            id = "e1",
            category = "epub",
            raw_source_url = "https://signed.example/test.epub",
        }, "/root/EPUB/e1.epub")
        assert(err == nil)
        assert(result.format == "epub")
    end

    do
        -- Exactly the configured reserve is still allowed; only values below
        -- it are rejected before any network/download work.
        local inst = installer()
        local raw = RawSource:new{
            http = {
                request = function(_, request)
                    assert(request.sink("%PDF-1.7\nreserve-boundary") == 1)
                    return { status = 200, headers = {} }
                end,
            },
            installer = inst,
            download_root = "/root",
            max_bytes = 1024,
            min_free_bytes = 100,
            disk_usage = function() return { available = 100 } end,
        }
        local result, err = raw:download({
            category = "pdf",
            raw_source_url = "https://signed.example/boundary.pdf",
        }, "/root/boundary.pdf")
        assert(err == nil)
        assert(result.path == "/root/boundary.pdf")
    end

    do
        local raw = RawSource:new{
            http = { request = function() error("must not request") end },
            installer = installer(),
            download_root = "/root",
            max_bytes = 1024,
            min_free_bytes = 100,
            disk_usage = function() return { available = 50 } end,
        }
        local result, err = raw:download({
            category = "pdf",
            raw_source_url = "https://signed.example/test.pdf",
        }, "/root/test.pdf")
        assert(result == nil)
        assert(err.kind == "no_space")
        assert(err.retryable == true)
    end

    do
        local raw = RawSource:new{
            http = { request = function() error("must not request") end },
            installer = installer(),
            download_root = "/root",
            max_bytes = 1024,
            disk_usage = function() return { available = 1000 } end,
        }
        local result, err = raw:download({ category = "pdf" }, "/root/test.pdf")
        assert(result == nil)
        assert(err.kind == "raw_unavailable")
        assert(raw:isFallbackEligible(err) == true)
    end

    do
        local inst = installer()
        local raw = RawSource:new{
            http = {
                request = function(_, request)
                    assert(request.sink("<html>not pdf</html>") == 1)
                    return { status = 200, headers = {} }
                end,
            },
            installer = inst,
            download_root = "/root",
            max_bytes = 1024,
            disk_usage = function() return { available = 1000 } end,
        }
        local result, err = raw:download({
            category = "pdf",
            raw_source_url = "https://signed.example/test.pdf",
        }, "/root/test.pdf")
        assert(result == nil)
        assert(err.kind == "raw_invalid")
        assert(raw:isFallbackEligible(err) == true)
    end

    do
        local raw = RawSource:new{
            http = {},
            installer = {},
            download_root = "/root",
            max_bytes = 1024,
            disk_usage = function() return { available = 1000 } end,
        }
        assert(raw:isFallbackEligible({ kind = "too_large" }) == true)
        assert(raw:isFallbackEligible({ kind = "raw_invalid" }) == true)
        assert(raw:isFallbackEligible({ kind = "client", retryable = false }) == true)
        assert(raw:isFallbackEligible({ kind = "timeout", retryable = true }) == false)
    end

    assert(RawSource._validateMagic("pdf", "%PDF-1.4") == true)
    assert(RawSource._validateMagic("epub", "PK\003\004abc") == true)
    assert(RawSource._validateMagic("pdf", "PK\003\004abc") == false)
end
