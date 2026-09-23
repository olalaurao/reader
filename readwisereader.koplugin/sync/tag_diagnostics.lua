-- SPDX-License-Identifier: AGPL-3.0-only

local TagDiagnostics = {}

local function containsTag(tags, wanted)
    for _, tag in ipairs(tags or {}) do
        if tag == wanted then return true end
    end
    return false
end

function TagDiagnostics:run(tag_name)
    local Config = require("config")
    local DB = require("storage/db")
    local DocumentsRepository = require("storage/documents")
    local Http = require("api/http")
    local Reader = require("api/reader")

    local config = Config:new()
    local db
    local ok, result, err = pcall(function()
        db = DB:new()
        local repository = DocumentsRepository:new{ db = db }
        local reader = Reader:new{
            http = Http:new(),
            config = config,
        }

        local diagnostic, diag_err = reader:diagnoseTag(tag_name)
        if not diagnostic then return nil, diag_err end

        local summary = {
            tag_found = diagnostic.tag_found == true,
            tag_name = diagnostic.tag_name or tag_name,
            tag_key = diagnostic.tag_key,
            tag_pages = diagnostic.tag_pages or 0,
            document_pages = diagnostic.document_pages or 0,
            total_matches = 0,
            top_level_matches = 0,
            article_matches = 0,
            managed_matches = 0,
            managed_local_matches = 0,
            payload_has_tag = 0,
            categories = {},
        }

        for _, document in ipairs(diagnostic.documents or {}) do
            summary.total_matches = summary.total_matches + 1
            local category = document.category or "unknown"
            summary.categories[category] = (summary.categories[category] or 0) + 1
            if document.parent_id == nil then
                summary.top_level_matches = summary.top_level_matches + 1
            end
            if document.category == "article" and document.parent_id == nil then
                summary.article_matches = summary.article_matches + 1
            end
            if containsTag(document.tags, summary.tag_name) then
                summary.payload_has_tag = summary.payload_has_tag + 1
            end

            local existing = repository:getById(document.id)
            if existing and existing.is_managed then
                summary.managed_matches = summary.managed_matches + 1
                if existing.is_local_present
                    and type(existing.local_path) == "string"
                    and existing.local_path ~= "" then
                    summary.managed_local_matches = summary.managed_local_matches + 1
                end
            end
        end

        return summary
    end)

    if db then pcall(function() db:close() end) end
    if config then pcall(function() config:close() end) end

    if not ok then
        return nil, {
            kind = "worker",
            retryable = true,
            message = "Reader tag diagnostics failed safely.",
        }
    end
    return result, err
end

return TagDiagnostics
