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
    local state = {
        shown = {},
        enabled = false,
        writes = 0,
        archive_finished = true,
        archive_writes = 0,
        categories = {},
    }
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
            getArchiveFinished = function() return state.archive_finished end,
            setArchiveFinished = function(_, value)
                state.archive_finished = value == true
                state.archive_writes = state.archive_writes + 1
            end,
            getPropagateHighlightDeletions = function() return state.enabled end,
            setPropagateHighlightDeletions = function(_, value)
                state.enabled = value == true
                state.writes = state.writes + 1
            end,
            hasAccessToken = function() return true end,
            getDownloadDirectory = function() return "/mnt/us/documents/Readwise" end,
            isSyncLocationEnabled = function() return false end,
            isSyncCategoryEnabled = function(_, category)
                return state.categories[category] == true
            end,
            setSyncCategoryEnabled = function(_, category, value)
                state.categories[category] = value == true
            end,
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

        local finished
        for _, item in ipairs(menu.sub_item_table) do
            if item.text == "Finished documents" then finished = item end
        end
        assert(finished)
        local archive = finished.sub_item_table[1]
        assert(archive.text == "Archive in Reader")
        assert(archive.checked_func() == true)
        archive.callback()
        assert(state.archive_finished == false)
        assert(state.archive_writes == 1)
        archive.callback()
        assert(state.archive_finished == true)
        assert(state.archive_writes == 2)

        local documents
        for _, item in ipairs(menu.sub_item_table) do
            if item.text == "Documents" then documents = item end
        end
        assert(documents)
        local types
        for _, item in ipairs(documents.sub_item_table) do
            if item.text == "Types" then types = item end
        end
        assert(types)
        local by_text = {}
        for _, item in ipairs(types.sub_item_table) do by_text[item.text] = item end
        assert(by_text["Email / newsletters"])
        assert(by_text["RSS"])
        assert(by_text["Tweets"])
        assert(by_text["Videos"])
        assert(by_text["Email / newsletters"].checked_func() == false)
        by_text["Email / newsletters"].callback()
        assert(state.categories.email == true)
        by_text["RSS"].callback()
        assert(state.categories.rss == true)
        by_text["Tweets"].callback()
        assert(state.categories.tweet == true)
        by_text["Videos"].callback()
        assert(state.categories.video == true)
    end)
end
