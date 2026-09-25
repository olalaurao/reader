-- SPDX-License-Identifier: AGPL-3.0-only

local ConfirmBox = require("ui/widget/confirmbox")
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
        download_dialog = nil,
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
            {
                text = _("Highlights"),
                sub_item_table = {
                    {
                        text = _("Propagate highlight deletions"),
                        keep_menu_open = true,
                        checked_func = function()
                            return self.config:getPropagateHighlightDeletions()
                        end,
                        callback = function()
                            if self.config:getPropagateHighlightDeletions() then
                                self.config:setPropagateHighlightDeletions(false)
                                return
                            end
                            UIManager:show(ConfirmBox:new{
                                text = _([[Enable remote highlight deletion?

When enabled, deleting a linked KOReader highlight can delete that exact linked highlight from Readwise Reader during Sync now.

This is destructive. The plugin still verifies the remote child ID, parent document and KOReader marker before deleting.]]),
                                ok_text = _("Enable"),
                                ok_callback = function()
                                    self.config:setPropagateHighlightDeletions(true)
                                end,
                            })
                        end,
                    },
                },
            },
            {
                text = _("Finished documents"),
                sub_item_table = {
                    {
                        text = _("Archive in Reader"),
                        keep_menu_open = true,
                        checked_func = function()
                            return self.config:getArchiveFinished()
                        end,
                        callback = function()
                            self.config:setArchiveFinished(
                                not self.config:getArchiveFinished()
                            )
                        end,
                    },
                },
            },
            {
                text = _("Documents"),
                sub_item_table = {
                    {
                        text_func = function()
                            return _("Download folder: ") .. self.config:getDownloadDirectory()
                        end,
                        keep_menu_open = true,
                        callback = function()
                            self:showDownloadDirectoryDialog()
                        end,
                    },
                    {
                        text = _("Locations"),
                        sub_item_table = {
                            {
                                text = _("Inbox"),
                                checked_func = function()
                                    return self.config:isSyncLocationEnabled("new")
                                end,
                                callback = function()
                                    self.config:setSyncLocationEnabled(
                                        "new",
                                        not self.config:isSyncLocationEnabled("new")
                                    )
                                end,
                            },
                            {
                                text = _("Later"),
                                checked_func = function()
                                    return self.config:isSyncLocationEnabled("later")
                                end,
                                callback = function()
                                    self.config:setSyncLocationEnabled(
                                        "later",
                                        not self.config:isSyncLocationEnabled("later")
                                    )
                                end,
                            },
                            {
                                text = _("Shortlist"),
                                checked_func = function()
                                    return self.config:isSyncLocationEnabled("shortlist")
                                end,
                                callback = function()
                                    self.config:setSyncLocationEnabled(
                                        "shortlist",
                                        not self.config:isSyncLocationEnabled("shortlist")
                                    )
                                end,
                            },
                            {
                                text = _("Feed"),
                                checked_func = function()
                                    return self.config:isSyncLocationEnabled("feed")
                                end,
                                callback = function()
                                    self.config:setSyncLocationEnabled(
                                        "feed",
                                        not self.config:isSyncLocationEnabled("feed")
                                    )
                                end,
                            },
                            {
                                text = _("Archive"),
                                checked_func = function()
                                    return self.config:isSyncLocationEnabled("archive")
                                end,
                                callback = function()
                                    self.config:setSyncLocationEnabled(
                                        "archive",
                                        not self.config:isSyncLocationEnabled("archive")
                                    )
                                end,
                            },
                        },
                    },
                    {
                        text = _("Download article images"),
                        checked_func = function()
                            return self.config:getDownloadImages()
                        end,
                        callback = function()
                            self.config:setDownloadImages(
                                not self.config:getDownloadImages()
                            )
                        end,
                    },
                    {
                        text = _("Types"),
                        sub_item_table = {
                            {
                                text = _("Articles"),
                                checked_func = function()
                                    return self.config:isSyncCategoryEnabled("article")
                                end,
                                callback = function()
                                    self.config:setSyncCategoryEnabled(
                                        "article",
                                        not self.config:isSyncCategoryEnabled("article")
                                    )
                                end,
                            },
                            {
                                text = _("Email / newsletters"),
                                checked_func = function()
                                    return self.config:isSyncCategoryEnabled("email")
                                end,
                                callback = function()
                                    self.config:setSyncCategoryEnabled(
                                        "email",
                                        not self.config:isSyncCategoryEnabled("email")
                                    )
                                end,
                            },
                            {
                                text = _("RSS"),
                                checked_func = function()
                                    return self.config:isSyncCategoryEnabled("rss")
                                end,
                                callback = function()
                                    self.config:setSyncCategoryEnabled(
                                        "rss",
                                        not self.config:isSyncCategoryEnabled("rss")
                                    )
                                end,
                            },
                            {
                                text = _("PDF"),
                                checked_func = function()
                                    return self.config:isSyncCategoryEnabled("pdf")
                                end,
                                callback = function()
                                    self.config:setSyncCategoryEnabled(
                                        "pdf",
                                        not self.config:isSyncCategoryEnabled("pdf")
                                    )
                                end,
                            },
                            {
                                text = _("EPUB"),
                                checked_func = function()
                                    return self.config:isSyncCategoryEnabled("epub")
                                end,
                                callback = function()
                                    self.config:setSyncCategoryEnabled(
                                        "epub",
                                        not self.config:isSyncCategoryEnabled("epub")
                                    )
                                end,
                            },
                            {
                                text = _("Tweets"),
                                checked_func = function()
                                    return self.config:isSyncCategoryEnabled("tweet")
                                end,
                                callback = function()
                                    self.config:setSyncCategoryEnabled(
                                        "tweet",
                                        not self.config:isSyncCategoryEnabled("tweet")
                                    )
                                end,
                            },
                            {
                                text = _("Videos"),
                                checked_func = function()
                                    return self.config:isSyncCategoryEnabled("video")
                                end,
                                callback = function()
                                    self.config:setSyncCategoryEnabled(
                                        "video",
                                        not self.config:isSyncCategoryEnabled("video")
                                    )
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
end


function SettingsUI:showDownloadDirectoryDialog()
    self.download_dialog = MultiInputDialog:new{
        title = _("Readwise download folder"),
        fields = {
            {
                text = self.config:getDownloadDirectory(),
                hint = _("/mnt/us/documents/Readwise"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.download_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = self.download_dialog:getFields()
                        local ok, err = self.config:setDownloadDirectory(fields[1])
                        UIManager:close(self.download_dialog)
                        if ok then
                            UIManager:show(InfoMessage:new{
                                text = _("Download folder saved."),
                            })
                        elseif err == "unsafe" then
                            UIManager:show(InfoMessage:new{
                                text = _("Use a folder inside /mnt/us/documents/."),
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("The download folder was empty, so nothing was saved."),
                            })
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(self.download_dialog)
    self.download_dialog:onShowKeyboard()
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
