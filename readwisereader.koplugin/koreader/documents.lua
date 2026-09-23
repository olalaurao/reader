-- SPDX-License-Identifier: AGPL-3.0-only

local Documents = {}
Documents.__index = Documents

local function tagsToKeywords(tags)
    if type(tags) ~= "table" then return nil end

    local out, seen = {}, {}
    for _, value in ipairs(tags) do
        if type(value) == "string" then
            -- KOReader stores keywords as one string and Bookshelf treats
            -- newline-separated values as independent genres. Keep Reader's
            -- ordering, trim only the edges, and prevent an embedded newline
            -- from accidentally creating an extra Bookshelf genre.
            local tag = value:gsub("[\r\n]+", " "):match("^%s*(.-)%s*$")
            if tag ~= "" and not seen[tag] then
                seen[tag] = true
                out[#out + 1] = tag
            end
        end
    end
    -- Empty string is intentional: KOReader/Bookshelf uses it to mean the
    -- custom keyword set was explicitly cleared instead of falling back to
    -- embedded document keywords.
    return table.concat(out, "\n")
end

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
    local keywords = tagsToKeywords(document.tags)
    if keywords ~= nil then
        props.keywords = keywords
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

function Documents:refreshExternalMetadataCaches()
    -- Bookshelf v5.1.4 deliberately keeps its light-metadata cache warm when
    -- handling KOReader's BookMetadataChanged event. That is normally useful,
    -- but it means externally-written custom keywords can remain invisible in
    -- the Genres shelf even though the sidecar itself is already correct.
    --
    -- Do not introduce a hard Bookshelf dependency: only invalidate its cache
    -- when the repository module is already loaded in this KOReader process.
    -- If Bookshelf has not been opened yet, there is no stale light cache to
    -- clear and its first open will build from the fresh custom metadata.
    local repo = package.loaded["lib/bookshelf_book_repository"]
    if type(repo) ~= "table" then return true end

    local ok = true
    if type(repo.invalidateLightMeta) == "function" then
        ok = pcall(repo.invalidateLightMeta) and ok
    end
    if type(repo.invalidateBookCache) == "function" then
        ok = pcall(repo.invalidateBookCache, "ReadwiseReader metadata sync") and ok
    end
    return ok
end

function Documents:openDocument(filepath)
    self.deps.UIManager:broadcastEvent(self.deps.Event:new("SetupShowReader"))
    self.deps.ReaderUI:showReader(filepath)
end

Documents._tagsToKeywords = tagsToKeywords

return Documents
