-- SPDX-License-Identifier: AGPL-3.0-only

local ImageSpike = require("content/image_spike")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local ImageSpikeUI = {}
ImageSpikeUI.__index = ImageSpikeUI

function ImageSpikeUI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        installer = assert(options.installer, "installer is required"),
        koreader_documents = assert(options.koreader_documents, "koreader_documents is required"),
    }, self)
end

function ImageSpikeUI:getMenuItem()
    return {
        text = _("Image asset spike (Gate 5)"),
        keep_menu_open = true,
        callback = function()
            self:run()
        end,
    }
end

function ImageSpikeUI:_paths()
    local root = self.config:getDownloadDirectory()
    local diagnostics = root .. "/Diagnostics"
    local asset_dir = diagnostics .. "/" .. ImageSpike.ASSET_DIRNAME
    return {
        html = diagnostics .. "/" .. ImageSpike.HTML_FILENAME,
        asset = asset_dir .. "/" .. ImageSpike.ASSET_FILENAME,
    }
end

function ImageSpikeUI:_ensure(path, content)
    if self.installer:fileExists(path) then return true end
    local result, err = self.installer:install(content, path)
    if result then return true end
    return nil, err
end

function ImageSpikeUI:run()
    local paths = self:_paths()

    local asset_ok, asset_err = self:_ensure(paths.asset, ImageSpike.svg())
    if not asset_ok then
        UIManager:show(InfoMessage:new{
            text = _("Could not install the Gate 5 local image asset: ")
                .. tostring(asset_err and asset_err.message or _("unknown error")),
        })
        return
    end

    local html_ok, html_err = self:_ensure(paths.html, ImageSpike.html())
    if not html_ok then
        UIManager:show(InfoMessage:new{
            text = _("Could not install the Gate 5 diagnostic HTML: ")
                .. tostring(html_err and html_err.message or _("unknown error")),
        })
        return
    end

    UIManager:nextTick(function()
        local ok, err = pcall(
            self.koreader_documents.openDocument,
            self.koreader_documents,
            paths.html
        )
        if not ok then
            UIManager:show(InfoMessage:new{
                text = _("The Gate 5 diagnostic files were installed, but KOReader could not open the HTML: ")
                    .. tostring(err),
            })
        end
    end)
end

ImageSpikeUI._ImageSpike = ImageSpike

return ImageSpikeUI
