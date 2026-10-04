-- SPDX-License-Identifier: AGPL-3.0-only

local Audit = {}
Audit.__index = Audit

local EXAMPLE_LIMIT = 3

local function asKey(value)
    if type(value) == "string" and value ~= "" then return value end
    return "(missing)"
end

local function increment(map, key)
    key = asKey(key)
    map[key] = (map[key] or 0) + 1
end

local function countKeys(map)
    local count = 0
    for _ in pairs(map or {}) do count = count + 1 end
    return count
end

local function oneLine(value)
    local text = tostring(value or "")
    text = text:gsub("[%c]", " ")
    text = text:gsub("%s+", " ")
    text = text:match("^%s*(.-)%s*$") or ""
    if #text > 80 then text = text:sub(1, 77) .. "..." end
    return text
end

local function exampleFor(document)
    document = document or {}
    local title = oneLine(document.title)
    if title ~= "" then return title end
    local id = oneLine(document.id or document.reader_id)
    if id ~= "" then return id end
    return "(untitled)"
end

local function addReason(groups, reason, document)
    reason = oneLine(reason)
    if reason == "" then reason = "unknown" end
    local group = groups[reason]
    if not group then
        group = { count = 0, examples = {} }
        groups[reason] = group
    end
    group.count = group.count + 1
    if #group.examples < EXAMPLE_LIMIT then
        group.examples[#group.examples + 1] = exampleFor(document)
    end
end

local function errorLabel(err)
    if type(err) ~= "table" then return "unknown" end
    local stage = asKey(err.stage or err.kind)
    local detail = err.detail
    if type(detail) == "string" and detail ~= "" and detail ~= stage then
        return stage .. " / " .. detail
    end
    return stage
end

local function materializationReason(document, err)
    local category = asKey(document and document.category)
    if type(err) ~= "table" then
        return category .. " / unknown materialization error"
    end

    if category == "article"
        and err.kind == "content"
        and type(err.message) == "string"
        and err.message:find("processed HTML", 1, true) then
        return "article / processed HTML missing"
    end

    if (category == "pdf" or category == "epub")
        and err.stage == "raw_fallback" then
        return category .. " / raw source unavailable + no HTML fallback"
    end

    if (category == "pdf" or category == "epub")
        and err.kind == "raw_unavailable" then
        return category .. " / raw source unavailable"
    end

    if err.kind == "exists" then
        return category .. " / destination already exists"
    end

    return category .. " / " .. errorLabel(err)
end

local function lookupReason(document, err)
    local category = asKey(document and document.category)
    return category .. " / direct lookup " .. errorLabel(err)
end

function Audit:new(filters, supported_categories)
    return setmetatable({
        filters = filters or { locations = {}, categories = {} },
        supported_categories = supported_categories or {},
        metadata_parent_seen = 0,
        metadata_eligible = 0,
        child_records = 0,
        excluded_by_location = {},
        excluded_by_category = {},
        unsupported_by_category = {},
        eligible = {},
        outcomes = {},
        content_seen = {},
        late_content_eligible = 0,
        repair_candidates = 0,
        content_scan_seen = 0,
        content_scan_eligible_seen = 0,
        content_scan_missing = 0,
        content_scan_direct_reads = 0,
        content_scan_direct_recovered = 0,
        content_scan_direct_failed = 0,
        content_scan_remote_changed = 0,
        materialization_skip_reasons = {},
        retryable_error_reasons = {},
        content_lookup_failure_reasons = {},
    }, self)
end

function Audit:classify(document)
    if not document then return "invalid", "(missing)" end
    if document.parent_id ~= nil then return "child", "child" end

    local location = asKey(document.location)
    if self.filters.locations[document.location] ~= true then
        return "excluded_location", location
    end

    local category = asKey(document.category)
    if self.supported_categories[document.category] ~= true then
        return "unsupported_category", category
    end
    if self.filters.categories[document.category] ~= true then
        return "excluded_category", category
    end
    return "eligible", category
end

function Audit:_ensureEligible(document, source)
    local id = document and (document.id or document.reader_id)
    if type(id) ~= "string" or id == "" then return nil end
    if not self.eligible[id] then
        self.eligible[id] = {
            id = id,
            title = document.title,
            category = document.category,
            location = document.location,
        }
        if source == "content" then
            self.late_content_eligible = self.late_content_eligible + 1
        elseif source == "repair" then
            self.repair_candidates = self.repair_candidates + 1
        end
    else
        local current = self.eligible[id]
        if document.title ~= nil then current.title = document.title end
        if document.category ~= nil then current.category = document.category end
        if document.location ~= nil then current.location = document.location end
    end
    return self.eligible[id]
end

function Audit:observeMetadata(document)
    if document and document.parent_id ~= nil then
        self.child_records = self.child_records + 1
        return "child", "child"
    end

    self.metadata_parent_seen = self.metadata_parent_seen + 1
    local status, key = self:classify(document)
    if status == "eligible" then
        self.metadata_eligible = self.metadata_eligible + 1
        self:_ensureEligible(document, "metadata")
    elseif status == "excluded_location" then
        increment(self.excluded_by_location, key)
    elseif status == "excluded_category" then
        increment(self.excluded_by_category, key)
    elseif status == "unsupported_category" then
        increment(self.unsupported_by_category, key)
    end
    return status, key
end

function Audit:addRepairCandidate(document)
    local status = self:classify(document)
    if status ~= "eligible" then return false end
    self:_ensureEligible(document, "repair")
    return true
end

function Audit:observeContent(document)
    self.content_scan_seen = self.content_scan_seen + 1
    local id = document and document.id
    if type(id) == "string" and id ~= "" then self.content_seen[id] = true end
    local status, key = self:classify(document)
    if status == "eligible" then
        self.content_scan_eligible_seen = self.content_scan_eligible_seen + 1
        self:_ensureEligible(document, "content")
    end
    return status, key
end

function Audit:getEligible(id)
    return self.eligible[id]
end

function Audit:eligibleIds()
    local ids = {}
    for id in pairs(self.eligible) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

function Audit:wasContentSeen(id)
    return self.content_seen[id] == true
end

function Audit:getOutcome(id)
    return self.outcomes[id]
end

function Audit:markOutcome(id, outcome)
    if type(id) ~= "string" or id == "" then return end
    self.outcomes[id] = outcome
end

function Audit:markContentMissing()
    self.content_scan_missing = self.content_scan_missing + 1
end

function Audit:markDirectRead(ok)
    self.content_scan_direct_reads = self.content_scan_direct_reads + 1
    if ok then
        self.content_scan_direct_recovered = self.content_scan_direct_recovered + 1
    else
        self.content_scan_direct_failed = self.content_scan_direct_failed + 1
    end
end

function Audit:markRemoteChanged(id)
    self.content_scan_remote_changed = self.content_scan_remote_changed + 1
    if type(id) == "string" and id ~= "" then
        self.outcomes[id] = "remote_changed"
    end
end

function Audit:recordPermanent(document, err)
    addReason(self.materialization_skip_reasons, materializationReason(document, err), document)
    local id = document and (document.id or document.reader_id)
    if type(id) == "string" and id ~= "" then self.outcomes[id] = "permanent_skip" end
end

function Audit:recordKnownPermanent(document, kind)
    local reason = asKey(document and document.category)
        .. " / previous permanent " .. asKey(kind)
    addReason(self.materialization_skip_reasons, reason, document)
    local id = document and (document.id or document.reader_id)
    if type(id) == "string" and id ~= "" then self.outcomes[id] = "permanent_skip" end
end

function Audit:recordRetryable(document, err)
    addReason(self.retryable_error_reasons,
        asKey(document and document.category) .. " / " .. errorLabel(err), document)
    local id = document and (document.id or document.reader_id)
    if type(id) == "string" and id ~= "" then self.outcomes[id] = "retryable_failure" end
end

function Audit:recordLookupFailure(document, err)
    addReason(self.content_lookup_failure_reasons, lookupReason(document, err), document)
end

function Audit:apply(report)
    local excluded_location_total = 0
    for _, count in pairs(self.excluded_by_location) do excluded_location_total = excluded_location_total + count end
    local excluded_category_total = 0
    for _, count in pairs(self.excluded_by_category) do excluded_category_total = excluded_category_total + count end
    local unsupported_total = 0
    for _, count in pairs(self.unsupported_by_category) do unsupported_total = unsupported_total + count end

    local outcome_counts = {
        already_local = 0,
        downloaded = 0,
        permanent_skip = 0,
        retryable_failure = 0,
        remote_changed = 0,
    }
    local unaccounted = 0
    for id in pairs(self.eligible) do
        local outcome = self.outcomes[id]
        if outcome_counts[outcome] ~= nil then
            outcome_counts[outcome] = outcome_counts[outcome] + 1
        else
            unaccounted = unaccounted + 1
        end
    end

    local eligible_total = countKeys(self.eligible)
    local accounted = eligible_total - unaccounted
    local metadata_accounted = self.metadata_eligible
        + excluded_location_total
        + excluded_category_total
        + unsupported_total
    local metadata_unaccounted = self.metadata_parent_seen - metadata_accounted

    report.metadata_seen = self.metadata_parent_seen
    report.child_records = self.child_records
    report.eligible_metadata = self.metadata_eligible
    report.eligible_documents = eligible_total
    report.repair_candidates = self.repair_candidates
    report.late_content_eligible = self.late_content_eligible
    report.excluded_location_total = excluded_location_total
    report.excluded_category_total = excluded_category_total
    report.unsupported_category_total = unsupported_total
    report.excluded_by_location = self.excluded_by_location
    report.excluded_by_category = self.excluded_by_category
    report.unsupported_by_category = self.unsupported_by_category
    report.filtered_out = excluded_location_total + excluded_category_total + unsupported_total
    report.content_scan_seen = self.content_scan_seen
    report.content_scan_eligible_seen = self.content_scan_eligible_seen
    report.content_scan_missing = self.content_scan_missing
    report.content_scan_direct_reads = self.content_scan_direct_reads
    report.content_scan_direct_recovered = self.content_scan_direct_recovered
    report.content_scan_direct_failed = self.content_scan_direct_failed
    report.content_scan_remote_changed = self.content_scan_remote_changed
    report.materialization_skip_reasons = self.materialization_skip_reasons
    report.retryable_error_reasons = self.retryable_error_reasons
    report.content_lookup_failure_reasons = self.content_lookup_failure_reasons
    report.audit_already_local = outcome_counts.already_local
    report.audit_downloaded = outcome_counts.downloaded
    report.audit_permanent_skipped = outcome_counts.permanent_skip
    report.audit_retryable_failed = outcome_counts.retryable_failure
    report.audit_remote_changed = outcome_counts.remote_changed
    report.audit_unaccounted = unaccounted
    report.audit_accounted = accounted
    report.metadata_accounted = metadata_accounted
    report.metadata_unaccounted = metadata_unaccounted
    report.audit_invariant_errors = 0

    if unaccounted ~= 0 or metadata_unaccounted ~= 0 then
        report.audit_invariant_errors = 1
        report.errors = (report.errors or 0) + 1
    end
end

Audit.EXAMPLE_LIMIT = EXAMPLE_LIMIT
Audit._materializationReason = materializationReason
Audit._lookupReason = lookupReason
Audit._countKeys = countKeys

return Audit
