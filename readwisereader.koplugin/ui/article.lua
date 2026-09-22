-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local ArticleUI = {}
ArticleUI.__index = ArticleUI

local function errorText(err)
    if not err then
        return _("The article operation failed safely.")
    end
    if err.kind == "auth" then
        return _("Readwise rejected the access token. Check Account settings and try again.")
    elseif err.kind == "offline" then
        return _("The network is unavailable. Turn Wi-Fi on outside the plugin and try again.")
    elseif err.kind == "timeout" then
        return _("The Reader request timed out. Try again.")
    elseif err.kind == "tls" then
        return _("A secure TLS connection to Readwise could not be established.")
    elseif err.kind == "rate_limit" then
        return _("Readwise rate limit reached. Try again later.")
    elseif err.kind == "not_found" then
        return _("That Reader article could not be found.")
    elseif err.kind == "content" then
        return _("That article does not have usable processed HTML content.")
    elseif err.kind == "exists" then
        return _("A file already exists at the safe destination and was not overwritten.")
    elseif err.kind == "io" then
        return _("The article could not be installed safely. No existing file was overwritten.")
    end
    return _("The article operation failed safely.")
end

local function candidateItems(candidates)
    local items = {}
    for _, candidate in ipairs(candidates or {}) do
        local title = candidate.title
        if type(title) ~= "string" or title == "" then
            title = _("Untitled")
        end
        items[#items + 1] = {
            text = title,
            mandatory = type(candidate.author) == "string" and candidate.author or nil,
            reader_id = candidate.id,
        }
    end
    return items
end

function ArticleUI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        coordinator = assert(options.coordinator, "coordinator is required"),
        koreader_documents = assert(options.koreader_documents, "koreader_documents is required"),
        candidate_menu = nil,
    }, self)
end

function ArticleUI:getMenuItem()
    return {
        text = _("Download one article (Gate 3)"),
        keep_menu_open = true,
        callback = function()
            self:chooseArticle()
        end,
    }
end

function ArticleUI:_preflight()
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

function ArticleUI:chooseArticle()
    if not self:_preflight() then
        return
    end
    Trapper:wrap(function()
        self:_chooseArticleWrapped()
    end)
end

function ArticleUI:_chooseArticleWrapped()
    local completed, candidates, err = Trapper:dismissableRunInSubprocess(function()
        return self.coordinator:listCandidates(100)
    end, _([[Loading Reader articles…

Tap to cancel. Only article metadata is being requested.]]))

    if not completed then
        UIManager:show(InfoMessage:new{ text = _("Article selection cancelled.") })
        return
    end
    if not candidates then
        UIManager:show(InfoMessage:new{ text = errorText(err) })
        return
    end
    if #candidates == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No top-level Reader articles were found in this page."),
        })
        return
    end

    local menu
    menu = Menu:new{
        title = _("Choose a Reader article (Gate 3)"),
        item_table = candidateItems(candidates),
        onMenuSelect = function(_, item)
            UIManager:close(menu)
            self.candidate_menu = nil
            UIManager:nextTick(function()
                self:downloadArticle(item.reader_id)
            end)
        end,
    }
    self.candidate_menu = menu
    UIManager:show(menu)
end

function ArticleUI:downloadArticle(reader_id)
    local existing_path = self.coordinator:getExistingPath(reader_id)
    if existing_path then
        self.koreader_documents:openDocument(existing_path)
        return
    end

    if not self:_preflight() then
        return
    end
    Trapper:wrap(function()
        self:_downloadArticleWrapped(reader_id)
    end)
end

function ArticleUI:_downloadArticleWrapped(reader_id)
    local completed, document, err = Trapper:dismissableRunInSubprocess(function()
        return self.coordinator:fetchDocument(reader_id)
    end, _([[Downloading processed Reader article…

Tap to cancel. The final file is installed only after the request completes successfully.]]))

    if not completed then
        UIManager:show(InfoMessage:new{
            text = _("Article download cancelled. No document was installed."),
        })
        return
    end
    if not document then
        UIManager:show(InfoMessage:new{ text = errorText(err) })
        return
    end

    local result, install_err = self.coordinator:installDocument(document)
    if not result then
        UIManager:show(InfoMessage:new{ text = errorText(install_err) })
        return
    end

    self.koreader_documents:openDocument(result.path)
end

ArticleUI._errorText = errorText
ArticleUI._candidateItems = candidateItems

return ArticleUI
