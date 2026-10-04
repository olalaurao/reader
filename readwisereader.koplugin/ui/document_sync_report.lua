-- SPDX-License-Identifier: AGPL-3.0-only

local Report = {}

local function sortedKeys(map)
    local keys = {}
    for key, value in pairs(map or {}) do
        if tonumber(value) and value > 0 then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

local function sortedReasonKeys(groups)
    local keys = {}
    for key, group in pairs(groups or {}) do
        if type(group) == "table" and (tonumber(group.count) or 0) > 0 then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

local function appendCountMap(lines, heading, total, map, _)
    lines[#lines + 1] = string.format(_("%s: %d"), heading, total or 0)
    for _, key in ipairs(sortedKeys(map)) do
        lines[#lines + 1] = string.format("  %s: %d", key, map[key])
    end
end

local function appendReasonGroups(lines, heading, total, groups, _)
    lines[#lines + 1] = string.format(_("%s: %d"), heading, total or 0)
    for _, reason in ipairs(sortedReasonKeys(groups)) do
        local group = groups[reason]
        lines[#lines + 1] = string.format("  %s: %d", reason, group.count or 0)
        for _, example in ipairs(group.examples or {}) do
            lines[#lines + 1] = "    - " .. tostring(example)
        end
        local hidden = (group.count or 0) - #(group.examples or {})
        if hidden > 0 then
            lines[#lines + 1] = string.format(_("    + %d more"), hidden)
        end
    end
end

function Report.text(report, gettext)
    local _ = gettext or function(value) return value end
    report = report or {}

    local eligible = report.eligible_documents or report.eligible_metadata or 0
    local accounted = report.audit_accounted
    if accounted == nil then
        accounted = eligible - (report.audit_unaccounted or 0)
    end

    local lines = {
        _("DOCUMENT SYNC AUDIT"),
        string.format(_("Remote parent documents seen: %d"), report.metadata_seen or 0),
        string.format(_("Child records ignored: %d"), report.child_records or 0),
        string.format(_("Eligible for current filters: %d"), eligible),
        string.format(_("Already local: %d"), report.audit_already_local or report.unchanged or 0),
        string.format(_("Downloaded: %d"), report.audit_downloaded or report.downloaded or 0),
        string.format(_("Eligible but not downloadable: %d"), report.audit_permanent_skipped or report.nonretryable_skipped or 0),
        string.format(_("Temporary failures: %d"), report.audit_retryable_failed or report.retryable_item_errors or 0),
        string.format(_("Remote changed during scan: %d"), report.audit_remote_changed or 0),
        string.format(_("Unaccounted eligible: %d"), report.audit_unaccounted or 0),
        string.format(_("Accounted eligible: %d / %d"), accounted, eligible),
        string.format(
            _("Metadata accounted: %d / %d"),
            report.metadata_accounted or 0,
            report.metadata_seen or 0
        ),
        string.format(_("Active filters: %s"), report.filter_scope or _("unknown")),
        "",
    }

    appendCountMap(
        lines,
        _("Location not selected"),
        report.excluded_location_total or 0,
        report.excluded_by_location,
        _
    )
    appendCountMap(
        lines,
        _("Category not selected"),
        report.excluded_category_total or 0,
        report.excluded_by_category,
        _
    )
    appendCountMap(
        lines,
        _("Unsupported category"),
        report.unsupported_category_total or 0,
        report.unsupported_by_category,
        _
    )

    lines[#lines + 1] = ""
    lines[#lines + 1] = _("CONTENT LIST RECONCILIATION")
    lines[#lines + 1] = string.format(_("Eligible returned by content LIST: %d"), report.content_scan_eligible_seen or 0)
    lines[#lines + 1] = string.format(_("Missing from content LIST: %d"), report.content_scan_missing or 0)
    lines[#lines + 1] = string.format(_("Direct id reads: %d"), report.content_scan_direct_reads or 0)
    lines[#lines + 1] = string.format(_("Recovered by direct id read: %d"), report.content_scan_direct_recovered or 0)
    lines[#lines + 1] = string.format(_("Direct id read failures: %d"), report.content_scan_direct_failed or 0)
    lines[#lines + 1] = string.format(_("Remote changes observed during reconciliation: %d"), report.content_scan_remote_changed or 0)

    lines[#lines + 1] = ""
    appendReasonGroups(
        lines,
        _("Not downloadable by reason"),
        report.audit_permanent_skipped or report.nonretryable_skipped or 0,
        report.materialization_skip_reasons,
        _
    )
    appendReasonGroups(
        lines,
        _("Temporary failures by reason"),
        report.audit_retryable_failed or report.retryable_item_errors or 0,
        report.retryable_error_reasons,
        _
    )

    local lookup_total = 0
    for _, group in pairs(report.content_lookup_failure_reasons or {}) do
        lookup_total = lookup_total + (tonumber(group.count) or 0)
    end
    appendReasonGroups(
        lines,
        _("Direct lookup failures by reason"),
        lookup_total,
        report.content_lookup_failure_reasons,
        _
    )

    if (report.audit_invariant_errors or 0) > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = _("AUDIT INVARIANT FAILED: at least one eligible or metadata document was not accounted for. The watermark must not advance.")
    end

    return table.concat(lines, "\n")
end

Report._sortedKeys = sortedKeys
Report._sortedReasonKeys = sortedReasonKeys

return Report
