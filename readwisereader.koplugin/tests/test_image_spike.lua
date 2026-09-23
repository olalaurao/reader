-- SPDX-License-Identifier: AGPL-3.0-only

local ImageSpike = require("content/image_spike")

local function withStubbedUI(run)
    local names = {
        "ui/image_spike",
        "ui/widget/infomessage",
        "ui/uimanager",
        "gettext",
    }
    local saved_loaded, saved_preload = {}, {}
    for _, name in ipairs(names) do
        saved_loaded[name] = package.loaded[name]
        saved_preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    local state = { shown = {}, next_ticks = {} }
    package.preload["gettext"] = function()
        return function(value) return value end
    end
    package.preload["ui/widget/infomessage"] = function()
        return { new = function(_, value) return value end }
    end
    package.preload["ui/uimanager"] = function()
        return {
            show = function(_, widget) state.shown[#state.shown + 1] = widget end,
            nextTick = function(_, callback) state.next_ticks[#state.next_ticks + 1] = callback end,
        }
    end

    local ok, err = pcall(function()
        local ImageSpikeUI = require("ui/image_spike")
        run(ImageSpikeUI, state)
    end)

    for _, name in ipairs(names) do
        package.loaded[name] = saved_loaded[name]
        package.preload[name] = saved_preload[name]
    end
    if not ok then error(err) end
end

return function()
    local html = ImageSpike.html()
    local svg = ImageSpike.svg()
    assert(html:find('src="gate5%-assets/gate5%-test%.svg"'))
    assert(html:find('missing%-on%-purpose%.svg'))
    assert(not html:find("/mnt/us/", 1, true), "fixture must exercise a relative asset path")
    assert(svg:find("<svg", 1, true))
    assert(svg:find("GATE 5", 1, true))

    withStubbedUI(function(ImageSpikeUI, state)
        local installs = {}
        local opened
        local installer = {
            fileExists = function() return false end,
            install = function(_, content, path)
                installs[#installs + 1] = { content = content, path = path }
                return { path = path }
            end,
        }
        local ui = ImageSpikeUI:new{
            config = {
                getDownloadDirectory = function()
                    return "/mnt/us/documents/Readwise"
                end,
            },
            installer = installer,
            koreader_documents = {
                openDocument = function(_, path) opened = path end,
            },
        }

        ui:run()
        assert(#installs == 2)
        assert(installs[1].path == "/mnt/us/documents/Readwise/Diagnostics/gate5-assets/gate5-test.svg")
        assert(installs[1].content == svg)
        assert(installs[2].path == "/mnt/us/documents/Readwise/Diagnostics/gate5-relative-assets-v1.html")
        assert(installs[2].content == html)
        assert(#state.next_ticks == 1)
        assert(opened == nil)
        state.next_ticks[1]()
        assert(opened == "/mnt/us/documents/Readwise/Diagnostics/gate5-relative-assets-v1.html")
        assert(#state.shown == 0)
    end)

    withStubbedUI(function(ImageSpikeUI, state)
        local installs = 0
        local opened
        local ui = ImageSpikeUI:new{
            config = {
                getDownloadDirectory = function()
                    return "/mnt/us/documents/Readwise"
                end,
            },
            installer = {
                fileExists = function() return true end,
                install = function()
                    installs = installs + 1
                    error("existing diagnostic files must be reused")
                end,
            },
            koreader_documents = {
                openDocument = function(_, path) opened = path end,
            },
        }
        ui:run()
        assert(installs == 0)
        assert(#state.next_ticks == 1)
        state.next_ticks[1]()
        assert(opened:find("gate5%-relative%-assets%-v1%.html"))
    end)
end
