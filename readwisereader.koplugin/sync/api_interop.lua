-- SPDX-License-Identifier: AGPL-3.0-only

local ApiInterop = {}
ApiInterop.__index = ApiInterop

local PHRASE = "Gate Eight exact highlight phrase for KOReader interoperability testing."
local INITIAL_NOTE = "gate8 initial [[Foucault]]"
local V3_NOTE = "gate8 updated through Reader v3 [[Foucault]]"
local V2_NOTE = "gate8 updated through Readwise v2 [[Foucault]]"
local TAG = "koreader-gate8"

local KEYS = {
    stage = "gate8_stage",
    started_at = "gate8_started_at",
    parent_id = "gate8_parent_id",
    highlight_id = "gate8_highlight_id",
    v2_id = "gate8_v2_id",
}

local function errorResult(kind, message, retryable)
    return nil, {
        kind = kind,
        retryable = retryable == true,
        message = message,
    }
end

local function hasTag(tags, wanted)
    for _, tag in ipairs(tags or {}) do
        if tag == wanted then return true end
        if type(tag) == "table" and tag.name == wanted then return true end
    end
    return false
end

local function isNotFound(err)
    return err and (
        err.kind == "not_found"
        or (err.kind == "client" and tonumber(err.status) == 404)
    )
end

function ApiInterop:new(options)
    options = options or {}
    return setmetatable({
        reader = assert(options.reader, "reader is required"),
        readwise = assert(options.readwise, "readwise is required"),
        meta = assert(options.meta, "sync meta is required"),
        sleep = options.sleep or function(seconds) require("socket").sleep(seconds) end,
        utc_now = options.utc_now or function() return os.date("!%Y-%m-%dT%H:%M:%SZ") end,
        stamp = options.stamp or function()
            return string.format("%.6f", require("socket").gettime()):gsub("[^0-9]", "")
        end,
    }, self)
end

function ApiInterop:_state()
    return {
        stage = self.meta:get(KEYS.stage),
        started_at = self.meta:get(KEYS.started_at),
        parent_id = self.meta:get(KEYS.parent_id),
        highlight_id = self.meta:get(KEYS.highlight_id),
        v2_id = tonumber(self.meta:get(KEYS.v2_id)),
    }
end

function ApiInterop:_requireState(min_stage)
    local state = self:_state()
    local rank = {
        parent_created = 0.5,
        created = 1,
        v3_updated = 2,
        v2_updated = 3,
        cleanup_pending = 4,
    }
    if not state.parent_id or not state.highlight_id or not state.started_at then
        return nil, {
            kind = "gate8_state",
            retryable = false,
            message = "Gate 8 disposable state is missing. Start again from step 1.",
        }
    end
    if min_stage and (rank[state.stage] or 0) < (rank[min_stage] or 0) then
        return nil, {
            kind = "gate8_state",
            retryable = false,
            message = "Gate 8 steps must be run in order.",
        }
    end
    return state
end

function ApiInterop:clearState()
    for _, key in pairs(KEYS) do
        self.meta:delete(key)
    end
end

function ApiInterop:_cleanupParent(parent_id)
    if not parent_id then return true end
    local ok, err = self.reader:deleteDocument(parent_id)
    if ok or isNotFound(err) then return true end
    return nil, err
end

function ApiInterop:_waitParentReady(parent_id, attempts)
    local last_err
    for _ = 1, attempts or 5 do
        local document, err = self.reader:getDocument(parent_id, true, false)
        if document and type(document.html_content) == "string"
            and document.html_content:find(PHRASE, 1, true) then
            return document
        end
        last_err = err
    end
    return nil, last_err or {
        kind = "gate8_parent_not_ready",
        retryable = true,
        message = "Disposable Reader document did not become highlightable in time.",
    }
end

function ApiInterop:create()
    local existing = self:_state()
    if existing.parent_id or existing.highlight_id then
        return errorResult(
            "gate8_state",
            "A Gate 8 disposable document is already active. Continue or clean it up before starting again.",
            false
        )
    end

    local started_at = self.utc_now()
    local stamp = self.stamp()
    local parent, parent_err = self.reader:saveDocument{
        url = "https://readwisereader-koplugin.invalid/gate8/" .. stamp,
        html = "<article><h1>KOReader Gate 8 disposable</h1><p>"
            .. PHRASE
            .. "</p><p>This document exists only for API interoperability testing.</p></article>",
        should_clean_html = false,
        title = "KOReader Gate 8 disposable " .. stamp,
        author = "KOReader Readwise Reader",
        category = "article",
        location = "new",
        saved_using = "KOReader Gate 8",
        tags = { TAG },
    }
    if not parent then return nil, parent_err end

    -- Persist the disposable parent immediately so the recovery action still
    -- knows exactly what to clean if the user cancels while Reader is parsing.
    self.meta:setMany{
        [KEYS.stage] = "parent_created",
        [KEYS.started_at] = started_at,
        [KEYS.parent_id] = parent.id,
    }

    local ready, ready_err = self:_waitParentReady(parent.id, 5)
    if not ready then
        local cleaned = self:_cleanupParent(parent.id)
        if cleaned then self:clearState() end
        return nil, ready_err
    end

    local highlight, highlight_err = self.reader:createHighlight(
        parent.id,
        PHRASE,
        INITIAL_NOTE,
        { TAG }
    )
    if not highlight then
        local cleaned = self:_cleanupParent(parent.id)
        if cleaned then self:clearState() end
        return nil, highlight_err
    end

    -- Store the child ID before any follow-up read so cancellation/failure
    -- can never strand an unknown disposable highlight.
    self.meta:setMany{
        [KEYS.stage] = "created",
        [KEYS.started_at] = started_at,
        [KEYS.parent_id] = parent.id,
        [KEYS.highlight_id] = highlight.id,
    }

    local child, child_err = self.reader:getDocument(highlight.id, false, false)
    if not child then
        return nil, child_err
    end

    return {
        stage = "created",
        parent_id = parent.id,
        highlight_id = highlight.id,
        v3_category = child.category,
        v3_parent_matches = child.parent_id == parent.id,
        v3_note_matches = child.notes == INITIAL_NOTE,
        v3_tag_matches = hasTag(child.tags, TAG),
        highlight_offset_present = child.highlight_offset ~= nil,
        highlight_location_present = child.highlight_location ~= nil,
        expected_initial_note = INITIAL_NOTE,
        expected_tag = TAG,
    }
end

function ApiInterop:_findV2Mapping(state)
    local attempts = 5
    local last_count = 0
    for attempt = 1, attempts do
        local page, err = self.readwise:listHighlights{
            page_size = 1000,
            updated_after = state.started_at,
        }
        if not page then return nil, err end
        last_count = #page.results
        for _, highlight in ipairs(page.results) do
            if highlight.external_id == state.highlight_id then
                return {
                    id = highlight.id,
                    method = "highlight.external_id",
                    book_id = highlight.book_id,
                    external_id = highlight.external_id,
                    text_matches = highlight.text == PHRASE,
                    note = highlight.note,
                    color = highlight.color,
                    attempts = attempt,
                    candidates = last_count,
                }
            end
        end
        if attempt < attempts then self.sleep(3.2) end
    end

    local export_page, export_err = self.readwise:exportUpdated{
        updated_after = state.started_at,
        include_deleted = true,
    }
    if not export_page then return nil, export_err end

    local fallback_candidate
    for _, book in ipairs(export_page.results) do
        if book.source == "reader" and book.external_id == state.parent_id then
            for _, raw_highlight in ipairs(book.highlights or {}) do
                if raw_highlight.external_id == state.highlight_id then
                    return {
                        id = tonumber(raw_highlight.id),
                        method = "export.parent_external_id+highlight.external_id",
                        book_id = tonumber(raw_highlight.book_id or book.user_book_id),
                        external_id = raw_highlight.external_id,
                        text_matches = raw_highlight.text == PHRASE,
                        note = raw_highlight.note,
                        color = raw_highlight.color,
                        attempts = attempts,
                        candidates = last_count,
                    }
                end
                if raw_highlight.text == PHRASE
                    and (raw_highlight.note == INITIAL_NOTE or raw_highlight.note == V3_NOTE)
                    and not fallback_candidate then
                    fallback_candidate = {
                        id = tonumber(raw_highlight.id),
                        method = "export.parent_external_id+text+note_only",
                        book_id = tonumber(raw_highlight.book_id or book.user_book_id),
                        external_id = raw_highlight.external_id,
                        text_matches = true,
                        note = raw_highlight.note,
                        color = raw_highlight.color,
                        attempts = attempts,
                        candidates = last_count,
                        deterministic = false,
                    }
                end
            end
        end
    end
    return fallback_candidate, fallback_candidate and nil or {
        kind = "gate8_mapping",
        retryable = true,
        message = "No Readwise v2 representation of the Reader highlight was found yet.",
    }
end

function ApiInterop:probeAndUpdateV3()
    local state, state_err = self:_requireState("created")
    if not state then return nil, state_err end

    local child, child_err = self.reader:getDocument(state.highlight_id, false, false)
    if not child then return nil, child_err end

    local mapping, mapping_err = self:_findV2Mapping(state)
    if not mapping then return nil, mapping_err end

    if mapping.deterministic == false then
        return nil, {
            kind = "gate8_mapping_ambiguous",
            retryable = false,
            message = "A v2 candidate was found only by parent/text/note, not by deterministic external_id mapping.",
            mapping = mapping,
        }
    end

    self.meta:set(KEYS.v2_id, tostring(mapping.id))

    local updated, update_err = self.reader:updateDocument(state.highlight_id, {
        notes = V3_NOTE,
        tags = { TAG, "gate8-v3-updated" },
    })
    if not updated then return nil, update_err end

    local after, after_err = self.reader:getDocument(state.highlight_id, false, false)
    if not after then return nil, after_err end

    self.meta:set(KEYS.stage, "v3_updated")
    return {
        stage = "v3_updated",
        v2_id = mapping.id,
        mapping_method = mapping.method,
        v2_external_id_matches_reader_child = mapping.external_id == state.highlight_id,
        v2_text_matches = mapping.text_matches == true,
        v3_category = child.category,
        v3_parent_matches = child.parent_id == state.parent_id,
        v3_note_before = child.notes,
        v3_note_after = after.notes,
        v3_note_update_verified = after.notes == V3_NOTE,
        v3_tag_update_verified = hasTag(after.tags, "gate8-v3-updated"),
        highlight_offset_present = after.highlight_offset ~= nil,
        highlight_location_present = after.highlight_location ~= nil,
        expected_v3_note = V3_NOTE,
    }
end

function ApiInterop:updateViaV2()
    local state, state_err = self:_requireState("v3_updated")
    if not state then return nil, state_err end
    if not state.v2_id then
        return errorResult(
            "gate8_mapping",
            "A deterministic Readwise v2 highlight id has not been established.",
            false
        )
    end

    local v2, v2_err = self.readwise:updateHighlight(state.v2_id, {
        note = V2_NOTE,
        color = "green",
    })
    if not v2 then return nil, v2_err end

    local v3_after
    local last_err
    for attempt = 1, 4 do
        v3_after, last_err = self.reader:getDocument(state.highlight_id, false, false)
        if v3_after and v3_after.notes == V2_NOTE then break end
        if attempt < 4 then self.sleep(2) end
    end
    if not v3_after then return nil, last_err end

    self.meta:set(KEYS.stage, "v2_updated")
    return {
        stage = "v2_updated",
        v2_id = state.v2_id,
        v2_note_update_response_matches = v2.note == V2_NOTE,
        v2_color_update_response_matches = v2.color == "green",
        v3_saw_v2_note_update = v3_after.notes == V2_NOTE,
        v3_note_after_v2 = v3_after.notes,
        expected_v2_note = V2_NOTE,
        expected_color = "green",
    }
end

function ApiInterop:deleteAndCleanup()
    local state, state_err = self:_requireState("created")
    if not state then return nil, state_err end

    local report = {
        stage = "cleanup",
        v3_delete_success = false,
        v3_missing_after_delete = false,
        v2_missing_after_v3_delete = false,
        v2_still_visible_after_v3_delete = false,
        v2_delete_used = false,
        parent_cleanup_success = false,
    }

    local deleted, delete_err = self.reader:deleteDocument(state.highlight_id)
    report.v3_delete_success = deleted == true
    report.v3_delete_error = delete_err and delete_err.kind or nil

    if deleted then
        local child, child_err = self.reader:getDocument(state.highlight_id, false, false)
        report.v3_missing_after_delete = child == nil and isNotFound(child_err)
    end

    if state.v2_id then
        local last_v2
        local last_v2_err
        for attempt = 1, 4 do
            if attempt > 1 then self.sleep(2) end
            last_v2, last_v2_err = self.readwise:getHighlight(state.v2_id)
            if last_v2 == nil and isNotFound(last_v2_err) then
                report.v2_missing_after_v3_delete = true
                break
            end
        end

        if not report.v2_missing_after_v3_delete then
            if last_v2 then
                report.v2_still_visible_after_v3_delete = true
                report.v2_detail_is_deleted = last_v2.is_deleted == true
                local v2_deleted, v2_delete_err = self.readwise:deleteHighlight(state.v2_id)
                report.v2_delete_used = true
                report.v2_delete_success = v2_deleted == true
                report.v2_delete_error = v2_delete_err and v2_delete_err.kind or nil
            else
                report.v2_probe_error = last_v2_err and last_v2_err.kind or "unknown"
            end
        end
    end

    local parent_ok, parent_err = self:_cleanupParent(state.parent_id)
    report.parent_cleanup_success = parent_ok == true
    report.parent_cleanup_error = parent_err and parent_err.kind or nil

    if report.parent_cleanup_success then
        self:clearState()
    else
        self.meta:set(KEYS.stage, "cleanup_pending")
    end
    return report
end

function ApiInterop:cleanup()
    local state = self:_state()
    local report = {
        highlight_cleanup = true,
        v2_cleanup = true,
        parent_cleanup = true,
    }

    if state.highlight_id then
        local ok, err = self.reader:deleteDocument(state.highlight_id)
        if not ok and not isNotFound(err) then
            report.highlight_cleanup = false
            report.highlight_error = err and err.kind or "unknown"
        end
    end
    if state.v2_id then
        local ok, err = self.readwise:deleteHighlight(state.v2_id)
        if not ok and not isNotFound(err) then
            report.v2_cleanup = false
            report.v2_error = err and err.kind or "unknown"
        end
    end
    if state.parent_id then
        local ok, err = self:_cleanupParent(state.parent_id)
        if not ok then
            report.parent_cleanup = false
            report.parent_error = err and err.kind or "unknown"
        end
    end

    if report.highlight_cleanup and report.v2_cleanup and report.parent_cleanup then
        self:clearState()
        report.cleared = true
    end
    return report
end

ApiInterop.PHRASE = PHRASE
ApiInterop.INITIAL_NOTE = INITIAL_NOTE
ApiInterop.V3_NOTE = V3_NOTE
ApiInterop.V2_NOTE = V2_NOTE
ApiInterop.TAG = TAG
ApiInterop.KEYS = KEYS
ApiInterop._hasTag = hasTag
ApiInterop._isNotFound = isNotFound

return ApiInterop
