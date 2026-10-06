-- SPDX-License-Identifier: AGPL-3.0-only

-- v1.3 compatibility wrapper around the physically accepted v1.2 mutation
-- engine. KOReader represents a cleared note as nil, while Reader/Readwise
-- accept an empty string for note removal. Normalize only the mutation scan so
-- the existing conflict/identity machinery can safely exercise the already
-- supported string-note path without changing annotation identity/hash data.
local Base = require("sync/annotation_mutations_base")

local base_new = Base.new
local base_repair_reader_note = Base._repairReaderNote

function Base:new(options)
    options = options or {}
    local adapter = assert(options.adapter, "annotation adapter is required")
    local adapter_proxy = setmetatable({}, { __index = adapter })
    function adapter_proxy:scan(...)
        local report, err = adapter:scan(...)
        if not report then return nil, err end
        for _, candidate in ipairs(report.annotations or {}) do
            if candidate.note == nil then
                candidate.note = ""
            end
        end
        return report
    end
    local wrapped = {}
    for key, value in pairs(options) do wrapped[key] = value end
    wrapped.adapter = adapter_proxy
    return base_new(self, wrapped)
end

function Base:_repairReaderNote(document, candidate, link, report)
    if candidate and candidate.note == nil then
        local normalized = {}
        for key, value in pairs(candidate) do normalized[key] = value end
        normalized.note = ""
        candidate = normalized
    end
    return base_repair_reader_note(self, document, candidate, link, report)
end

return Base
