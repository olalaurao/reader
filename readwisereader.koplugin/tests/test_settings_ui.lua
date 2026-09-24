-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubbedSettings(run)
    local names = {
        "ui/settings",
        "ui/widget/confirmbox",
        "ui/widget/infomessage",
        "ui/widget/multiinputdialog",
        "ui/network/manager",
        "ui/uimanager",
        "gettext",
    }
    local loaded, preload = {}, {}
    local state = { shown = {}, enabled = false, writes = 0 }
    for _, name in ipairs(names) do
        loaded[name] = package.loaded[name]
        preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    package.preload["gettext"] = function()
        return function(value) return value end
    end
    package.preload["ui/widget/confirmbox"] = function()
        return { new = function(_, value) value.kind = "confirm" return value end }
    end
    package.preload["ui/widget/infomessage"] = function()
        return { new = function(_, value) return value end }
    end
    package.preload["ui/widget/multiinputdialog"] = function()
        return { new = function(_, value) return value end }
    end
    package.preload["ui/network/manager"] = function()
        return { isOnline = function() return true end }
    end
    package.preload["ui/uimanager"] = function()
        return {
            show = function(_, widget) state.shown[#state.shown + 1] = widget end,
            close = function() end,
        }
    end

    local ok, failure = pcall(function()
        local SettingsUI = require("ui/settings")
        local config = {
            getPropagateHighlightDeletions = function() return state.enabled end,
            setPropagateHighlightDeletions = function(_, value)
                state.enabled = value == true
                state.writes = state.writes + 1
            end,
            hasAccessToken = function() return true end,
            getDownloadDirectory = function() return "/mnt/us/documents/Readwise" end,
            isSyncLocationEnabled = function() return false end,
            isSyncCategoryEnabled = function() return false end,
            getDownloadImages = function() return true end,
        }
        run(SettingsUI:new{ config = config, reader = {} }, state)
    end)

    for _, name in ipairs(names) do
        package.loaded[name] = loaded[name]
        package.preload[name] = preload[name]
    end
    if not ok then error(failure) end
end

return function()
    withStubbedSettings(function(ui, state)
        local menu = ui:getSettingsMenu()
        local highlights
        for _, item in ipairs(menu.sub_item_table) do
            if item.text == "Highlights" then highlights = item end
        end
        assert(highlights)
        local deletion = highlights.sub_item_table[1]
        assert(deletion.text == "Propagate highlight deletions")
        assert(deletion.checked_func() == false)

        deletion.callback()
        assert(state.enabled == false, "enabling deletion must require confirmation")
        assert(state.writes == 0)
        assert(state.shown[#state.shown].kind == "confirm")
        assert(state.shown[#state.shown].text:find("destructive", 1, true))

        state.shown[#state.shown].ok_callback()
        assert(state.enabled == true)
        assert(state.writes == 1)
        assert(deletion.checked_func() == true)

        deletion.callback()
        assert(state.enabled == false, "disabling deletion should be immediate")
        assert(state.writes == 2)
    end)
end
