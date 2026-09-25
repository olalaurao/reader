-- SPDX-License-Identifier: AGPL-3.0-only

local Constants = require("constants")
local Hash = require("content/hash")
local InfoMessage = require("ui/widget/infomessage")
local Locator = require("koreader/remote_highlight_locator")
local TextMatch = require("sync/text_match")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Worker = require("sync/remote_highlight_probe_worker")
local _ = require("gettext")

local UI = {}
UI.__index = UI

local MAX_IMPORTS_PER_RUN = Constants.REMOTE_HIGHLIGHT_IMPORT_MAX_PER_SYNC or 20
local MAX_LOCATOR_ATTEMPTS_PER_RUN =
    Constants.REMOTE_HIGHLIGHT_IMPORT_MAX_LOCATOR_ATTEMPTS or 30

local function domainError(kind, message)
    return { kind = kind, retryable = false, message = message }
end

local function stateKey(prefix, reader_document_id)
    return prefix .. tostring(reader_document_id)
end

local function remoteIdSignature(remote_id)
    return Hash.sha256("reader-highlight-id\0" .. tostring(remote_id or ""))
end

local function textSignature(text)
    return Hash.sha256(
        "reader-highlight-text\0"
            .. TextMatch.canonicalPlainText(text)
    )
end

local function decodeUnresolved(value)
    local out = {}
    if type(value) ~= "string" or value == "" then return out end
    for line in value:gmatch("[^\n]+") do
        local id_hash, text_hash = line:match("^([^\t]+)\t([^\t]+)$")
        if id_hash and text_hash then out[id_hash] = text_hash end
    end
    return out
end

local function encodeUnresolved(values)
    local keys = {}
    for key, value in pairs(values or {}) do
        if type(key) == "string" and key ~= ""
            and type(value) == "string" and value ~= "" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    if #keys == 0 then return nil end
    local lines = {}
    for _, key in ipairs(keys) do
        lines[#lines + 1] = key .. "\t" .. values[key]
    end
    return table.concat(lines, "\n")
end

local function sameNote(a, b)
    if a == nil then a = "" end
    if b == nil then b = "" end
    return a == b
end

local function rollbackLocal(reader_ui, index)
    local deleted = pcall(reader_ui.highlight.deleteHighlight, reader_ui.highlight, index)
    local saved = pcall(reader_ui.saveSettings, reader_ui)
    return deleted and saved
end

local function exactLocalAt(reader_ui, locator)
    for index, item in ipairs(reader_ui.annotation.annotations or {}) do
        if item.drawer ~= nil
            and item.pos0 == locator.pos0
            and item.pos1 == locator.pos1 then
            return index, item
        end
    end
end

local function orderedCandidates(highlights)
    local out = {}
    for pass_index, wants_note in ipairs({ true, false }) do
        for item_index, item in ipairs(highlights or {}) do
            if (item.note_present == true) == wants_note then
                out[#out + 1] = item
            end
        end
    end
    return out
end

local function rotateAfter(items, cursor_id)
    local out = {}
    if #items == 0 then return out end

    local cursor_index
    if type(cursor_id) == "string" and cursor_id ~= "" then
        for index, item in ipairs(items) do
            if item.remote and item.remote.id == cursor_id then
                cursor_index = index
                break
            end
        end
    end

    local start = cursor_index and (cursor_index % #items) + 1 or 1
    for offset = 0, #items - 1 do
        local index = ((start + offset - 1) % #items) + 1
        out[#out + 1] = items[index]
    end
    return out
end

local function newBatchReport(remote_report)
    return {
        status = "ok",
        scan_mode = remote_report.updated_after and "incremental" or "historical",
        reader_highlights = remote_report.parent_highlight_records or 0,
        highlights_with_text = #(remote_report.remote_highlights or {}),
        imported = 0,
        notes_imported = 0,
        linked_skipped = 0,
        collisions_linked = 0,
        local_collisions = 0,
        collision_conflicts = 0,
        unresolved_collision_risk = 0,
        persisted_guard_matches = 0,
        locator_attempts = 0,
        ambiguous = 0,
        missing = 0,
        invalid = 0,
        deferred_by_limit = 0,
        failures = 0,
        remote_writes = 0,
        suppress_outbound_ids = {},
        suppress_current_document = false,
    }
end

local function addLocatorFailure(result, status)
    if status == "ambiguous" then
        result.ambiguous = result.ambiguous + 1
    elseif status == "missing" then
        result.missing = result.missing + 1
    else
        result.invalid = result.invalid + 1
    end
end

local function addSuppressedId(result, local_annotation_id)
    if type(local_annotation_id) ~= "string" or local_annotation_id == "" then
        result.suppress_current_document = true
        return
    end
    result._suppressed_set = result._suppressed_set or {}
    if not result._suppressed_set[local_annotation_id] then
        result._suppressed_set[local_annotation_id] = true
        result.suppress_outbound_ids[#result.suppress_outbound_ids + 1] =
            local_annotation_id
    end
end

local function summaryLines(result, title)
    return {
        title or _("Reader → KOReader highlight import"),
        "",
        string.format(_("Scan mode: %s"), result.scan_mode or _("unknown")),
        string.format(_("Imported local highlights: %d"), result.imported or 0),
        string.format(_("Imported notes preserved: %d"), result.notes_imported or 0),
        string.format(_("Reader highlights for document: %d"), result.reader_highlights or 0),
        string.format(_("Reader highlights with text: %d"), result.highlights_with_text or 0),
        string.format(_("Remote highlights already linked/skipped: %d"), result.linked_skipped or 0),
        string.format(_("Existing local highlights linked safely: %d"), result.collisions_linked or 0),
        string.format(_("Exact local-position collisions skipped: %d"), result.local_collisions or 0),
        string.format(_("Local/Reader collision conflicts: %d"), result.collision_conflicts or 0),
        string.format(_("Unresolved local/Reader collision risks: %d"), result.unresolved_collision_risk or 0),
        string.format(_("Persisted unresolved guards matched locally: %d"), result.persisted_guard_matches or 0),
        string.format(_("Locator attempts: %d"), result.locator_attempts or 0),
        string.format(_("Ambiguous locator matches skipped: %d"), result.ambiguous or 0),
        string.format(_("Missing locator matches skipped: %d"), result.missing or 0),
        string.format(_("Invalid/different locator matches skipped: %d"), result.invalid or 0),
        string.format(_("Unlinked highlights deferred by batch limit: %d"), result.deferred_by_limit or 0),
        string.format(_("Import failures: %d"), result.failures or 0),
        string.format(_("Outbound creates suppressed for collision safety: %d"),
            #(result.suppress_outbound_ids or {})),
        _("Remote writes from import: none"),
    }
end

function UI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        importer = assert(options.importer, "importer is required"),
        sync_meta = assert(options.sync_meta, "sync_meta is required"),
        get_current_path = assert(options.get_current_path, "get_current_path is required"),
        get_reader_ui = assert(options.get_reader_ui, "get_reader_ui is required"),
        worker = options.worker or Worker,
        max_imports = options.max_imports or MAX_IMPORTS_PER_RUN,
        max_locator_attempts =
            options.max_locator_attempts or MAX_LOCATOR_ATTEMPTS_PER_RUN,
    }, self)
end

function UI:getMenuItem()
    return {
        text = _("Import Reader highlights (current document)"),
        keep_menu_open = true,
        callback = function() self:run() end,
    }
end

function UI:_readerContext(path)
    local current_path = self.get_current_path()
    local reader_ui = self.get_reader_ui()
    if type(path) ~= "string" or path == "" or current_path ~= path
        or not reader_ui or not reader_ui.document or not reader_ui.highlight
        or not reader_ui.annotation then
        return nil, nil, domainError(
            "document",
            "Open the same Readwise-managed EPUB before importing highlights."
        )
    end
    if not reader_ui.rolling then
        return nil, nil, domainError(
            "format",
            "Reader highlight import currently supports rolling EPUB/HTML documents only."
        )
    end
    if type(reader_ui.saveSettings) ~= "function" then
        return nil, nil, domainError(
            "save",
            "KOReader save-settings API is unavailable; no highlight was imported."
        )
    end

    local document, document_err = self.importer:getDocument(path)
    if not document then
        return nil, nil, document_err
    end
    return reader_ui, document
end

function UI:_preflight()
    if not self.config:hasAccessToken() then
        UIManager:show(InfoMessage:new{ text = _("No access token is configured.") })
        return nil
    end
    if not NetworkMgr:isOnline() then
        UIManager:show(InfoMessage:new{
            text = _("No internet connection. Turn Wi-Fi on outside the plugin and try again."),
        })
        return nil
    end

    local path = self.get_current_path()
    local reader_ui, document, context_err = self:_readerContext(path)
    if not reader_ui then
        UIManager:show(InfoMessage:new{ text = context_err.message })
        return nil
    end
    return path, reader_ui, document
end

function UI:_scanState(document)
    local id = document.reader_id
    local baseline_key = stateKey("remote_highlight_baseline:", id)
    local watermark_key = stateKey("remote_highlight_watermark:", id)
    local query_key = stateKey("remote_highlight_query_after:", id)
    local cursor_key = stateKey("remote_highlight_cursor:", id)
    local unresolved_key = stateKey("remote_highlight_unresolved:", id)

    local baseline = self.sync_meta:get(baseline_key) == "1"
    local query_after = baseline and self.sync_meta:get(query_key) or nil
    if baseline and (type(query_after) ~= "string" or query_after == "") then
        baseline = false
        query_after = nil
    end

    return {
        baseline_key = baseline_key,
        watermark_key = watermark_key,
        query_key = query_key,
        cursor_key = cursor_key,
        unresolved_key = unresolved_key,
        unresolved = decodeUnresolved(self.sync_meta:get(unresolved_key)),
        baseline_complete = baseline,
        updated_after = query_after,
        cursor_id = self.sync_meta:get(cursor_key),
    }
end

function UI:_saveScanProgress(document, remote_report, result, scan_state)
    local unresolved_encoded = encodeUnresolved(scan_state.unresolved)
    if unresolved_encoded then
        self.sync_meta:set(scan_state.unresolved_key, unresolved_encoded)
    else
        self.sync_meta:delete(scan_state.unresolved_key)
    end

    if result.failures > 0 or result.suppress_current_document then
        return
    end

    if result.deferred_by_limit > 0 then
        if result.last_processed_remote_id then
            self.sync_meta:set(scan_state.cursor_key, result.last_processed_remote_id)
        end
        return
    end

    -- Never advance past an unresolved local/remote collision. Otherwise an
    -- unchanged historical Reader child would disappear behind updatedAfter
    -- on the next Sync and the outbound create guard could no longer prove
    -- that the corresponding local annotation is safe to POST.
    if (result.collision_conflicts or 0) > 0 then
        self.sync_meta:delete(scan_state.cursor_key)
        return
    end

    self.sync_meta:delete(scan_state.cursor_key)
    local started_at = remote_report.scan_started_at
    local query_after = remote_report.proposed_query_after
    if type(started_at) == "string" and started_at ~= ""
        and type(query_after) == "string" and query_after ~= "" then
        self.sync_meta:setMany({
            [scan_state.baseline_key] = "1",
            [scan_state.watermark_key] = started_at,
            [scan_state.query_key] = query_after,
        })
    end
end

function UI:_createAndLink(path, reader_ui, remote, locator)
    local previous_selected = reader_ui.highlight.selected_text
    local previous_hold = reader_ui.highlight.hold_pos
    reader_ui.highlight.hold_pos = nil
    reader_ui.highlight.selected_text = {
        text = locator.text,
        pos0 = locator.pos0,
        pos1 = locator.pos1,
        note = remote.notes,
    }

    local created_ok, index = pcall(
        reader_ui.highlight.saveHighlight,
        reader_ui.highlight,
        false
    )
    reader_ui.highlight.selected_text = previous_selected
    reader_ui.highlight.hold_pos = previous_hold

    if not created_ok or type(index) ~= "number"
        or not reader_ui.annotation.annotations[index] then
        return nil, domainError(
            "local_create",
            "KOReader could not create the local highlight. Nothing was written to Reader."
        )
    end

    local saved_ok = pcall(reader_ui.saveSettings, reader_ui)
    if not saved_ok then
        rollbackLocal(reader_ui, index)
        return nil, domainError(
            "sidecar",
            "KOReader could not persist the sidecar; the just-created local highlight was rolled back."
        )
    end

    local local_item = reader_ui.annotation.annotations[index]
    local link_call_ok, linked = pcall(
        self.importer.linkPersisted,
        self.importer,
        path,
        remote,
        local_item
    )
    if not link_call_ok or not linked then
        local rollback_ok = rollbackLocal(reader_ui, index)
        return nil, domainError(
            rollback_ok and "db" or "rollback",
            rollback_ok
                and "The remote/local identity link could not be persisted; the local import was rolled back."
                or "The identity link failed and local rollback also failed. Stop syncing and report this error."
        )
    end

    if linked.status == "already_linked" then
        local rollback_ok = rollbackLocal(reader_ui, index)
        if not rollback_ok then
            return nil, domainError(
                "rollback",
                "A remote-link race was detected and local rollback failed. Stop syncing and report this error."
            )
        end
        return { status = "already_linked_race" }
    end

    return {
        status = "linked",
        local_annotation_id = linked.local_annotation_id,
    }
end

function UI:_candidateStates(highlights)
    local states = {}
    for _, remote in ipairs(orderedCandidates(highlights)) do
        local call_ok, existing_link = pcall(
            self.importer.isRemoteLinked,
            self.importer,
            remote.id
        )
        if not call_ok then
            return nil, domainError(
                "db",
                "Could not read the durable Reader/local highlight links."
            )
        end
        states[#states + 1] = {
            remote = remote,
            existing_link = existing_link,
        }
    end
    return states
end

function UI:_applyPersistedUnresolvedGuards(
    path,
    reader_ui,
    scan_state,
    result
)
    local unresolved_texts = {}
    for _, signature in pairs(scan_state.unresolved or {}) do
        unresolved_texts[signature] = true
    end
    if next(unresolved_texts) == nil then return true end

    for _, item in ipairs(reader_ui.annotation.annotations or {}) do
        if item.drawer ~= nil
            and unresolved_texts[textSignature(item.text)] then
            local normalized, normalize_err =
                self.importer:normalizeLocal(path, item)
            if not normalized then
                result.failures = result.failures + 1
                result.status = "error"
                result.suppress_current_document = true
                return nil, normalize_err
            end

            local lookup_ok, local_link = pcall(
                self.importer.getLocalLink,
                self.importer,
                normalized.local_annotation_id
            )
            if not lookup_ok then
                result.failures = result.failures + 1
                result.status = "error"
                result.suppress_current_document = true
                return nil, domainError(
                    "db",
                    "Could not read the local annotation identity link."
                )
            end

            if not local_link or local_link.created_remote ~= true then
                addSuppressedId(result, normalized.local_annotation_id)
                result.persisted_guard_matches =
                    result.persisted_guard_matches + 1
                result.unresolved_collision_risk =
                    result.unresolved_collision_risk + 1
            end
        end
    end
    return true
end

function UI:_suppressLocalTextMatches(path, reader_ui, remote, result)
    local matched = 0
    for _, item in ipairs(reader_ui.annotation.annotations or {}) do
        if item.drawer ~= nil
            and TextMatch.equivalentPlainText(item.text, remote.content) then
            local normalized, normalize_err =
                self.importer:normalizeLocal(path, item)
            if not normalized then
                result.failures = result.failures + 1
                result.status = "error"
                result.suppress_current_document = true
                return nil, normalize_err
            end
            addSuppressedId(result, normalized.local_annotation_id)
            matched = matched + 1
        end
    end
    result.unresolved_collision_risk =
        result.unresolved_collision_risk + matched
    return true
end

function UI:_applyRemoteReport(path, reader_ui, document, remote_report, scan_state)
    local result = newBatchReport(remote_report)
    result.reader_document_id = document.reader_id

    local persisted_ok, persisted_err =
        self:_applyPersistedUnresolvedGuards(
            path,
            reader_ui,
            scan_state,
            result
        )
    if not persisted_ok then
        return result, persisted_err
    end

    local candidate_states, state_err =
        self:_candidateStates(remote_report.remote_highlights)
    if not candidate_states then
        result.failures = result.failures + 1
        result.status = "error"
        result.suppress_current_document = true
        return result, state_err
    end

    local rotated = rotateAfter(candidate_states, scan_state.cursor_id)

    for position, state in ipairs(rotated) do
        local remote = state.remote
        local remote_id_signature = remoteIdSignature(remote.id)
        local remote_text_signature = textSignature(remote.content)

        if state.existing_link then
            scan_state.unresolved[remote_id_signature] = nil
            result.linked_skipped = result.linked_skipped + 1
            result.last_processed_remote_id = remote.id
        else
            if result.imported >= self.max_imports
                or result.locator_attempts >= self.max_locator_attempts then
                for remaining = position, #rotated do
                    if not rotated[remaining].existing_link then
                        result.deferred_by_limit =
                            result.deferred_by_limit + 1
                    end
                end
                break
            end

            result.locator_attempts = result.locator_attempts + 1
            local locator, locator_status =
                Locator.findUnique(reader_ui, remote.content)

            if not locator then
                scan_state.unresolved[remote_id_signature] =
                    remote_text_signature
                addLocatorFailure(result, locator_status)
                local suppressed_ok, suppress_err =
                    self:_suppressLocalTextMatches(
                        path,
                        reader_ui,
                        remote,
                        result
                    )
                if not suppressed_ok then
                    return result, suppress_err
                end
            else
                local existing_index, existing_item =
                    exactLocalAt(reader_ui, locator)
                if existing_index then
                    result.local_collisions = result.local_collisions + 1
                    local normalized, normalize_err =
                        self.importer:normalizeLocal(path, existing_item)
                    if not normalized then
                        result.failures = result.failures + 1
                        result.status = "error"
                        result.suppress_current_document = true
                        return result, normalize_err
                    end

                    if sameNote(existing_item.note, remote.notes) then
                        local link_ok, linked = pcall(
                            self.importer.linkPersisted,
                            self.importer,
                            path,
                            remote,
                            existing_item
                        )
                        if link_ok and linked then
                            scan_state.unresolved[remote_id_signature] = nil
                            result.collisions_linked =
                                result.collisions_linked + 1
                        else
                            scan_state.unresolved[remote_id_signature] =
                                remote_text_signature
                            result.collision_conflicts =
                                result.collision_conflicts + 1
                            result.status = "partial"
                            addSuppressedId(
                                result,
                                normalized.local_annotation_id
                            )
                        end
                    else
                        scan_state.unresolved[remote_id_signature] =
                            remote_text_signature
                        result.collision_conflicts =
                            result.collision_conflicts + 1
                        result.status = "partial"
                        addSuppressedId(
                            result,
                            normalized.local_annotation_id
                        )
                    end
                else
                    local created, create_err = self:_createAndLink(
                        path,
                        reader_ui,
                        remote,
                        locator
                    )
                    if not created then
                        scan_state.unresolved[remote_id_signature] =
                            remote_text_signature
                        result.failures = result.failures + 1
                        result.status = "error"
                        result.suppress_current_document = true
                        return result, create_err
                    elseif created.status == "already_linked_race" then
                        scan_state.unresolved[remote_id_signature] = nil
                        result.linked_skipped =
                            result.linked_skipped + 1
                    else
                        scan_state.unresolved[remote_id_signature] = nil
                        result.imported = result.imported + 1
                        if remote.note_present then
                            result.notes_imported =
                                result.notes_imported + 1
                        end
                    end
                end
            end
            result.last_processed_remote_id = remote.id
        end
    end

    return result
end

function UI:_fetchRemote(path, progress_text, scan_state)
    local completed, report, err = Trapper:dismissableRunInSubprocess(function()
        return self.worker:run(path, {
            updated_after = scan_state and scan_state.updated_after or nil,
        })
    end, progress_text)
    if not completed then
        return nil, domainError("cancelled", "Reader highlight import was cancelled.")
    end
    if not report then
        return nil, err or domainError(
            "remote",
            "Reader highlights could not be read safely."
        )
    end
    return report
end

function UI:prepareForSync(path)
    local reader_ui, document, context_err = self:_readerContext(path)
    if not reader_ui then
        return {
            status = "skipped",
            skipped_reason = context_err.kind,
            imported = 0,
            notes_imported = 0,
            remote_writes = 0,
            suppress_outbound_ids = {},
            suppress_current_document = false,
        }
    end

    local scan_state = self:_scanState(document)
    local remote_report, fetch_err = self:_fetchRemote(
        path,
        scan_state.baseline_complete
            and _([[Checking recent Reader highlights before outbound annotation sync…

Tap to cancel Sync now. No Reader mutation is performed by this check.]])
            or _([[Reconciling historical Reader highlights before outbound annotation sync…

Tap to cancel Sync now. No Reader mutation is performed by this check.]]),
        scan_state
    )
    if not remote_report then
        return {
            status = fetch_err and fetch_err.kind == "cancelled"
                and "cancelled" or "error",
            error_kind = fetch_err and fetch_err.kind or "remote",
            error_message = fetch_err and fetch_err.message or nil,
            imported = 0,
            notes_imported = 0,
            remote_writes = 0,
            reader_document_id = document.reader_id,
            suppress_outbound_ids = {},
            suppress_current_document = true,
            abort_sync = fetch_err and fetch_err.kind == "cancelled" or false,
        }, fetch_err
    end

    local result, apply_err = self:_applyRemoteReport(
        path,
        reader_ui,
        document,
        remote_report,
        scan_state
    )
    if apply_err then
        result.status = "error"
        result.error_kind = apply_err.kind
        result.error_message = apply_err.message
    end
    self:_saveScanProgress(document, remote_report, result, scan_state)
    result._suppressed_set = nil
    return result, apply_err
end

function UI:run()
    local path, reader_ui, document = self:_preflight()
    if not path then return end

    Trapper:wrap(function()
        local scan_state = self:_scanState(document)
        local remote_report, fetch_err = self:_fetchRemote(
            path,
            scan_state.baseline_complete
                and _([[Checking recent Reader highlights for the open document…

Tap to cancel. No Reader mutation is performed.]])
                or _([[Fetching historical Reader highlights for the open document…

Tap to cancel. No Reader mutation is performed. Local highlights are created only for exact unique KOReader XPointer matches.]]),
            scan_state
        )
        if not remote_report then
            UIManager:show(InfoMessage:new{
                text = fetch_err and fetch_err.message
                    or _("Reader highlights could not be read safely."),
            })
            return
        end

        local result, apply_err = self:_applyRemoteReport(
            path,
            reader_ui,
            document,
            remote_report,
            scan_state
        )
        self:_saveScanProgress(document, remote_report, result, scan_state)
        result._suppressed_set = nil

        local lines = summaryLines(result)
        if apply_err then
            lines[#lines + 1] = ""
            lines[#lines + 1] = apply_err.message
        elseif result.suppress_current_document then
            lines[#lines + 1] = ""
            lines[#lines + 1] = _(
                "Import safety could not be proven for this document. No Reader write was performed."
            )
        elseif (result.deferred_by_limit or 0) > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = _(
                "The bounded migration will continue from a rotated cursor on a later Sync/import run."
            )
        elseif (result.imported or 0) > 0
            or (result.collisions_linked or 0) > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = _(
                "Imported/reconciled highlights were saved and linked to their existing Reader IDs."
            )
        else
            lines[#lines + 1] = ""
            lines[#lines + 1] = _(
                "No new unambiguous Reader highlights were imported."
            )
        end
        UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
    end)
end

UI._exactLocalAt = exactLocalAt
UI._orderedCandidates = orderedCandidates
UI._rotateAfter = rotateAfter
UI._rollbackLocal = rollbackLocal
UI._sameNote = sameNote
UI._summaryLines = summaryLines

return UI
