-- SPDX-License-Identifier: AGPL-3.0-only

local Report = require("ui/document_sync_report")

return function()
    local text = Report.text({
        metadata_seen = 12,
        child_records = 2,
        eligible_documents = 5,
        audit_accounted = 5,
        audit_already_local = 2,
        audit_downloaded = 1,
        audit_permanent_skipped = 1,
        audit_retryable_failed = 0,
        audit_remote_changed = 1,
        audit_unaccounted = 0,
        metadata_accounted = 12,
        filter_scope = "locations=new;categories=article,pdf",
        excluded_location_total = 2,
        excluded_by_location = { archive = 2 },
        excluded_category_total = 2,
        excluded_by_category = { epub = 2 },
        unsupported_category_total = 3,
        unsupported_by_category = { email = 1, rss = 2 },
        content_scan_eligible_seen = 2,
        content_scan_missing = 3,
        content_scan_direct_reads = 3,
        content_scan_direct_recovered = 2,
        content_scan_direct_failed = 1,
        content_scan_remote_changed = 1,
        materialization_skip_reasons = {
            ["article / processed HTML missing"] = {
                count = 4,
                examples = { "A", "B", "C" },
            },
        },
        content_lookup_failure_reasons = {
            ["pdf / direct lookup timeout"] = {
                count = 1,
                examples = { "Missing PDF" },
            },
        },
        retryable_error_reasons = {},
    }, function(value) return value end)

    assert(text:find("DOCUMENT SYNC AUDIT", 1, true))
    assert(text:find("Child records ignored: 2", 1, true))
    assert(text:find("Eligible for current filters: 5", 1, true))
    assert(text:find("Accounted eligible: 5 / 5", 1, true))
    assert(text:find("Location not selected: 2", 1, true))
    assert(text:find("archive: 2", 1, true))
    assert(text:find("Category not selected: 2", 1, true))
    assert(text:find("epub: 2", 1, true))
    assert(text:find("Unsupported category: 3", 1, true))
    assert(text:find("email: 1", 1, true))
    assert(text:find("rss: 2", 1, true))
    assert(text:find("Missing from content LIST: 3", 1, true))
    assert(text:find("Recovered by direct id read: 2", 1, true))
    assert(text:find("article / processed HTML missing: 4", 1, true))
    assert(text:find("- A", 1, true))
    assert(text:find("+ 1 more", 1, true))
    assert(text:find("pdf / direct lookup timeout: 1", 1, true))

    local broken = Report.text({
        metadata_seen = 2,
        eligible_documents = 2,
        audit_accounted = 1,
        audit_unaccounted = 1,
        metadata_accounted = 2,
        audit_invariant_errors = 1,
    }, function(value) return value end)
    assert(broken:find("Unaccounted eligible: 1", 1, true))
    assert(broken:find("AUDIT INVARIANT FAILED", 1, true))
end
