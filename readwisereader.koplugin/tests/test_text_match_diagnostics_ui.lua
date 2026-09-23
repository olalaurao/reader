-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubbedUI(run)
    local names = {
        "ui/text_match_diagnostics",
        "ui/widget/infomessage",
        "ui/network/manager",
        "ui/trapper",
        "ui/uimanager",
        "sync/text_match_probe_worker",
        "gettext",
    }
    local saved_loaded, saved_preload = {}, {}
    for _, name in ipairs(names) do
        saved_loaded[name] = package.loaded[name]
        saved_preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    local shown = {}
    package.preload["gettext"] = function()
        return function(value) return value end
    end
    package.preload["ui/widget/infomessage"] = function()
        return { new = function(_, options) return options end }
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
                local report, err = fn()
                return true, report, err
            end,
        }
    end
    package.preload["sync/text_match_probe_worker"] = function()
        return { run = function() error("default worker must be injected in test") end }
    end

    local ok, err = pcall(function()
        run(require("ui/text_match_diagnostics"), shown)
    end)

    for _, name in ipairs(names) do
        package.loaded[name] = saved_loaded[name]
        package.preload[name] = saved_preload[name]
    end
    if not ok then error(err) end
end

return function()
    withStubbedUI(function(UI, shown)
        local called
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            get_current_path = function() return "/Readwise/a.html" end,
            worker = {
                run = function(_, path)
                    called = path
                    return {
                        matched = true,
                        mode = "punctuation",
                        local_text = 'She said "hello" - today.',
                        reader_exact_text = "She said “hello” — today.",
                        remote_writes = 0,
                    }
                end,
            },
        }
        ui:run()
        assert(called == "/Readwise/a.html")
        assert(#shown == 1)
        assert(shown[1].text:find("Matched: yes", 1, true))
        assert(shown[1].text:find("Result: punctuation", 1, true))
        assert(shown[1].text:find("Remote writes: none", 1, true))
    end)

    withStubbedUI(function(UI, shown)
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            get_current_path = function() return "/Readwise/a.html" end,
            worker = {
                run = function()
                    return {
                        matched = false,
                        status = "ambiguous",
                        message = "Highlight text occurs more than once.",
                        local_text = "same sentence",
                        remote_writes = 0,
                    }
                end,
            },
        }
        ui:run()
        assert(#shown == 1)
        assert(shown[1].text:find("Matched: no", 1, true))
        assert(shown[1].text:find("Result: ambiguous", 1, true))
        assert(shown[1].text:find("Remote writes: none", 1, true))
    end)
end
