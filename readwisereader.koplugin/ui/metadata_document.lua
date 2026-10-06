-- SPDX-License-Identifier: AGPL-3.0-only

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Tags = require("metadata/tags")
local _ = require("gettext")
local Screen = Device.screen

local DocumentEditor = {}

local function normalizedNote(value)
    if value == nil then return "" end
    return tostring(value):gsub("\r\n", "\n"):gsub("\r", "\n")
end

local function showQueuedMessage(desired)
    if desired == "" then
        return _("Reader document-note removal queued. Run Sync now when you want to send it.")
    end
    return _("Reader document-note change queued. Run Sync now when you want to send it.")
end

function DocumentEditor.fetchRemote(self, reader_id)
    if not self.config:hasAccessToken() then return nil end
    local remote
    Trapper:wrap(function()
        local completed, value = Trapper:dismissableRunInSubprocess(function()
            return self.reader:getDocument(reader_id, false, false)
        end, _([[Refreshing Reader metadata...

Tap to cancel. This is a read-only request.]]))
        if completed then remote = value end
    end)
    return remote
end

function DocumentEditor.showActions(self, document, pending)
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

function DocumentEditor.editCurrent(self)
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

local function queueNote(self, document, pending, desired)
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
            or showQueuedMessage(desired),
    })
end

function DocumentEditor.editNote(self, document, pending)
    pending = pending or self.mutations:getPendingDocumentState(document)
    local dialog
    local buttons = {
        {
            {
                text = _("Cancel"), id = "close",
                callback = function()
                    UIManager:close(dialog)
                    self.active_dialog = nil
                end,
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
                    queueNote(self, document, pending, desired)
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
                    local refreshed = self.documents:getById(document.reader_id)
                    if refreshed and refreshed.remote_notes ~= nil then
                        document.remote_notes = refreshed.remote_notes
                    end
                    UIManager:show(InfoMessage:new{
                        text = _("Kindle note edit discarded. The current Reader note was kept."),
                    })
                end,
            },
        }
    end

    if normalizedNote(pending.note) ~= "" then
        buttons[#buttons + 1] = {
            {
                text = _("Clear note"),
                callback = function()
                    UIManager:close(dialog)
                    self.active_dialog = nil
                    queueNote(self, document, pending, "")
                end,
            },
        }
    end

    dialog = InputDialog:new{
        title = pending.note_status == "blocked"
            and _("Reader document note - conflict")
            or _("Reader document note"),
        input = normalizedNote(pending.note),
        input_type = "text",
        buttons = buttons,
    }
    self.active_dialog = dialog
    UIManager:show(dialog)
    if type(dialog.onShowKeyboard) == "function" then dialog:onShowKeyboard() end
end

function DocumentEditor.editTags(self, document, pending)
    pending = pending or self.mutations:getPendingDocumentState(document)
    local available = self:_fetchTagNames()
    self:_showTagPicker{
        title = _("Reader document tags"),
        selected = pending.tags,
        available = available,
        on_save = function(desired)
            if Tags.equal(desired, pending.tags) then
                UIManager:show(InfoMessage:new{ text = _("No Reader document-tag change to queue.") })
                return
            end
            local queued, err = self.mutations:queueDocumentTags(document, desired)
            if not queued then
                UIManager:show(InfoMessage:new{
                    text = err and err.message or _("The Reader document-tag change could not be queued safely."),
                })
                return
            end
            UIManager:show(InfoMessage:new{
                text = _("Reader document-tag change queued. Run Sync now when you want to send it."),
            })
        end,
    }
end

DocumentEditor._normalizedNote = normalizedNote

return DocumentEditor
