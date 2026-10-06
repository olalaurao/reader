-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local Tags = require("metadata/tags")
local _ = require("gettext")

local HighlightEditor = {}

local function getAnnotation(reader_highlight, index)
    local annotations = reader_highlight
        and reader_highlight.ui
        and reader_highlight.ui.annotation
        and reader_highlight.ui.annotation.annotations
    if type(annotations) ~= "table" then return nil end
    if index and type(annotations[index]) == "table" then return annotations[index] end
    return nil
end

local function closeHighlightMenu(reader_highlight)
    if reader_highlight and reader_highlight.highlight_dialog then
        UIManager:close(reader_highlight.highlight_dialog)
        reader_highlight.highlight_dialog = nil
    end
end

local function normalizedLocal(self, document, annotation)
    if type(annotation) ~= "table" then return nil end
    local ok, normalized = pcall(self.adapter.normalize, self.adapter, document.reader_id, annotation)
    if not ok or type(normalized) ~= "table" then return nil end
    return normalized
end

local function persistLocalLink(self, document, local_item)
    local existing = self.annotations:getById(local_item.local_annotation_id)
    if existing then return existing end
    if type(self.annotations.upsertLocal) ~= "function" then return nil end
    self.annotations:upsertLocal{
        local_annotation_id = local_item.local_annotation_id,
        reader_document_id = document.reader_id,
        local_created_at = local_item.datetime,
        locator_fingerprint = local_item.locator_fingerprint,
        original_text_hash = local_item.text_hash,
        last_text_hash = local_item.text_hash,
        last_note_hash = local_item.note_hash,
        sync_state = "local_only",
    }
    return self.annotations:getById(local_item.local_annotation_id)
end

local function resolveLink(self, document, annotation)
    local local_item = normalizedLocal(self, document, annotation)
    if not local_item then return nil end
    local link = self.annotations:getById(local_item.local_annotation_id)
    if not link then link = persistLocalLink(self, document, local_item) end
    return link, local_item
end

local function currentTags(self, link)
    local meta = link and self.annotation_metadata:getById(link.local_annotation_id) or nil
    if meta and type(meta.pending_tags) == "table" then
        return meta.pending_tags, meta.last_synced_tags or {}
    end
    if link and type(link.reader_highlight_document_id) == "string"
        and link.reader_highlight_document_id ~= "" then
        local remote = self.remote_highlights:getByRemoteId(link.reader_highlight_document_id)
        if remote and type(remote.tags) == "table" then
            return remote.tags, remote.tags
        end
    end
    return meta and meta.last_synced_tags or {}, meta and meta.last_synced_tags or {}
end

function HighlightEditor.editTags(self, reader_highlight, index)
    local document = self:_currentDocument()
    if not document then
        UIManager:show(InfoMessage:new{ text = _("The current document is not managed by Readwise Reader.") })
        return
    end

    local annotation = getAnnotation(reader_highlight, index)
    if not annotation and reader_highlight and type(reader_highlight.selected_text) == "table" then
        -- For a new selection, ask KOReader itself to create the highlight first.
        -- saveHighlight() returns the exact annotation index, so the Reader tag
        -- intent is attached only after a real local identity exists.
        if type(reader_highlight.saveHighlight) ~= "function" then
            UIManager:show(InfoMessage:new{ text = _("This highlight could not be created safely before tagging.") })
            return
        end
        local ok, created_index = pcall(reader_highlight.saveHighlight, reader_highlight)
        if not ok or type(created_index) ~= "number" then
            UIManager:show(InfoMessage:new{ text = _("This highlight could not be created safely before tagging.") })
            return
        end
        index = created_index
        annotation = getAnnotation(reader_highlight, index)
    end

    local link = resolveLink(self, document, annotation)
    if not link then
        UIManager:show(InfoMessage:new{ text = _("This highlight could not be identified safely.") })
        return
    end

    local selected, baseline = currentTags(self, link)
    local available = self:_fetchTagNames()
    self:_showTagPicker{
        title = _("Reader highlight tags"),
        selected = selected,
        available = available,
        on_save = function(desired)
            if Tags.equal(desired, selected) then
                UIManager:show(InfoMessage:new{ text = _("No Reader highlight-tag change to queue.") })
                return
            end

            if type(link.reader_highlight_document_id) == "string"
                and link.reader_highlight_document_id ~= "" then
                local queued, err = self.mutations:queueHighlightTags(link, baseline, desired)
                if not queued then
                    UIManager:show(InfoMessage:new{
                        text = err and err.message or _("The Reader highlight-tag change could not be queued safely."),
                    })
                    return
                end
            else
                self.annotation_metadata:setPendingTags(link.local_annotation_id, baseline, desired)
            end
            UIManager:show(InfoMessage:new{
                text = _("Reader highlight tags queued. Run Sync now when you want to send them."),
            })
        end,
    }
end

function HighlightEditor.register(self)
    local reader_ui = self.get_reader_ui()
    local highlight = reader_ui and reader_ui.highlight
    if not highlight or type(highlight.addToHighlightDialog) ~= "function" then return false end

    highlight:addToHighlightDialog("08_readwise_tags", function(this, index)
        return {
            text = _("Reader tags"),
            show_in_highlight_dialog_func = function()
                return self:_currentDocument() ~= nil and type(this.selected_text) == "table"
            end,
            callback = function()
                closeHighlightMenu(this)
                self:editHighlightTags(this, index)
            end,
        }
    end)
    return true
end

HighlightEditor._getAnnotation = getAnnotation
HighlightEditor._resolveLink = resolveLink
HighlightEditor._currentTags = currentTags

return HighlightEditor
