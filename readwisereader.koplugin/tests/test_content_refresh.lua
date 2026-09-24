-- SPDX-License-Identifier: AGPL-3.0-only

local Refresh = require("sync/content_refresh")

return function()
    local Html = {
        _bodyFragment = function(value)
            return value:match("<body>(.*)</body>") or value
        end,
    }
    local TextMatch = {
        visibleText = function(value)
            return value:gsub("<[^>]+>", "")
        end,
    }

    assert(
        Refresh.normalizeVisible(
            "<html><body><p>Hello   world</p></body></html>",
            Html,
            TextMatch
        ) == "Hello world"
    )
    assert(Refresh.compareVisible(
        "<html><body><p>Hello   world</p></body></html>",
        "<p>Hello world</p>",
        Html,
        TextMatch
    ) == "same")
    assert(Refresh.compareVisible(
        "<p>Hello world</p>",
        "<p>Hello changed world</p>",
        Html,
        TextMatch
    ) == "different")

    assert(Refresh.isReplacementAllowed() == false)
    assert(Refresh.decide{
        local_present = false,
        category = "article",
        local_format = "html",
    } == "block_local_missing")

    assert(Refresh.decide{
        local_present = true,
        category = "pdf",
        local_format = "pdf",
        pending = true,
    } == "defer_raw_keep_local")

    assert(Refresh.decide{
        local_present = true,
        category = "article",
        local_format = "html",
        comparison = "same",
        has_reading_state = true,
    } == "same_visible_text_keep_local")

    assert(Refresh.decide{
        local_present = true,
        category = "article",
        local_format = "html",
        comparison = "different",
        has_reading_state = true,
    } == "defer_changed_text_reading_state")

    assert(Refresh.decide{
        local_present = true,
        category = "article",
        local_format = "html",
        comparison = "different",
        has_reading_state = false,
    } == "defer_changed_text_unproven")

    assert(Refresh.decide{
        local_present = true,
        category = "article",
        local_format = "html",
        pending = true,
        comparison = "unavailable",
    } == "defer_unverified_keep_local")

    assert(Refresh.decide{
        local_present = true,
        category = "article",
        local_format = "html",
        pending = false,
        remote_revision_changed = false,
        comparison = "not_run",
    } == "no_refresh_evidence")
end
