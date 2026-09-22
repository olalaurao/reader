-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local SettingsUI = {}
SettingsUI.__index = SettingsUI

function SettingsUI:new(options)
    return setmetatable({
        config = assert(options.config, "config is required"),
        token_dialog = nil,
    }, self)
end

function SettingsUI:getSettingsMenu()
    return {
        text = _("Settings"),
        sub_item_table = {
            {
                text = _("Account"),
                sub_item_table = {
                    {
                        text_func = function()
                            if self.config:hasAccessToken() then
                                return _("Access token: configured")
                            end
                            return _("Access token: not set")
                        end,
                        keep_menu_open = true,
                        callback = function()
                            self:showTokenDialog()
                        end,
                    },
                },
            },
        },
    }
end

function SettingsUI:showTokenDialog()
    local hint
    if self.config:hasAccessToken() then
        hint = _("Enter a new token to replace the saved token")
    else
        hint = _("Paste your Readwise access token")
    end

    self.token_dialog = MultiInputDialog:new{
        title = _("Readwise access token"),
        fields = {
            {
                text = "",
                text_type = "password",
                hint = hint,
            },
        },
        buttons = {
            {
                {
                    text = _("Clear"),
                    callback = function()
                        self.config:clearAccessToken()
                        UIManager:close(self.token_dialog)
                        UIManager:show(InfoMessage:new{
                            text = _("Saved access token cleared."),
                        })
                    end,
                },
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.token_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = self.token_dialog:getFields()
                        local ok = self.config:setAccessToken(fields[1])
                        UIManager:close(self.token_dialog)
                        if ok then
                            UIManager:show(InfoMessage:new{
                                text = _("Access token saved locally."),
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("The token was empty, so nothing was saved."),
                            })
                        end
                    end,
                },
            },
        },
    }

    UIManager:show(self.token_dialog)
    self.token_dialog:onShowKeyboard()
end

return SettingsUI
