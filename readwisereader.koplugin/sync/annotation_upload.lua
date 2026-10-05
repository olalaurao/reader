-- SPDX-License-Identifier: AGPL-3.0-only

-- v1.3 compatibility wrapper around the accepted v1.2 create engine. It adds
-- durable Reader-tag intent to new highlights and drains the generic metadata
-- mutation queue at the same safe point where create work is already allowed:
-- after the worker's read-only reachability/auth preflight.
local Base = require("sync/annotation_upload_base")
local AnnotationMetadata = require("storage/annotation_metadata")
local MetadataMutations = require("sync/metadata_mutations")

local base_new = Base.new
local base_process_queue = Base.processQueue
local base_persist_remote = Base._persistRemote

local function localIdFromMarker(marker)
    local prefix = "KOReader Readwise Reader:"
    if type(marker) ~= "string" or marker:sub(1, #prefix) ~= prefix then return nil end
    local value = marker:sub(#prefix + 1)
    return value ~= "" and value or nil
end

function Base:new(options)
    options = options or {}
    local annotation_metadata = options.annotation_metadata
    if not annotation_metadata and options.queue and options.queue.db then
        annotation_metadata = AnnotationMetadata:new{ db = options.queue.db }
    end

    local reader = assert(options.reader, "Reader API is required")
    local reader_proxy = setmetatable({}, { __index = reader })
    function reader_proxy:createHighlight(parent_id, content, note, tags, saved_using)
        local local_id = localIdFromMarker(saved_using)
        if local_id and annotation_metadata then
            local metadata = annotation_metadata:getById(local_id)
            if metadata and metadata.pending_tags ~= nil then
                tags = metadata.pending_tags
            end
        end
        return reader:createHighlight(parent_id, content, note, tags, saved_using)
    end

    local wrapped = {}
    for key, value in pairs(options) do wrapped[key] = value end
    wrapped.reader = reader_proxy
    local instance = base_new(self, wrapped)
    instance.annotation_metadata = annotation_metadata
    instance._v13_reader = reader
    return instance
end

function Base:_persistRemote(candidate, remote_id, key)
    base_persist_remote(self, candidate, remote_id, key)
    if self.annotation_metadata then
        local metadata = self.annotation_metadata:getById(candidate.local_annotation_id)
        if metadata and metadata.pending_tags ~= nil then
            self.annotation_metadata:markTagsSynced(
                candidate.local_annotation_id,
                metadata.pending_tags,
                self.now()
            )
        end
    end
end

function Base:processQueue(options)
    -- The stock worker calls this only after a successful Reader reachability
    -- probe, so metadata writes inherit the exact same no-Wi-Fi-control and
    -- offline-safety boundary as highlight creates.
    local metadata_report
    if self.annotation_metadata then
        local mutations = MetadataMutations:new{
            reader = self._v13_reader or self.reader,
            documents = self.documents,
            queue = self.queue,
            annotation_metadata = self.annotation_metadata,
            hasher = self.hasher,
            now = self.now,
        }
        metadata_report = mutations:processQueue()
    end
    local report, err = base_process_queue(self, options)
    if report then report.metadata = metadata_report end
    return report, err
end

Base._localIdFromMarker = localIdFromMarker

return Base
