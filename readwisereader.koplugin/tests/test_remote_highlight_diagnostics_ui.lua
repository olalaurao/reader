-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubs(run)
    local names = {
        "ui/remote_highlight_diagnostics",
        "ui/widget/infomessage",
        "ui/network/manager",
        "ui/trapper",
        "ui/uimanager",
        "sync/remote_highlight_probe_worker",
        "gettext",
    }
    local loaded, preload = {}, {}
    local shown = {}
    for _, name in ipairs(names) do
        loaded[name] = package.loaded[name]
        preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    package.preload["gettext"] = function() return function(v) return v end end
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
    package.preload["sync/remote_highlight_probe_worker"] = function() return {} end

    local ok, failure = pcall(function()
        local UI = require("ui/remote_highlight_diagnostics")
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
        local calls = 0
        local reader_ui = {
            rolling = {},
            document = {
                findAllText = function(_, text)
                    calls = calls + 1
                    if text == "Unique" then
                        return { { start = "xp1", ["end"] = "xp2" } }
                    elseif text == "Repeated" then
                        return {
                            { start = "a", ["end"] = "b" },
                            { start = "c", ["end"] = "d" },
                        }
                    end
                    return nil
                end,
                getTextFromXPointers = function(_, start, finish)
                    assert(start == "xp1" and finish == "xp2")
                    return "Unique"
                end,
            },
        }
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            get_current_path = function() return "/books/book.epub" end,
            get_reader_ui = function() return reader_ui end,
            worker = {
                run = function(_, path)
                    assert(path == "/books/book.epub")
                    return {
                        pages = 1,
                        records_scanned = 3,
                        parent_highlight_records = 3,
                        highlights_with_text = 3,
                        remote_highlights = {
                            { id = "1", content = "Unique" },
                            { id = "2", content = "Repeated" },
                            { id = "3", content = "Missing" },
                        },
                    }
                end,
            },
        }
        ui:run()
        assert(calls == 3)
        local text = shown[#shown].text
        assert(text:find("Unique exact XPointer matches: 1", 1, true))
        assert(text:find("Ambiguous matches: 1", 1, true))
        assert(text:find("Missing matches: 1", 1, true))
        assert(text:find("Remote writes: none", 1, true))
        assert(text:find("Local writes: none", 1, true))
    end)
end
