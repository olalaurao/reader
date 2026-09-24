-- SPDX-License-Identifier: AGPL-3.0-only

local Refresh = {}

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Refresh.normalizeVisible(html, Html, TextMatch)
    if type(html) ~= "string" then return nil end
    local fragment = Html and Html._bodyFragment
        and Html._bodyFragment(html) or html
    local visible = TextMatch.visibleText(fragment)
    visible = visible:gsub("%s+", " ")
    return trim(visible)
end

function Refresh.decide(input)
    input = input or {}

    if input.local_present ~= true then
        return "block_local_missing"
    end

    local category = tostring(input.category or "")
    local local_format = tostring(input.local_format or "")

    if (category == "pdf" or category == "epub")
        and local_format ~= "html" then
        return "defer_raw_keep_local"
    end

    if input.comparison == "same" then
        return "same_visible_text_keep_local"
    end

    if input.comparison == "different" then
        if input.has_reading_state == true then
            return "defer_changed_text_reading_state"
        end
        -- Replacement without reading state has not yet passed the target-PW3
        -- position/sidecar spike either. V1 remains conservative until it does.
        return "defer_changed_text_unproven"
    end

    if input.pending == true or input.remote_revision_changed == true then
        return "defer_unverified_keep_local"
    end

    return "no_refresh_evidence"
end

function Refresh.isReplacementAllowed()
    -- Gate 15 safety baseline: no automatic replacement of an existing local
    -- document until the format-specific physical stability spike has passed.
    return false
end

return Refresh
