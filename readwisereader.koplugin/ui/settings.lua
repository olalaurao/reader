-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local SettingsUI = {}
SettingsUI.__index = SettingsUI

function SettingsUI:new(options)
    return setmetatable({
        config = assert(options.config, "config is required"),
        reader = assert(options.reader, "reader is required"),
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
                    {
                        text = _("Test connection"),
                        keep_menu_open = true,
                        callback = function()
                            self:testConnection()
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

function SettingsUI:testConnection()
    if not self.config:hasAccessToken() then
        UIManager:show(InfoMessage:new{
            text = _("No access token is configured."),
        })
        return
    end

    -- Deliberately do not call runWhenOnline/beforeWifiAction: V1 never toggles Wi-Fi.
    if not NetworkMgr:isOnline() then
        UIManager:show(InfoMessage:new{
            text = _("No internet connection. Turn Wi-Fi on outside the plugin and try again."),
        })
        return
    end

    local ok, err = self.reader:validateToken()
    if ok then
        UIManager:show(InfoMessage:new{
            text = _("Connected to Readwise successfully."),
        })
        return
    end

    local text
    if err and err.kind == "auth" then
        text = _("Readwise rejected the access token. Replace it and try again.")
    elseif err and err.kind == "timeout" then
        text = _("The Readwise connection timed out. Try again.")
    elseif err and err.kind == "tls" then
        text = _("A secure TLS connection to Readwise could not be established.")
    elseif err and err.kind == "rate_limit" then
        text = _("Readwise rate limit reached. Try again later.")
    elseif err and err.kind == "offline" then
        text = _("The network is unavailable. Check Wi-Fi and try again.")
    elseif err and err.kind == "server" then
        text = _("Readwise reported a server error. Try again later.")
    else
        text = _("Could not validate the Readwise connection.")
    end

    UIManager:show(InfoMessage:new{ text = text })
end

return SettingsUI
