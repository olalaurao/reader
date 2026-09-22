-- SPDX-License-Identifier: AGPL-3.0-only

local Config = require("config")
local Constants = require("constants")
local Http = require("api/http")
local Reader = require("api/reader")
local SettingsUI = require("ui/settings")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ReadwiseReader = WidgetContainer:extend{
    name = "readwisereader",
    is_doc_only = false,
    version = Constants.VERSION,
}

function ReadwiseReader:init()
    self.config = Config:new()
    self.http = Http:new()
    self.reader_api = Reader:new{
        http = self.http,
        config = self.config,
    }
    self.settings_ui = SettingsUI:new{
        config = self.config,
        reader = self.reader_api,
    }
    self.ui.menu:registerToMainMenu(self)
end

function ReadwiseReader:addToMainMenu(menu_items)
    menu_items.readwisereader = {
        text = _("Readwise Reader"),
        sorting_hint = "more_tools",
        sub_item_table = {
            self.settings_ui:getSettingsMenu(),
        },
    }
end

function ReadwiseReader:onCloseWidget()
    if self.config then
        self.config:close()
    end
end

return ReadwiseReader
