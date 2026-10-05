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
        end, _([[Refreshing Reader metadata…

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
        end, _([[Loading Reader tags…

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
            mandatory = pending.note_pending and _("queued") or nil,
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
    dialog = InputDialog:new{
        title = _("Reader document note"),
        input = pending.note or "",
        allow_newline = true,
        buttons = {
            {
                {
                    text = _("Cancel"), id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Save for Sync"), is_enter_default = true,
                    callback = function()
                        local desired = normalizedNote(dialog:getInputText())
                        UIManager:close(dialog)
                        self.active_dialog = nil
                        if normalizedNote(pending.note) == desired then
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
                            text = desired == ""
                                and _("Reader document-note removal queued. Run Sync now when you want to send it.")
                                or _("Reader document-note change queued. Run Sync now when you want to send it."),
                        })
                    end,
                },
            },
        },
    }
    self.active_dialog = dialog
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function MetadataUI:_showTagInput(title, input_title, initial, callback)
    local dialog
    dialog = InputDialog:new{
        title = input_title,
        input = initial or "",
        buttons = {
            {
                {
                    text = _("Cancel"), id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("OK"), is_enter_default = true,
                    callback = function()
                        local value = dialog:getInputText()
                        UIManager:close(dialog)
                        self.active_dialog = nil
                        callback(value)
                    end,
                },
            },
        },
    }
    self.active_dialog = dialog
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function MetadataUI:_showTagPicker(options)
    options = options or {}
    local selected = asSet(options.selected)
    local available_set = asSet(options.available)
    for tag in pairs(selected) do available_set[tag] = true end
    local filter = trim(options.filter)
    local container
    local menu

    local function selectedList()
        local out = {}
        for tag, enabled in pairs(selected) do
            if enabled then out[#out + 1] = tag end
        end
        table.sort(out)
        return out
    end

    local function allList()
        local out = {}
        for tag in pairs(available_set) do out[#out + 1] = tag end
        table.sort(out)
        return out
    end

    local function closeMenu()
        if container then UIManager:close(container) end
        if self.active_menu == container then self.active_menu = nil end
    end

    local function rebuild(new_filter)
        closeMenu()
        UIManager:nextTick(function()
            self:_showTagPicker{
                title = options.title,
                selected = selectedList(),
                available = allList(),
                filter = new_filter,
                on_save = options.on_save,
            }
        end)
    end

    local items = {
        {
            text = _("Save tags"),
            mandatory = string.format(_("%d selected"), #selectedList()),
            callback = function()
                local result = selectedList()
                closeMenu()
                options.on_save(result)
            end,
        },
        {
            text = filter and _("Change tag search…") or _("Search existing tags…"),
            mandatory = filter,
            callback = function()
                closeMenu()
                self:_showTagInput(options.title, _("Search Reader tags"), filter or "", function(value)
                    rebuild(trim(value))
                end)
            end,
        },
        {
            text = _("Add new tag…"),
            callback = function()
                closeMenu()
                self:_showTagInput(options.title, _("New Reader tag"), "", function(value)
                    local tag = trim(value)
                    if tag then
                        available_set[tag] = true
                        selected[tag] = true
                    end
                    rebuild(filter)
                end)
            end,
            separator = true,
        },
    }

    local lower_filter = filter and filter:lower() or nil
    local visible = 0
    for _, tag in ipairs(allList()) do
        if not lower_filter or tag:lower():find(lower_filter, 1, true) then
            visible = visible + 1
            items[#items + 1] = {
                text = tag,
                checked_func = function() return selected[tag] == true end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    selected[tag] = not selected[tag]
                    if touchmenu_instance and touchmenu_instance.updateItems then
                        touchmenu_instance:updateItems()
                    elseif menu and menu.updateItems then
                        menu:updateItems()
                    end
                end,
            }
        end
    end
    if visible == 0 then
        items[#items + 1] = {
            text = filter and _("No existing tags match this search.") or _("No existing Reader tags were loaded."),
            enabled = false,
        }
    end

    menu = Menu:new{
        title = options.title or _("Reader tags"),
        item_table = items,
        width = math.floor(Screen:getWidth() * 0.94),
        height = math.floor(Screen:getHeight() * 0.94),
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

function MetadataUI:editDocumentTags(document, pending)
    local available = self:_fetchTagNames()
    self:_showTagPicker{
        title = _("Reader document tags"),
        selected = pending.tags,
        available = available,
        on_save = function(tags)
            if Tags.equal(pending.tags, tags) then
                UIManager:show(InfoMessage:new{ text = _("No Reader document-tag changes to queue.") })
                return
            end
            local queued, err = self.mutations:queueDocumentTags(document, tags)
            if not queued then
                UIManager:show(InfoMessage:new{
                    text = err and err.message or _("The Reader document-tag change could not be queued safely."),
                })
                return
            end
            UIManager:show(InfoMessage:new{
                text = _("Reader document tags queued. Run Sync now when you want to send them."),
            })
        end,
    }
end

function MetadataUI:_resolveAnnotation(index)
    local document = self:_currentDocument()
    local reader_ui = self.get_reader_ui()
    local annotation = reader_ui and reader_ui.annotation
        and reader_ui.annotation.annotations
        and reader_ui.annotation.annotations[index] or nil
    if not document or not annotation or annotation.drawer == nil then return nil end
    local normalized = self.adapter:normalize(document.reader_id, annotation)
    if not normalized then return nil end
    local link = self.annotations:getById(normalized.local_annotation_id)
    if not link then
        link = self.annotations:upsertLocal{
            local_annotation_id = normalized.local_annotation_id,
            reader_document_id = document.reader_id,
            local_created_at = normalized.datetime,
            locator_fingerprint = normalized.locator_fingerprint,
            original_text_hash = normalized.text_hash,
            last_text_hash = normalized.text_hash,
            last_note_hash = normalized.note_hash,
            sync_state = "local_only",
            last_sync_error = nil,
        }
    end
    return document, annotation, normalized, link
end

function MetadataUI:canEditHighlight(index)
    local document = self:_currentDocument()
    if not document or type(index) ~= "number" then return false end
    local reader_ui = self.get_reader_ui()
    local annotation = reader_ui and reader_ui.annotation
        and reader_ui.annotation.annotations
        and reader_ui.annotation.annotations[index] or nil
    return annotation ~= nil and annotation.drawer ~= nil
end

function MetadataUI:_queueHighlightTags(document, normalized, link, baseline, desired, tags)
    if Tags.equal(desired, tags) then
        UIManager:show(InfoMessage:new{ text = _("No Reader highlight-tag changes to queue.") })
        return
    end

    if link and link.created_remote
        and type(link.reader_highlight_document_id) == "string"
        and link.reader_highlight_document_id ~= "" then
        local queued, err = self.mutations:queueHighlightTags(link, baseline, tags)
        if not queued then
            UIManager:show(InfoMessage:new{
                text = err and err.message or _("A previous Reader highlight-tag edit must be reconciled with Sync now first."),
            })
            return
        end
        self.annotation_metadata:setPendingTags(
            normalized.local_annotation_id,
            baseline,
            tags,
            os.time()
        )
    else
        local create_item = self.queue:getByKey(
            AnnotationIdentity.createQueueKey(normalized.local_annotation_id)
        )
        if create_item and (create_item.attempts or 0) > 0 then
            UIManager:show(InfoMessage:new{
                text = _("This highlight has an unresolved Reader create attempt. Run Sync now to reconcile it before changing its Reader tags."),
            })
            return
        end
        self.annotation_metadata:setPendingTags(
            normalized.local_annotation_id,
            baseline,
            tags,
            os.time()
        )
    end
    UIManager:show(InfoMessage:new{
        text = _("Reader highlight tags queued. Run Sync now when you want to send them."),
    })
end

function MetadataUI:editHighlightTags(index)
    local document, _, normalized, link = self:_resolveAnnotation(index)
    if not document then
        UIManager:show(InfoMessage:new{ text = _("This highlight is not in a managed Reader document.") })
        return
    end

    local metadata = self.annotation_metadata:getById(normalized.local_annotation_id)
    local baseline = metadata and metadata.last_synced_tags or {}
    local desired = metadata and metadata.pending_tags or baseline

    if link and link.created_remote
        and type(link.reader_highlight_document_id) == "string"
        and link.reader_highlight_document_id ~= "" then
        local remote = self:_fetchRemote(link.reader_highlight_document_id)
        if remote and remote.category == "highlight" and remote.parent_id == document.reader_id then
            baseline = Tags.normalize(remote.tags)
            desired = metadata and metadata.pending_tags or baseline
            if not (metadata and metadata.pending_tags) then
                self.annotation_metadata:markTagsSynced(normalized.local_annotation_id, baseline, os.time())
            end
        else
            local cached = self.remote_highlights:getByRemoteId(link.reader_highlight_document_id)
            if cached and not metadata then
                baseline = Tags.normalize(cached.tags)
                desired = baseline
            end
        end
    end

    local available = self:_fetchTagNames()
    self:_showTagPicker{
        title = _("Reader highlight tags"),
        selected = desired,
        available = available,
        on_save = function(tags)
            self:_queueHighlightTags(document, normalized, link, baseline, desired, tags)
        end,
    }
end

function MetadataUI:registerHighlightButton()
    local reader_ui = self.get_reader_ui()
    if not (reader_ui and reader_ui.highlight
        and type(reader_ui.highlight.addToHighlightDialog) == "function") then
        return false
    end
    reader_ui.highlight:addToHighlightDialog("08_readwise_tags", function(_, index)
        return {
            text = _("Reader tags"),
            show_in_highlight_dialog_func = function()
                return self:canEditHighlight(index)
            end,
            callback = function()
                reader_ui.highlight:onClose()
                self:editHighlightTags(index)
            end,
        }
    end)
    return true
end

MetadataUI._normalizedNote = normalizedNote
MetadataUI._trim = trim

return MetadataUI
