-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubbedLibraryUI(run, initial_online)
    local module_names = {
        "ui.library",
        "ui/widget/infomessage",
        "ui/network/manager",
        "ui/trapper",
        "ui/uimanager",
        "gettext",
    }
    local saved_loaded = {}
    local saved_preload = {}
    for _, name in ipairs(module_names) do
        saved_loaded[name] = package.loaded[name]
        saved_preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    local shown = {}
    local state = {
        online = initial_online ~= false,
        wrap_calls = 0,
        subprocess_calls = 0,
    }

    package.preload["gettext"] = function()
        return function(text)
            return text
        end
    end
    package.preload["ui/widget/infomessage"] = function()
        return {
            new = function(_, options)
                return options
            end,
        }
    end
    package.preload["ui/network/manager"] = function()
        return {
            isOnline = function()
                return state.online
            end,
        }
    end
    package.preload["ui/uimanager"] = function()
        return {
            show = function(_, widget)
                shown[#shown + 1] = widget
            end,
        }
    end
    package.preload["ui/trapper"] = function()
        return {
            wrap = function(_, callback)
                state.wrap_calls = state.wrap_calls + 1
                callback()
                return true
            end,
            dismissableRunInSubprocess = function(_, task, message)
                state.subprocess_calls = state.subprocess_calls + 1
                state.progress_message = message
                return true, task()
            end,
        }
    end

    local ok, err = pcall(function()
        local LibraryUI = require("ui/library")
        run(LibraryUI, state, shown)
    end)

    for _, name in ipairs(module_names) do
        package.loaded[name] = saved_loaded[name]
        package.preload[name] = saved_preload[name]
    end

    if not ok then
        error(err)
    end
end

return function()
    withStubbedLibraryUI(function(LibraryUI, state, shown)
        local scanner_calls = 0
        local ui = LibraryUI:new{
            config = {
                hasAccessToken = function()
                    return true
                end,
            },
            scanner = {
                scan = function()
                    scanner_calls = scanner_calls + 1
                    return {
                        top_level_documents = 2,
                        pages = 1,
                        duplicates_ignored = 0,
                        child_records = 1,
                        by_location = { new = 2 },
                        by_category = { article = 2 },
                    }
                end,
            },
        }

        ui:scanMetadata()

        assert(state.wrap_calls == 1)
        assert(state.subprocess_calls == 1)
        assert(scanner_calls == 1)
        assert(type(state.progress_message) == "string")
        assert(state.progress_message:find("Tap to cancel", 1, true))
        assert(#shown == 1)
        assert(shown[1].text:find("Reader metadata scan complete", 1, true))
    end)

    withStubbedLibraryUI(function(LibraryUI, state, shown)
        local ui = LibraryUI:new{
            config = {
                hasAccessToken = function()
                    return true
                end,
            },
            scanner = {
                scan = function()
                    error("offline scan must not start")
                end,
            },
        }

        ui:scanMetadata()

        assert(state.wrap_calls == 0)
        assert(state.subprocess_calls == 0)
        assert(#shown == 1)
        assert(shown[1].text:find("No internet connection", 1, true))
    end, false)
end
