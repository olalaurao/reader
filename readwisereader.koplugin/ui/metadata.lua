-- SPDX-License-Identifier: AGPL-3.0-only

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Tags = require("metadata/tags")
local AnnotationIdentity = require("sync/annotation_identity")
local _ = require("gettext")
local Screen = Device.screen

local MetadataUI = {}
MetadataUI.__index = MetadataUI

local function normalizedNote(value)
    if value == nil then return "" end
    return tostring(value):gsub("\r\n", "\n"):gsub("\r", "\n")
end

local function trim(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value == "" then return nil end
    return value
end

local function asSet(values)
    local out = {}
    for _, value in ipairs(Tags.normalize(values)) do out[value] = true end
    return out
end

function MetadataUI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        reader = assert(options.reader, "reader is required"),
        documents = assert(options.documents, "documents repository is required"),
        annotations = assert(options.annotations, "annotations repository is required"),
        annotation_metadata = assert(options.annotation_metadata, "annotation metadata repository is required"),
        remote_highlights = assert(options.remote_highlights, "remote highlight repository is required"),
        queue = assert(options.queue, "queue repository is required"),
        mutations = assert(options.mutations, "metadata mutations is required"),
        adapter = assert(options.adapter, "annotation adapter is required"),
        get_current_path = assert(options.get_current_path, "get_current_path is required"),
        get_reader_ui = assert(options.get_reader_ui, "get_reader_ui is required"),
        active_menu = nil,
        active_dialog = nil,
    }, self)
end

function MetadataUI:_currentDocument()
    local path = self.get_current_path()
    if type(path) ~= "string" or path == "" then return nil end
    local document = self.documents:getByLocalPath(path)
    if not document or document.is_managed ~= true then return nil end
    return document
end

function MetadataUI:getMenuItem()
    return {
        text = _("Reader metadata"),
        enabled_func = function() return self:_currentDocument() ~= nil end,
        callback = function() self:editCurrentDocument() end,
    }
end

function MetadataUI:_fetchRemote(reader_id)
    if not self.config:hasAccessToken() then return nil end
    local remote
    Trapper:wrap(function()
        local completed, value = Trapper:dismissableRunInSubprocess(function()
            return self.reader:getDocument(reader_id, false, false)
        end, _([[Refreshing Reader metadataâ€¦

Tap to cancel. This is a read-only request.]]))
        if completed then remote = value end
    end)
    return remote
end

function MetadataUI:_fetchTagNames()
    if not self.config:hasAccessToken() then return {} end
    local names = {}
    Trapper:wrap(function()
        local completed, value = Trapper:dismissableRunInSubprocess(function()
            local result, cursor, seen = {}, nil, {}
            while true do
                local page, page_err = self.reader:listTags{ page_cursor = cursor }
                if not page then return nil, page_err end
                for _, tag in ipairs(page.results or {}) do
                    if type(tag.name) == "string" and tag.name ~= "" and not seen[tag.name] then
                        seen[tag.name] = true
                        result[#result + 1] = tag.name
                    end
                end
                cursor = page.next_page_cursor
                if cursor == nil then break end
            end
            table.sort(result)
            return result
        end, _([[Loading Reader tagsâ€¦

Tap to cancel. This is a read-only request.]]))
        if completed and type(value) == "table" then names = value end
    end)
    return names
end

function MetadataUI:_closeActiveMenu()
    if self.active_menu then
        UIManager:close(self.active_menu)
        self.active_menu = nil
    end
end

function MetadataUI:_showDocumentActions(document, pending)
    self:_closeActiveMenu()
    local container
    local menu
    local items = {
        {
            text = _("Document tags"),
            mandatory = pending.tags_pending and _("queued") or Tags.display(pending.tags),
            callback = function()
                if container then UIManager:close(container) end
                self.active_menu = nil
                self:editDocumentTags(document, pending)
            end,
        },
        {
            text = _("Document note"),
            mandatory = pending.note_status == "blocked" and _("conflict")
                or (pending.note_pending and _("queued") or nil),
            callback = function()
                if container then UIManager:close(container) end
                self.active_menu = nil
                self:editDocumentNote(document, pending)
            end,
        },
    }
    menu = Menu:new{
        title = _("Reader metadata"),
        item_table = items,
        width = math.floor(Screen:getWidth() * 0.94),
        height = math.floor(Screen:getHeight() * 0.60),
        single_line = false,
        close_callback = function()
            if container then UIManager:close(container) end
            self.active_menu = nil
        end,
    }
    container = CenterContainer:new{ dimen = Screen:getSize(), menu }
    menu.show_parent = container
    self.active_menu = container
    UIManager:show(container)
end

function MetadataUI:editCurrentDocument()
    local document = self:_currentDocument()
    if not document then
        UIManager:show(InfoMessage:new{ text = _("The current document is not managed by Readwise Reader.") })
        return
    end

    local remote = self:_fetchRemote(document.reader_id)
    if remote then
        self.documents:upsertRemote(remote, os.time())
        document = self.documents:getById(document.reader_id) or document
    end
    local pending = self.mutations:getPendingDocumentState(document)
    self:_showDocumentActions(document, pending)
end

function MetadataUI:editDocumentNote(document, pending)
    local dialog
    local buttons = {
        {
            {
                text = _("Cancel"), id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = pending.note_status == "blocked" and _("Keep Kindle") or _("Save for Sync"),
                is_enter_default = true,
                callback = function()
                    local desired = normalizedNote(dialog:getInputText())
                    UIManager:close(dialog)
                    self.active_dialog = nil
                    if pending.note_status ~= "blocked" and normalizedNote(pending.note) == desired then
                        UIManager:show(InfoMessage:new{ text = _("No Reader document-note change to queue.") })
                        return
                    end
                    local queued, err = self.mutations:queueDocumentNote(document, desired)
                    if not queued then
                        UIManager:show(InfoMessage:new{
                            text = err and err.message or _("The Reader document-note change could not be queued safely."),
                        })
                        return
                    end
                    UIManager:show(InfoMessage:new{
                        text = pending.note_status == "blocked"
                            and _("Kindle note kept and rebased on the current Reader version. Run Sync now to apply it.")
                            or (desired == ""
                                and _("Reader document-note removal queued. Run Sync now when you want to send it.")
                                or _("Reader document-note change queued. Run Sync now when you want to send it.")),
                    })
                end,
            },
        },
    }
    if pending.note_status == "blocked" then
        buttons[#buttons + 1] = {
            {
                text = _("Use Reader version"),
                callback = function()
                    UIManager:close(dialog)
                    self.active_dialog = nil
                    self.mutations:cancelDocumentEdit(document, "note")
                    UIManager:show(InfoMessage:new{
                        text = _("Kindle note edit discarded. The current Reader note was kept."),
                    })
                end,
            },
        }
    end
    dialog = InputDialog:new{
        title = pending.note_status == "blocked"
            and _("Reader document note â€” ½¹™±¥Ğˆ¤½È| ‰I•…‘•È‘½Õµ•¹Ğ¹½Ñ”ˆ¤°(€€€€€€€¥¹ÁÕĞ€ôÁ•¹‘¥¹œ¹¹½Ñ”½È€ˆˆ°(€€€€€€€…±±½İ}¹•İ±¥¹”€ôÑÉÕ”°(€€€€€€€‰ÕÑÑ½¹Ì€ô‰ÕÑÑ½¹Ì°(€€€ô(€€€Í•±˜¹…Ñ¥Ù•}‘¥…±½œ€ô‘¥…±½œ(€€€U%5…¹…•ÈéÍ¡½Ü¡‘¥…±½œ¤(€€€‘¥…±½œé½¹M¡½İ-•å‰½…É ¤)•¹()™Õ¹Ñ¥½¸5•Ñ…‘…Ñ…U$é}Í¡½İQ…%¹ÁÕĞ¡Ñ¥Ñ±”°¥¹ÁÕÑ}Ñ¥Ñ±”°¥¹¥Ñ¥…°°…±±‰…¬¤(€€€±½…°‘¥…±½œ(€€€‘¥…±½œ€ô%¹ÁÕÑ¥…±½œé¹•İì(€€€€€€€Ñ¥Ñ±”€ô¥¹ÁÕÑ}Ñ¥Ñ±”°(€€€€€€€¥¹ÁÕĞ€ô¥¹¥Ñ¥…°½È€ˆˆ°(€€€€€€€‰ÕÑÑ½¹Ì€ôì(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€ì(€€€€€€€€€€€€€€€€€€€Ñ•áĞ€ô| ‰…¹•°ˆ¤°¥€ô€‰±½Í”ˆ°(€€€€€€€€€€€€€€€€€€€…±±‰…¬€ô™Õ¹Ñ¥½¸ ¤U%5…¹…•Èé±½Í”¡‘¥…±½œ¤•¹°(€€€€€€€€€€€€€€€ô°(€€€€€€€€€€€€€€€ì(€€€€€€€€€€€€€€€€€€€Ñ•áĞ€ô| ‰=,ˆ¤°¥Í}•¹Ñ•É}‘•™…Õ±Ğ€ôÑÉÕ”°(€€€€€€€€€€€€€€€€€€€…±±‰…¬€ô™Õ¹Ñ¥½¸ ¤(€€€€€€€€€€€€€€€€€€€€€€€±½…°Ù…±Õ”€ô‘¥…±½œé•Ñ%¹ÁÕÑQ•áĞ ¤(€€€€€€€€€€€€€€€€€€€€€€€U%5…¹…•Èé±½Í”¡‘¥…±½œ¤(€€€€€€€€€€€€€€€€€€€€€€€Í•±˜¹…Ñ¥Ù•}‘¥…±½œ€ô¹¥°(€€€€€€€€€€€€€€€€€€€€€€€…±±‰…¬¡Ù…±Õ”¤(€€€€€€€€€€€€€€€€€€€•¹°(€€€€€€€€€€€€€€€ô°(€€€€€€€€€€€ô°(€€€€€€€ô°(€€€ô(€€€Í•±˜¹…Ñ¥Ù•}‘¥…±½œ€ô‘¥…±½œ(€€€U%5…¹…•ÈéÍ¡½Ü¡‘¥…±½œ¤(€€€‘¥…±½œé½¹M¡½İ-•å‰½…É ¤)•¹()™Õ¹Ñ¥½¸5•Ñ…‘…Ñ…U$é}Í¡½İQ…A¥­•È¡½ÁÑ¥½¹Ì¤(€€€½ÁÑ¥½¹Ì€ô½ÁÑ¥½¹Ì½Èíô(€€€±½…°Í•±•Ñ•€ô…ÍM•Ğ¡½ÁÑ¥½¹Ì¹Í•±•Ñ•¤(€€€±½…°…Ù…¥±…‰±•}Í•Ğ€ô…ÍM•Ğ¡½ÁÑ¥½¹Ì¹…Ù…¥±…‰±”¤(€€€™½ÈÑ…œ¥¸Á…¥ÉÌ¡Í•±•Ñ•¤‘¼…Ù…¥±…‰±•}Í•ÑmÑ…t€ôÑÉÕ”•¹(€€€±½…°™¥±Ñ•È€ôÑÉ¥´¡½ÁÑ¥½¹Ì¹™¥±Ñ•È¤(€€€±½…°½¹Ñ…¥¹•È(€€€±½…°µ•¹Ô((€€€±½…°™Õ¹Ñ¥½¸Í•±•Ñ•‘1¥ÍĞ ¤(€€€€€€€±½…°½ÕĞ€ôíô(€€€€€€€™½ÈÑ…œ°•¹…‰±•¥¸Á…¥ÉÌ¡Í•±•Ñ•¤‘¼(€€€€€€€€€€€¥˜•¹…‰±•Ñ¡•¸½ÕÑl½ÕĞ€¬€Åt€ôÑ…œ•¹(€€€€€€€•¹(€€€€€€€Ñ…‰±”¹Í½ÉĞ¡½ÕĞ¤(€€€€€€€É•ÑÕÉ¸½ÕĞ(€€€•¹((€€€±½…°™Õ¹Ñ¥½¸…±±1¥ÍĞ ¤(€€€€€€€±½…°½ÕĞ€ôíô(€€€€€€€™½ÈÑ…œ¥¸Á…¥ÉÌ¡…Ù…¥±…‰±•}Í•Ğ¤‘¼½ÕÑl½ÕĞ€¬€Åt€ôÑ…œ•¹(€€€€€€€Ñ…‰±”¹Í½ÉĞ¡½ÕĞ¤(€€€€€€€É•ÑÕÉ¸½ÕĞ(€€€•¹((€€€±½…°™Õ¹Ñ¥½¸±½Í•5•¹Ô ¤(€€€€€€€¥˜½¹Ñ…¥¹•ÈÑ¡•¸U%5…¹…•Èé±½Í”¡½¹Ñ…¥¹•È¤•¹(€€€€€€€¥˜Í•±˜¹…Ñ¥Ù•}µ•¹Ô€ôô½¹Ñ…¥¹•ÈÑ¡•¸Í•±˜¹…Ñ¥Ù•}µ•¹Ô€ô¹¥°•¹(€€€•¹((€€€±½…°™Õ¹Ñ¥½¸É•‰Õ¥±¡¹•İ}™¥±Ñ•È¤(€€€€€€€±½Í•5•¹Ô ¤(€€€€€€€U%5…¹…•Èé¹•áÑQ¥¬¡™Õ¹Ñ¥½¸ ¤(€€€€€€€€€€€Í•±˜é}Í¡½İQ…A¥­•Éì(€€€€€€€€€€€€€€€Ñ¥Ñ±”€ô½ÁÑ¥½¹Ì¹Ñ¥Ñ±”°(€€€€€€€€€€€€€€€Í•±•Ñ•€ôÍ•±•Ñ•‘1¥ÍĞ ¤°(€€€€€€€€€€€€€€€…Ù…¥±…‰±”€ô…±±1¥ÍĞ ¤°(€€€€€€€€€€€€€€€™¥±Ñ•È€ô¹•İ}™¥±Ñ•È°(€€€€€€€€€€€€€€€½¹}Í…Ù”€ô½ÁÑ¥½¹Ì¹½¹}Í…Ù”°(€€€€€€€€€€€ô(€€€€€€€•¹¤(€€€•¹((€€€±½…°¥Ñ•µÌ€ôì(€€€€€€€ì(€€€€€€€€€€€Ñ•áĞ€ô| ‰M…Ù”Ñ…Ìˆ¤°(€€€€€€€€€€€µ…¹‘…Ñ½Éä€ôÍÑÉ¥¹œ¹™½Éµ…Ğ¡| ˆ•Í•±•Ñ•ˆ¤°€Í•±•Ñ•‘1¥ÍĞ ¤¤°(€€€€€€€€€€€…±±‰…¬€ô™Õ¹Ñ¥½¸ ¤(€€€€€€€€€€€€€€€±½…°É•ÍÕ±Ğ€ôÍ•±•Ñ•‘1¥ÍĞ ¤(€€€€€€€€€€€€€€€±½Í•5•¹Ô ¤(€€€€€€€€€€€€€€€½ÁÑ¥½¹Ì¹½¹}Í…Ù”¡É•ÍÕ±Ğ¤(€€€€€€€€€€€•¹°(€€€€€€€ô°(€€€€€€€ì(€€€€€€€€€€€Ñ•áĞ€ô™¥±Ñ•È…¹| ‰¡…¹”Ñ…œÍ•…É£‹Š˜¤½È| ‰M•…É •á¥ÍÑ¥¹œÑ…ÏŠ˜ˆ¤°(€€€€€€€€€€€µ…¹‘…Ñ½Éä€ô™¥±Ñ•È°(€€€€€€€€€€€…±±‰…¬€ô™Õ¹Ñ¥½¸ ¤(€€€€€€€€€€€€€€€±½Í•5•¹Ô ¤(€€€€€€€€€€€€€€€Í•±˜é}Í¡½İQ…%¹ÁÕĞ¡½ÁÑ¥½¹Ì¹Ñ¥Ñ±”°| ‰M•…É I•…‘•ÈÑ…Ìˆ¤°™¥±Ñ•È½È€ˆˆ°™Õ¹Ñ¥½¸¡Ù…±Õ”¤(€€€€€€€€€€€€€€€€€€€É•‰Õ¥±¡ÑÉ¥´¡Ù…±Õ”¤¤(€€€€€€€€€€€€€€€•¹¤(€€€€€€€€€€€•¹°(€€€€€€€ô°(€€€€€€€ì(€€€€€€€€€€€Ñ•áĞ€ô| ‰‘¹•ÜÑ…ŸŠ˜ˆ¤°(€€€€€€€€€€€…±±‰…¬€ô™Õ¹Ñ¥½¸ ¤(€€€€€€€€€€€€€€€±½Í•5•¹Ô ¤(€€€€€€€€€€€€€€€Í•±˜é}Í¡½İQ…%¹ÁÕĞ¡½ÁÑ¥½¹Ì¹Ñ¥Ñ±”°| ‰9•ÜI•…‘•ÈÑ…œˆ¤°€ˆˆ°™Õ¹Ñ¥½¸¡Ù…±Õ”¤(€€€€€€€€€€€€€€€€€€€±½…°Ñ…œ€ôÑÉ¥´¡Ù…±Õ”¤(€€€€€€€€€€€€€€€€€€€¥˜Ñ…œÑ¡•¸(€€€€€€€€€€€€€€€€€€€€€€€…Ù…¥±…‰±•}Í•ÑmÑ…t€ôÑÉÕ”(€€€€€€€€€€€€€€€€€€€€€€€Í•±•Ñ•‘mÑ…t€ôÑÉÕ”(€€€€€€€€€€€€€€€€€€€•¹(€€€€€€€€€€€€€€€€€€€É•‰Õ¥±¡™¥±Ñ•È¤(€€€€€€€€€€€€€€€•¹¤(€€€€€€€€€€€•¹°(€€€€€€€€€€€Í•Á…É…Ñ½È€ôÑÉÕ”°(€€€€€€€ô°(€€€ô((€€€±½…°±½İ•É}™¥±Ñ•È€ô™¥±Ñ•È…¹™¥±Ñ•Èé±½İ•È ¤½È¹¥°(€€€±½…°Ù¥Í¥‰±”€ô€À(€€€™½È|°Ñ…œ¥¸¥Á…¥ÉÌ¡…±±1¥ÍĞ ¤¤‘¼(€€€€€€€¥˜¹½Ğ±½İ•É}™¥±Ñ•È½ÈÑ…œé±½İ•È ¤é™¥¹¡±½İ•É}™¥±Ñ•È°€Ä°ÑÉÕ”¤Ñ¡•¸(€€€€€€€€€€€Ù¥Í¥‰±”€ôÙ¥Í¥‰±”€¬€Ä(€€€€€€€€€€€¥Ñ•µÍl¥Ñ•µÌ€¬€Åt€ôì(€€€€€€€€€€€€€€€Ñ•áĞ€ôÑ…œ°(€€€€€€€€€€€€€€€¡•­•‘}™Õ¹Œ€ô™Õ¹Ñ¥½¸ ¤É•ÑÕÉ¸Í•±•Ñ•‘mÑ…t€ôôÑÉÕ”•¹°(€€€€€€€€€€€€€€€­••Á}µ•¹Õ}½Á•¸€ôÑÉÕ”°(€€€€€€€€€€€€€€€…±±‰…¬€ô™Õ¹Ñ¥½¸¡Ñ½Õ¡µ•¹Õ}¥¹ÍÑ…¹”¤(€€€€€€€€€€€€€€€€€€€Í•±•Ñ•‘mÑ…t€ô¹½ĞÍ•±•Ñ•‘mÑ…t(€€€€€€€€€€€€€€€€€€€¥˜Ñ½Õ¡µ•¹Õ}¥¹ÍÑ…¹”…¹Ñ½Õ¡µ•¹Õ}¥¹ÍÑ…¹”¹ÕÁ‘…Ñ•%Ñ•µÌÑ¡•¸(€€€€€€€€€€€€€€€€€€€€€€€Ñ½Õ¡µ•¹Õ}¥¹ÍÑ…¹”éÕÁ‘…Ñ•%Ñ•µÌ ¤(€€€€€€€€€€€€€€€€€€€•±Í•¥˜µ•¹Ô…¹µ•¹Ô¹ÕÁ‘…Ñ•%Ñ•µÌÑ¡•¸(€€€€€€€€€€€€€€€€€€€€€€€µ•¹ÔéÕÁ‘…Ñ•%Ñ•µÌ ¤(€€€€€€€€€€€€€€€€€€€•¹(€€€€€€€€€€€€€€€•¹°(€€€€€€€€€€€ô(€€€€€€€•¹(€€€•¹(€€€¥˜Ù¥Í¥‰±”€ôô€ÀÑ¡•¸(€€€€€€€¥Ñ•µÍl¥Ñ•µÌ€¬€Åt€ôì(€€€€€€€€€€€Ñ•áĞ€ô™¥±Ñ•È…¹| ‰9¼•á¥ÍÑ¥¹œÑ…Ìµ…Ñ Ñ¡¥ÌÍ•…É ¸ˆ¤½È| ‰9¼•á¥ÍÑ¥¹œI•…‘•ÈÑ…Ìİ•É”±½…‘•¸ˆ¤°(€€€€€€€€€€€•¹…‰±•€ô™…±Í”°(€€€€€€€ô(€€€•¹((€€€µ•¹Ô€ô5•¹Ôé¹•İì(€€€€€€€Ñ¥Ñ±”€ô½ÁÑ¥½¹Ì¹Ñ¥Ñ±”½È| ‰I•…‘•ÈÑ…Ìˆ¤°(€€€€€€€¥Ñ•µ}Ñ…‰±”€ô¥Ñ•µÌ‹ˆÚYHX]™›ÛÜŠØÜ™Y[™Ù]ÚY

H
ˆM
KˆZYÚHX]™›ÛÜŠØÜ™Y[™Ù]ZYÚ

H
ˆM
KˆÚ[™ÛWÛ[™HH˜[ÙKˆÛÜÙWØØ[˜XÚÈH[˜İ[ÛŠ
BˆYˆÛÛZ[™\ˆ[ˆRSX[˜YÙ\˜ÛÜÙJÛÛZ[™\ŠH[™ˆÙ[‹˜Xİ]™WÛY[HHš[ˆ[™ˆBˆÛÛZ[™\ˆHÙ[\ÛÛZ[™\›™]ŞÈ[Y[ˆHØÜ™Y[™Ù]Ú^™J
KY[HBˆY[KœÚİ×Ü\™[HÛÛZ[™\‚ˆÙ[‹˜Xİ]™WÛY[HHÛÛZ[™\‚ˆRSX[˜YÙ\œÚİÊÛÛZ[™\ŠB™[™‚™[˜İ[ÛˆY]Y]URN™Y]Øİ[Y[YÜÊØİ[Y[[™[™ÊBˆØØ[]˜Z[X›HHÙ[—Ù™]ÚYÓ˜[Y\Ê
BˆÙ[—ÜÚİÕYÔXÚÙ\Âˆ]HHÊ”™XY\ˆØİ[Y[YÜÈŠKˆÙ[XİYH[™[™ËYÜËˆ]˜Z[X›HH]˜Z[X›KˆÛ—ÜØ]™HH[˜İ[ÛŠYÜÊBˆYˆYÜË™\]X[
[™[™ËYÜËYÜÊH[‚ˆRSX[˜YÙ\œÚİÊ[™›ÓY\ÜØYÙN›™]ŞÈ^HÊ“›È™XY\ˆØİ[Y[]YÈÚ[™Ù\ÈÈ]Y]YKˆŠHJBˆ™]\›‚ˆ[™ˆØØ[]Y]YY\œˆHÙ[‹›]]][ÛœÎœ]Y]YQØİ[Y[YÜÊØİ[Y[YÜÊBˆYˆ›İ]Y]YY[‚ˆRSX[˜YÙ\œÚİÊ[™›ÓY\ÜØYÙN›™]ŞÂˆ^H\œˆ[™\œ‹›Y\ÜØYÙHÜˆÊ•H™XY\ˆØİ[Y[]YÈÚ[™ÙHÛİ[›İ™H]Y]YYØY™[KˆŠKˆJBˆ™]\›‚ˆ[™ˆRSX[˜YÙ\œÚİÊ[™›ÓY\ÜØYÙN›™]ŞÂˆ^HÊ”™XY\ˆØİ[Y[YÜÈ]Y]YYˆ[ˆŞ[˜È›İÈÚ[ˆ[İHØ[ÈÙ[™[KˆŠKˆJBˆ[™ˆB™[™‚™[˜İ[ÛˆY]Y]URN—Ü™\ÛÛ™P[››İ][ÛŠ[™^
BˆØØ[Øİ[Y[HÙ[—Øİ\œ™[Øİ[Y[

BˆØØ[™XY\—İZHHÙ[‹™Ù]Ü™XY\—İZJ
BˆØØ[[››İ][ÛˆH™XY\—İZH[™™XY\—İZK˜[››İ][Û‚ˆ[™™XY\—İZK˜[››İ][Û‹˜[››İ][ÛœÂˆ[™™XY\—İZK˜[››İ][Û‹˜[››İ][ÛœÖÚ[™^HÜˆš[ˆYˆ›İØİ[Y[Üˆ›İ[››İ][ÛˆÜˆ[››İ][Û‹™˜]Ù\ˆOHš[[ˆ™]\›ˆš[[™ˆØØ[›Ü›X[^™YHÙ[‹˜Y\\››Ü›X[^™JØİ[Y[œ™XY\—ÚY[››İ][ÛŠBˆYˆ›İ›Ü›X[^™Y[ˆ™]\›ˆš[[™ˆØØ[[šÈHÙ[‹˜[››İ][ÛœÎ™Ù]RY
›Ü›X[^™Y›ØØ[Ø[››İ][Û—ÚY
BˆYˆ›İ[šÈ[‚ˆKHHYÚYÚØ[ˆ™HYÙÙY™Y›Ü™HH™^Ş[˜ÈØØ[œÈ]ÈÚYXØ\‹‚ˆKH\œÚ\İ\È^Xİ]\›Z[š\İXÈØØ[Y[]HÛ›NÈ›È™[[İHÜš]BˆKHÜˆ[][Ûˆ[™™\™[˜ÙH\[œÈ[ˆHRH›ØÙ\ÜË‚ˆ[šÈHÙ[‹˜[››İ][ÛœÎ\Ù\ØØ[ÂˆØØ[Ø[››İ][Û—ÚYH›Ü›X[^™Y›ØØ[Ø[››İ][Û—ÚYˆ™XY\—ÙØİ[Y[ÚYHØİ[Y[œ™XY\—ÚYˆØØ[ØÜ™X]YØ]H›Ü›X[^™Y™]][YKˆØØ]Ü—Ùš[™Ù\œš[H›Ü›X[^™Y›ØØ]Ü—Ùš[™Ù\œš[ˆÜšYÚ[˜[İ^Ú\ÚH›Ü›X[^™Y^Ú\Úˆ\İİ^Ú\ÚH›Ü›X[^™Y^Ú\Úˆ\İÛ›İWÚ\ÚH›Ü›X[^™Y››İWÚ\ÚˆŞ[˜×Üİ]HH›ØØ[ÛÛ›H‹ˆ\İÜŞ[˜×Ù\œ›ÜˆHš[ˆBˆ[™ˆ™]\›ˆØİ[Y[[››İ][Û‹›Ü›X[^™Y[šÂ™[™‚™[˜İ[ÛˆY]Y]URN˜Ø[‘Y]YÚYÚ
[™^
BˆØØ[Øİ[Y[HÙ[—Øİ\œ™[Øİ[Y[

BˆYˆ›İØİ[Y[Üˆ\J[™^
HH›[X™\ˆˆ[ˆ™]\›ˆ˜[ÙH[™ˆØØ[™XY\—İZHHÙ[‹™Ù]Ü™XY\—İZJ
BˆØØ[[››İ][ÛˆH™XY\—İZH[™™XY\—İZK˜[››İ][Û‚ˆ[™™XY\—İZK˜[››İ][Û‹˜[››İ][ÛœÂˆ[™™XY\—İZK˜[››İ][Û‹˜[››İ][ÛœÖÚ[™^HÜˆš[ˆ™]\›ˆ[››İ][ÛˆHš[[™[››İ][Û‹™˜]Ù\ˆHš[™[™‚™[˜İ[ÛˆY]Y]URN—Ü]Y]YRYÚYÚYÜÊØİ[Y[›Ü›X[^™Y[šË˜\Ù[[™K\Ú\™YYÜÊBˆYˆYÜË™\]X[
\Ú\™YYÜÊH[‚ˆRSX[˜YÙ\œÚİÊ[™›ÓY\ÜØYÙN›™]ŞÈ^HÊ“›È™XY\ˆYÚYÚ]YÈÚ[™Ù\ÈÈ]Y]YKˆŠHJBˆ™]\›‚ˆ[™‚ˆYˆ[šÈ[™[šË˜Ü™X]YÜ™[[İBˆ[™\J[šËœ™XY\—ÚYÚYÚÙØİ[Y[ÚY
HOHœİš[™È‚ˆ[™[šËœ™XY\—ÚYÚYÚÙØİ[Y[ÚYHˆˆ[‚ˆØØ[]Y]YY\œˆHÙ[‹›]]][ÛœÎœ]Y]YRYÚYÚYÜÊ[šË˜\Ù[[™KYÜÊBˆYˆ›İ]Y]YY[‚ˆRSX[˜YÙ\œÚİÊ[™›ÓY\ÜØYÙN›™]ŞÂˆ^H\œˆ[™\œ‹›Y\ÜØYÙHÜˆÊH™]š[İ\È™XY\ˆYÚYÚ]YÈY]]\İ™H™XÛÛ˜Ú[YÚ]Ş[˜È›İÈš\œİˆŠKˆJBˆ™]\›‚ˆ[™ˆÙ[‹˜[››İ][Û—ÛY]Y]NœÙ][™[™ÕYÜÊˆ›Ü›X[^™Y›ØØ[Ø[››İ][Û—ÚYˆ˜\Ù[[™KˆYÜËˆÜË[YJ
Bˆ
Bˆ[ÙBˆØØ[Ü™X]WÚ][HHÙ[‹œ]Y]YN™Ù]RÙ^Jˆ[››İ][Û’Y[]K˜Ü™X]T]Y]YRÙ^J›Ü›X[^™Y›ØØ[Ø[››İ][Û—ÚY
Bˆ
BˆYˆÜ™X]WÚ][H[™
Ü™X]WÚ][K˜][\ÈÜˆ
Hˆ[‚ˆRSX[˜YÙ\œÚİÊ[™›ÓY\ÜØYÙN›™]ŞÂˆ^HÊ•\ÈYÚYÚ\È[ˆ[œ™\ÛÛ™Y™XY\ˆÜ™X]H][\ˆ[ˆŞ[˜È›İÈÈ™XÛÛ˜Ú[H]™Y›Ü™HÚ[™Ú[™È]È™XY\ˆYÜËˆŠKˆJBˆ™]\›‚ˆ[™ˆÙ[‹˜[››İ][Û—ÛY]Y]NœÙ][™[™ÕYÜÊˆ›Ü›X[^™Y›ØØ[Ø[››İ][Û—ÚYˆ˜\Ù[[™KˆYÜËˆÜË[YJ
Bˆ
Bˆ[™ˆRSX[˜YÙ\œÚİÊ[™›ÓY\ÜØYÙN›™]ŞÂˆ^HÊ”™XY\ˆYÚYÚYÜÈ]Y]YYˆ[ˆŞ[˜È›İÈÚ[ˆ[İHØ[ÈÙ[™[KˆŠKˆJB™[™‚™[˜İ[ÛˆY]Y]URN™Y]YÚYÚYÜÊ[™^
BˆØØ[Øİ[Y[Ë›Ü›X[^™Y[šÈHÙ[—Ü™\ÛÛ™P[››İ][ÛŠ[™^
BˆYˆ›İØİ[Y[[‚ˆRSX[˜YÙ\œÚİÊ[™›ÓY\ÜØYÙN›™]ŞÈ^HÊ•\ÈYÚYÚ\È›İ[ˆHX[˜YÙY™XY\ˆØİ[Y[ˆŠHJBˆ™]\›‚ˆ[™‚ˆØØ[Y]Y]HHÙ[‹˜[››İ][Û—ÛY]Y]N™Ù]RY
›Ü›X[^™Y›ØØ[Ø[››İ][Û—ÚY
BˆØØ[˜\Ù[[™HHY]Y]H[™Y]Y]K›\İÜŞ[˜ÙYİYÜÈÜˆßBˆØØ[\Ú\™YHY]Y]H[™Y]Y]Kœ[™[™×İYÜÈÜˆ˜\Ù[[™B‚ˆYˆ[šÈ[™[šË˜Ü™X]YÜ™[[İBˆ[™\J[šËœ™XY\—ÚYÚYÚÙØİ[Y[ÚY
HOHœİš[™È‚ˆ[™[šËœ™XY\—ÚYÚYÚÙØİ[Y[ÚYHˆˆ[‚ˆØØ[™[[İHHÙ[—Ù™]Ú™[[İJ[šËœ™XY\—ÚYÚYÚÙØİ[Y[ÚY
BˆYˆ™[[İH[™™[[İK˜Ø]YÛÜHOHšYÚYÚˆ[™™[[İKœ\™[ÚYOHØİ[Y[œ™XY\—ÚY[‚ˆ˜\Ù[[™HHYÜË››Ü›X[^™J™[[İKYÜÊBˆ\Ú\™YHY]Y]H[™Y]Y]Kœ[™[™×İYÜÈÜˆ˜\Ù[[™BˆYˆ›İ
Y]Y]H[™Y]Y]Kœ[™[™×İYÜÊH[‚ˆÙ[‹˜[››İ][Û—ÛY]Y]N›X\šÕYÜÔŞ[˜ÙY
›Ü›X[^™Y›ØØ[Ø[››İ][Û—ÚY˜\Ù[[™KÜË[YJ
JBˆ[™ˆ[ÙBˆØØ[ØXÚYHÙ[‹œ™[[İWÚYÚYÚÎ™Ù]T™[[İRY
[šËœ™XY\—ÚYÚYÚÙØİ[Y[ÚY
BˆYˆØXÚY[™›İY]Y]H[‚ˆ˜\Ù[[™HHYÜË››Ü›X[^™JØXÚYYÜÊBˆ\Ú\™YH˜\Ù[[™Bˆ[™ˆ[™ˆ[™‚ˆØØ[]˜Z[X›HHÙ[—Ù™]ÚYÓ˜[Y\Ê
BˆÙ[—ÜÚİÕYÔXÚÙ\Âˆ]HHÊ”™XY\ˆYÚYÚYÜÈŠKˆÙ[XİYH\Ú\™Yˆ]˜Z[X›HH]˜Z[X›KˆÛ—ÜØ]™HH[˜İ[ÛŠYÜÊBˆÙ[—Ü]Y]YRYÚYÚYÜÊØİ[Y[›Ü›X[^™Y[šË˜\Ù[[™K\Ú\™YYÜÊBˆ[™ˆB™[™‚™[˜İ[ÛˆY]Y]URNœ™YÚ\İ\’YÚYÚ]ÛŠ
BˆØØ[™XY\—İZHHÙ[‹™Ù]Ü™XY\—İZJ
BˆYˆ›İ
™XY\—İZH[™™XY\—İZKšYÚYÚˆ[™\J™XY\—İZKšYÚYÚ˜YÒYÚYÚX[ÙÊHOH™[˜İ[ÛˆŠH[‚ˆ™]\›ˆ˜[ÙBˆ[™ˆ™XY\—İZKšYÚYÚ˜YÒYÚYÚX[ÙÊŒÜ™XYÚ\ÙWİYÜÈ‹[˜İ[ÛŠË[™^
Bˆ™]\›ˆÂˆ^HÊ”™XY\ˆYÜÈŠKˆÚİ×Ú[—ÚYÚYÚÙX[Ù×Ù[˜ÈH[˜İ[ÛŠ
Bˆ™]\›ˆÙ[˜Ø[‘Y]YÚYÚ
[™^
Bˆ[™ˆØ[˜XÚÈH[˜İ[ÛŠ
Bˆ™XY\—İZKšYÚYÚ›ÛÛÜÙJ
BˆÙ[™Y]YÚYÚYÜÊ[™^
Bˆ[™ˆBˆ[™
Bˆ™]\›ˆYB™[™‚“Y]Y]URK—Û›Ü›X[^™Y›İHH›Ü›X[^™Y›İB“Y]Y]URK—İš[HHš[B‚œ™]\›ˆY]Y]URB