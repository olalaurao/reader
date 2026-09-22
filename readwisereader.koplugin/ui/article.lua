-- SPDX-License-Identifier: AGPL-3.0-only

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = Device.screen

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

local function candidateItems(candidates, on_select)
    local items = {}
    for index, candidate in ipairs(candidates or {}) do
        local title = candidate.title
        if type(title) ~= "string" or title == "" then
            title = _("Untitled")
        end
        local reader_id = candidate.id
        items[index] = {
            text = title,
            mandatory = type(candidate.author) == "string" and candidate.author or nil,
            reader_id = reader_id,
            callback = on_select and function()
                on_select(reader_id)
            end or nil,
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
        -- Unlike the Gate 2 InfoMessage-only action, this flow transitions
        -- to a separate Menu after the Trapper coroutine resumes. Let the
        -- originating TouchMenu close when the callback first yields.
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

    -- Do not build/show a new complex Menu from inside the resumed Trapper
    -- coroutine. Finish this coroutine and transition UI on the next tick,
    -- matching KOReader's own menu-search pattern.
    UIManager:nextTick(function()
        self:_showCandidateMenu(candidates)
    end)
end

function ArticleUI:_showCandidateMenu(candidates)
    local ok, show_err = pcall(function()
        local container
        local menu
        local function selectArticle(reader_id)
            if container then
                UIManager:close(container)
            end
            self.candidate_menu = nil
            UIManager:nextTick(function()
                self:downloadArticle(reader_id)
            end)
        end

        menu = Menu:new{
            title = _("Choose a Reader article (Gate 3)"),
            item_table = candidateItems(candidates, selectArticle),
            width = math.floor(Screen:getWidth() * 0.94),
            height = math.floor(Screen:getHeight() * 0.94),
            single_line = true,
            close_callback = function()
                if container then
                    UIManager:close(container)
                end
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
    end)

    if not ok then
        self.candidate_menu = nil
        UIManager:show(InfoMessage:new{
            text = _("The Reader article list could not be displayed. Please retry with the updated Gate 3 build."),
        })
        local logger = require("logger")
        logger.warn("ReadwiseReader: [UI] article selector failed", tostring(show_err))
    end
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

    local ok, result, install_err = pcall(function()
        return self.coordinator:installDocument(document)
    end)
    if not ok then
        local logger = require("logger")
        logger.warn("ReadwiseReader: [DOC] Gate 3 install failed", tostring(result))
        UIManager:show(InfoMessage:new{
            text = _("The article could not be installed safely. No existing file was overwritten."),
        })
        return
    end
    if not result then
        UIManager:show(InfoMessage:new{ text = errorText(install_err) })
        return
    end

    UIManager:nextTick(function()
        local opened, open_err = pcall(function()
            self.koreader_documents:openDocument(result.path)
        end)
        if not opened then
            local logger = require("logger")
            logger.warn("ReadwiseReader: [UI] Gate 3 open failed", tostring(open_err))
            UIManager:show(InfoMessage:new{
                text = _("The article was installed, but KOReader could not open it automatically. Open it from the Readwise/Articles folder."),
            })
        end
    end)
end

ArticleUI._errorText = errorText
ArticleUI._candidateItems = candidateItems

return ArticleUI
