-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubbedRawUI(run)
    local names = {
        "ui/raw_format",
        "ui/widget/container/centercontainer",
        "device",
        "ui/widget/infomessage",
        "ui/widget/menu",
        "ui/network/manager",
        "ui/trapper",
        "ui/uimanager",
        "gettext",
    }
    local saved_loaded, saved_preload = {}, {}
    for _, name in ipairs(names) do
        saved_loaded[name] = package.loaded[name]
        saved_preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    local state = {
        shown = {},
        next_ticks = {},
        online = true,
    }
    package.preload["gettext"] = function()
        return function(value) return value end
    end
    package.preload["device"] = function()
        return {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
                getSize = function() return { w = 600, h = 800 } end,
            },
        }
    end
    package.preload["ui/widget/infomessage"] = function()
        return { new = function(_, options) return options end }
    end
    package.preload["ui/widget/menu"] = function()
        return { new = function(_, options) return options end }
    end
    package.preload["ui/widget/container/centercontainer"] = function()
        return { new = function(_, options) return options end }
    end
    package.preload["ui/network/manager"] = function()
        return { isOnline = function() return state.online end }
    end
    package.preload["ui/trapper"] = function()
        return {
            wrap = function(_, callback) callback() end,
            dismissableRunInSubprocess = function(_, task)
                local a, b = task()
                return true, a, b
            end,
        }
    end
    package.preload["ui/uimanager"] = function()
        return {
            show = function(_, widget) state.shown[#state.shown + 1] = widget end,
            close = function() end,
            nextTick = function(_, callback) state.next_ticks[#state.next_ticks + 1] = callback end,
        }
    end

    local ok, err = pcall(function()
        local RawFormatUI = require("ui/raw_format")
        run(RawFormatUI, state)
    end)

    for _, name in ipairs(names) do
        package.loaded[name] = saved_loaded[name]
        package.preload[name] = saved_preload[name]
    end
    if not ok then error(err) end
end

return function()
    withStubbedRawUI(function(RawFormatUI, state)
        local metadata_calls, collection_calls, opens = 0, 0, 0
        local ui = RawFormatUI:new{
            config = { hasAccessToken = function() return true end },
            worker = {
                run = function()
                    return {
                        path = "/Readwise/EPUBs/fallback.html",
                        raw_fallback_used = true,
                        location = "new",
                        metadata = {
                            path = "/Readwise/EPUBs/fallback.html",
                            metadata = { title = "Fallback" },
                        },
                    }
                end,
            },
            koreader_documents = {
                writeMetadata = function()
                    metadata_calls = metadata_calls + 1
                    return true
                end,
                openDocument = function()
                    opens = opens + 1
                end,
            },
            collections = {
                syncLocation = function()
                    collection_calls = collection_calls + 1
                    return true
                end,
            },
        }
        ui:download("e1", "epub")
        assert(metadata_calls == 1, "fallback must still receive metadata")
        assert(collection_calls == 1, "fallback must still receive managed Collection")
        assert(opens == 0, "Gate 6 fallback must not be mistaken for original EPUB")
        assert(#state.next_ticks == 0)
        assert(#state.shown == 1)
        assert(state.shown[1].text:find("HTML fallback", 1, true))
    end)

    withStubbedRawUI(function(RawFormatUI, state)
        local opened
        local ui = RawFormatUI:new{
            config = { hasAccessToken = function() return true end },
            worker = {
                run = function()
                    return {
                        path = "/Readwise/PDFs/original.pdf",
                        raw_source_used = true,
                        location = "later",
                    }
                end,
            },
            koreader_documents = {
                writeMetadata = function() return true end,
                openDocument = function(_, path) opened = path end,
            },
            collections = {
                syncLocation = function() return true end,
            },
        }
        ui:download("p1", "pdf")
        assert(#state.next_ticks == 1)
        assert(opened == nil)
        state.next_ticks[1]()
        assert(opened == "/Readwise/PDFs/original.pdf")
    end)
end
