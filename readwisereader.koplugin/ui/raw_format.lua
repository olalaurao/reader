-- SPDX-License-Identifier: AGPL-3.0-only

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local RawFormatWorker = require("sync/raw_format_worker")
local _ = require("gettext")
local Screen = Device.screen

local RawFormatUI = {}
RawFormatUI.__index = RawFormatUI

local function errorText(err)
    if not err then return _("Raw format operation failed safely.") end
    if err.kind == "auth" then
        return _("Readwise rejected the access token.")
    elseif err.kind == "offline" then
        return _("The network is unavailable. Turn Wi-Fi on outside the plugin and try again.")
    elseif err.kind == "timeout" then
        return _("The Reader/raw-source request timed out. Try again.")
    elseif err.kind == "rate_limit" then
        return _("Readwise rate limit reached. Try again later.")
    elseif err.kind == "no_space" then
        return _("Not enough free space remains for this raw document.")
    elseif err.kind == "too_large" then
        return _("The original document exceeds the current raw-source safety limit.")
    elseif err.kind == "content" or err.kind == "raw_invalid" or err.kind == "raw_unavailable" then
        return _("Reader could not provide a usable original or processed fallback for this document.")
    elseif err.kind == "io" or err.kind == "sink" then
        return _("The document could not be installed safely. No existing file was overwritten.")
    end
    return _("Raw format operation failed safely.")
end

local function candidateItems(candidates, on_select)
    local items = {}
    for i, item in ipairs(candidates or {}) do
        local title = type(item.title) == "string" and item.title ~= "" and item.title or _("Untitled")
        items[i] = {
            text = title,
            mandatory = type(item.author) == "string" and item.author or nil,
            callback = function() on_select(item.id) end,
        }
    end
    return items
end

function RawFormatUI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        koreader_documents = assert(options.koreader_documents, "koreader_documents is required"),
        collections = assert(options.collections, "collections is required"),
        worker = options.worker or RawFormatWorker,
        candidate_menu = nil,
    }, self)
end

function RawFormatUI:getMenuItem()
    return {
        text = _("Test PDF / EPUB (Gate 6)"),
        sub_item_table = {
            {
                text = _("Choose one PDF"),
                callback = function() self:choose("pdf") end,
            },
            {
                text = _("Choose one EPUB"),
                callback = function() self:choose("epub") end,
            },
        },
    }
end

function RawFormatUI:_preflight()
    if not self.config:hasAccessToken() then
        UIManager:show(InfoMessage:new{ text = _("No access token is configured.") })
        return false
    end
    if not NetworkMgr:isOnline() then
        UIManager:show(InfoMessage:new{
            text = _("No internet connection. Turn Wi-Fi on outside the plugin and try again."),
        })
        return false
    end
    return true
end

function RawFormatUI:choose(category)
    if not self:_preflight() then return end
    Trapper:wrap(function()
        local completed, candidates, err = Trapper:dismissableRunInSubprocess(function()
            return self.worker:listCandidates(category)
        end, string.format(_("Loading Reader %s documents…\n\nTap to cancel."), category:upper()))

        if not completed then
            UIManager:show(InfoMessage:new{ text = _("Document selection cancelled.") })
            return
        end
        if not candidates then
            UIManager:show(InfoMessage:new{ text = errorText(err) })
            return
        end
        if #candidates == 0 then
            UIManager:show(InfoMessage:new{
                text = string.format(_("No top-level Reader %s documents were found."), category:upper()),
            })
            return
        end
        UIManager:nextTick(function()
            self:_showCandidates(category, candidates)
        end)
    end)
end

function RawFormatUI:_showCandidates(category, candidates)
    local container
    local menu
    local function selectDocument(reader_id)
        if container then UIManager:close(container) end
        self.candidate_menu = nil
        UIManager:nextTick(function()
            self:download(reader_id, category)
        end)
    end

    menu = Menu:new{
        title = string.format(_("Choose a Reader %s"), category:upper()),
        item_table = candidateItems(candidates, selectDocument),
        width = math.floor(Screen:getWidth() * 0.94),
        height = math.floor(Screen:getHeight() * 0.94),
        single_line = true,
        close_callback = function()
            if container then UIManager:close(container) end
            self.candidate_menu = nil
        end,
    }
    container = CenterContainer:new{
        dimen = Screen:getSize(),
        menu,
    }
    menu.show_parent = container
    self.candidate_menu = container
    UIManager:show(container)
end

function RawFormatUI:download(reader_id, category)
    if not self:_preflight() then return end
    Trapper:wrap(function()
        local completed, result, err = Trapper:dismissableRunInSubprocess(function()
            return self.worker:run(reader_id, category)
        end, string.format(
            _([[Downloading Reader %s…

Tap to cancel. Original raw source is preferred; a usable processed HTML fallback is allowed.]]),
            category:upper()
        ))

        if not completed then
            UIManager:show(InfoMessage:new{
                text = _("Raw document download cancelled. Incomplete temporary files are not kept."),
            })
            return
        end
        if not result then
            UIManager:show(InfoMessage:new{ text = errorText(err) })
            return
        end

        if result.raw_fallback_used then
            UIManager:show(InfoMessage:new{
                text = string.format(
                    _("Reader did not provide a usable original %s for this item. A readable HTML fallback was installed instead. Choose a different %s to validate Gate 6 original-format support."),
                    category:upper(),
                    category:upper()
                ),
            })
            return
        end

        if result.metadata then
            pcall(
                self.koreader_documents.writeMetadata,
                self.koreader_documents,
                result.metadata.path,
                result.metadata.metadata
            )
        end
        if result.location then
            pcall(
                self.collections.syncLocation,
                self.collections,
                result.path,
                result.location
            )
        end

        UIManager:nextTick(function()
            local opened = pcall(
                self.koreader_documents.openDocument,
                self.koreader_documents,
                result.path
            )
            if not opened then
                UIManager:show(InfoMessage:new{
                    text = _("The document was installed, but KOReader could not open it automatically."),
                })
            end
        end)
    end)
end

RawFormatUI._errorText = errorText
RawFormatUI._candidateItems = candidateItems

return RawFormatUI
