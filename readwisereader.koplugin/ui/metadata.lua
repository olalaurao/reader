-- SPDX-License-Identifier: AGPL-3.0-only

local DocumentEditor = require("ui/metadata_document")
local HighlightEditor = require("ui/metadata_highlight")
local TagPicker = require("ui/metadata_tags")
local _ = require("gettext")

local MetadataUI = {}
MetadataUI.__index = MetadataUI

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
    return DocumentEditor.fetchRemote(self, reader_id)
end

function MetadataUI:_fetchTagNames()
    return TagPicker.fetchTagNames(self)
end

function MetadataUI:_closeActiveMenu()
    return TagPicker.closeActiveMenu(self)
end

function MetadataUI:_showTagPicker(options)
    return TagPicker.show(self, options)
end

function MetadataUI:_showDocumentActions(document, pending)
    return DocumentEditor.showActions(self, document, pending)
end

function MetadataUI:editCurrentDocument()
    return DocumentEditor.editCurrent(self)
end

function MetadataUI:editDocumentNote(document, pending)
    return DocumentEditor.editNote(self, document, pending)
end

function MetadataUI:editDocumentTags(document, pending)
    return DocumentEditor.editTags(self, document, pending)
end

function MetadataUI:registerHighlightButton()
    return HighlightEditor.register(self)
end

function MetadataUI:editHighlightTags(reader_highlight, index)
    return HighlightEditor.editTags(self, reader_highlight, index)
end

return MetadataUI
