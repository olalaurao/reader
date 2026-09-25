-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubs(run)
    local names = {
        "ui/pdf_highlight_diagnostics",
        "ui/widget/infomessage",
        "ui/network/manager",
        "ui/trapper",
        "ui/uimanager",
        "sync/pdf_highlight_probe_worker",
        "koreader/paging_remote_highlight_locator",
        "gettext",
    }
    local loaded, preload = {}, {}
    local shown = {}
    for _, name in ipairs(names) do
        loaded[name] = package.loaded[name]
        preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    package.preload["gettext"] = function()
        return function(v) return v end
    end
    package.preload["ui/widget/infomessage"] = function()
        return { new = function(_, v) return v end }
    end
    package.preload["ui/network/manager"] = function()
        return { isOnline = function() return true end }
    end
    package.preload["ui/uimanager"] = function()
        return { show = function(_, widget) shown[#shown + 1] = widget end }
    end
    package.preload["ui/trapper"] = function()
        return {
            wrap = function(_, fn) fn() end,
            dismissableRunInSubprocess = function(_, fn)
                local a, b = fn()
                return true, a, b
            end,
        }
    end
    package.preload["sync/pdf_highlight_probe_worker"] =
        function() return {} end
    package.preload["koreader/paging_remote_highlight_locator"] = function()
        return {
            findUnique = function(_, text)
                if text == "Unique" then
                    return {
                        page = 4,
                        roundtrip_matches_search = true,
                    }, "unique_exact"
                elseif text == "Boundary" then
                    return {
                        page = 5,
                        roundtrip_matches_search = false,
                    }, "unique_boundary"
                elseif text == "Repeated" then
                    return nil, "ambiguous"
                elseif text == "Geometry" then
                    return nil, "geometry_mismatch"
                end
                return nil, "missing"
            end,
        }
    end

    local ok, failure = pcall(function()
        local UI = require("ui/pdf_highlight_diagnostics")
        run(UI, shown)
    end)

    for _, name in ipairs(names) do
        package.loaded[name] = loaded[name]
        package.preload[name] = preload[name]
    end
    if not ok then error(failure) end
end

return function()
    withStubs(function(UI, shown)
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            get_current_path = function() return "/books/book.pdf" end,
            get_reader_ui = function()
                return {
                    paging = {},
                    document = { is_pdf = true },
                }
            end,
            worker = {
                run = function(_, path)
                    assert(path == "/books/book.pdf")
                    return {
                        pages = 2,
                        records_scanned = 4,
                        parent_highlight_records = 5,
                        highlights_with_text = 5,
                        remote_highlights = {
                            { id = "1", content = "Unique" },
                            { id = "2", content = "Boundary" },
                            { id = "3", content = "Repeated" },
                            { id = "4", content = "Geometry" },
                            { id = "5", content = "Missing" },
                        },
                    }
                end,
            },
        }
        ui:run()
        local text = shown[#shown].text
        assert(text:find("Local PDF probes run: 3", 1, true))
        assert(text:find("Unique exact paging matches: 1", 1, true))
        assert(text:find("Unique word-boundary paging matches: 1", 1, true))
        assert(text:find("Validated paging positions total: 2", 1, true))
        assert(text:find("Ambiguous matches: 1", 1, true))
        assert(text:find("Full-text round-trip differences (diagnostic): 1", 1, true))
        assert(text:find("Remote writes: none", 1, true))
        assert(text:find("Local annotation/sidecar writes: none", 1, true))
    end)
end
