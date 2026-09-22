-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local VERSION = "0.0.1"

local ReadwiseReader = WidgetContainer:extend{
    name = "readwisereader",
    is_doc_only = false,
    version = VERSION,
}

function ReadwiseReader:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReadwiseReader:addToMainMenu(menu_items)
    menu_items.readwisereader = {
        text = _("Readwise Reader"),
        sorting_hint = "more_tools",
        callback = function()
            UIManager:show(InfoMessage:new{
                text = string.format(
                    _("Readwise Reader\n\nBootstrap plugin v%s loaded successfully.\n\nGate 0 device validation is ready."),
                    VERSION
                ),
            })
        end,
    }
end

return ReadwiseReader
