-- SPDX-License-Identifier: AGPL-3.0-only

local Documents = {}
Documents.__index = Documents

local function defaultDependencies()
    return {
        DocSettings = require("docsettings"),
        Event = require("ui/event"),
        ReaderUI = require("apps/reader/readerui"),
        UIManager = require("ui/uimanager"),
    }
end

function Documents:new(options)
    options = options or {}
    return setmetatable({
        deps = options.deps or defaultDependencies(),
        broadcast_events = options.broadcast_events ~= false,
    }, self)
end

function Documents:writeMetadata(filepath, document)
    local settings = self.deps.DocSettings.openSettingsFile()
    local props = {}

    if type(document.title) == "string" and document.title ~= "" then
        props.title = document.title
    end
    if type(document.author) == "string" and document.author ~= "" then
        props.authors = document.author
    end
    if type(document.summary) == "string" and document.summary ~= "" then
        props.description = document.summary
    end
    if type(document.site_name) == "string" and document.site_name ~= "" then
        props.series = document.site_name
    end

    settings:saveSetting("doc_props", props)
    settings:saveSetting("custom_props", props)
    if not settings:flushCustomMetadata(filepath) then
        return nil, {
            kind = "metadata",
            retryable = true,
            message = "KOReader custom metadata could not be written.",
        }
    end

    if self.broadcast_events then
        self:invalidateMetadata(filepath)
    end
    return true
end

function Documents:invalidateMetadata(filepath)
    self.deps.UIManager:broadcastEvent(self.deps.Event:new("InvalidateMetadataCache", filepath))
    self.deps.UIManager:broadcastEvent(self.deps.Event:new("BookMetadataChanged"))
    return true
end

function Documents:openDocument(filepath)
    self.deps.UIManager:broadcastEvent(self.deps.Event:new("SetupShowReader"))
    self.deps.ReaderUI:showReader(filepath)
end

return Documents
