-- SPDX-License-Identifier: AGPL-3.0-only

local Constants = require("constants")
local InfoMessage = require("ui/widget/infomessage")
local Locator = require("koreader/remote_highlight_locator")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Worker = require("sync/remote_highlight_probe_worker")
local _ = require("gettext")

local UI = {}
UI.__index = UI

local MAX_IMPORTS_PER_RUN = Constants.REMOTE_HIGHLIGHT_IMPORT_MAX_PER_SYNC or 20
local MAX_LOCATOR_ATTEMPTS_PER_RUN = Constants.REMOTE_HIGHLIGHT_IMPORT_MAX_LOCATOR_ATTEMPTS or 30

local function domainError(kind, message)
    return { kind = kind, retryable = false, message = message }
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

local function newBatchReport(remote_report)
    return {
        status = "ok",
        reader_highlights = remote_report.parent_highlight_records or 0,
        highlights_with_text = #(remote_report.remote_highlights or {}),
        imported = 0,
        notes_imported = 0,
        linked_skipped = 0,
        local_collisions = 0,
        locator_attempts = 0,
        ambiguous = 0,
        missing = 0,
        invalid = 0,
        deferred_by_limit = 0,
        failures = 0,
        remote_writes = 0,
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

local function summaryLines(result, title)
    return {
        title or _("Reader → KOReader highlight import"),
        "",
        string.format(_("Imported local highlights: %d"), result.imported or 0),
        string.format(_("Imported notes preserved: %d"), result.notes_imported or 0),
        string.format(_("Reader highlights for document: %d"), result.reader_highlights or 0),
        string.format(_("Reader highlights with text: %d"), result.highlights_with_text or 0),
        string.format(_("Remote highlights already linked/skipped: %d"), result.linked_skipped or 0),
        string.format(_("Exact local-position collisions skipped: %d"), result.local_collisions or 0),
        string.format(_("Locator attempts: %d"), result.locator_attempts or 0),
        string.format(_("Ambiguous locator matches skipped: %d"), result.ambiguous or 0),
        string.format(_("Missing locator matches skipped: %d"), result.missing or 0),
        string.format(_("Invalid/different locator matches skipped: %d"), result.invalid or 0),
        string.format(_("Unlinked highlights deferred by batch limit: %d"), result.deferred_by_limit or 0),
        string.format(_("Import failures: %d"), result.failures or 0),
        _("Remote writes: none"),
    }
end

function UI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        importer = assert(options.importer, "importer is required"),
        get_current_path = assert(options.get_current_path, "get_current_path is required"),
        get_reader_ui = assert(options.get_reader_ui, "get_reader_ui is required"),
        worker = options.worker or Worker,
        max_imports = options.max_imports or MAX_IMPORTS_PER_RUN,
        max_locator_attempts = options.max_locator_attempts or MAX_LOCATOR_ATTEMPTS_PER_RUN,
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
        return nil, domainError("document", "Open the same Readwise-managed EPUB before importing highlights.")
    end
    if not reader_ui.rolling then
        return nil, domainError("format", "Reader highlight import currently supports rolling EPUB/HTML documents only.")
    end
    if type(reader_ui.saveSettings) ~= "function" then
        return nil, domainError("save", "KOReader save-settings API is unavailable; no highlight was imported.")
    end
    return reader_ui
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
    local reader_ui, context_err = self:_readerContext(path)
    if not reader_ui then
        UIManager:show(InfoMessage:new{ text = context_err.message })
        return nil
    end
    return path, reader_ui
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

function UI:_applyRemoteReport(path, reader_ui, remote_report)
    local result = newBatchReport(remote_report)
    local candidates = orderedCandidates(remote_report.remote_highlights)

    for candidate_index, remote in ipairs(candidates) do
        local linked_ok, existing_link = pcall(
            self.importer.isRemoteLinked,
            self.importer,
            remote.id
        )
        if not linked_ok then
            result.failures = result.failures + 1
            result.status = "error"
            return result, domainError("db", "Could not read the durable Reader/local highlight links.")
        end

        if existing_link then
            result.linked_skipped = result.linked_skipped + 1
        elseif result.imported >= self.max_imports
            or result.locator_attempts >= self.max_locator_attempts then
            result.deferred_by_limit = result.deferred_by_limit + 1
        else
            result.locator_attempts = result.locator_attempts + 1
            local locator, locator_status = Locator.findUnique(reader_ui, remote.content)
            if not locator then
                addLocatorFailure(result, locator_status)
            else
                local existing_index = exactLocalAt(reader_ui, locator)
                if existing_index then
                    result.local_collisions = result.local_collisions + 1
                else
                    local created, create_err = self:_createAndLink(
                        path,
                        reader_ui,
                        remote,
                        locator
                    )
                    if not created then
                        result.failures = result.failures + 1
                        result.status = "error"
                        return result, create_err
                    elseif created.status == "already_linked_race" then
                        result.linked_skipped = result.linked_skipped + 1
                    else
                        result.imported = result.imported + 1
                        if remote.note_present then
                            result.notes_imported = result.notes_imported + 1
                        end
                    end
                end
            end
        end
    end

    return result
end

function UI:_fetchRemote(path, progress_text)
    local completed, report, err = Trapper:dismissableRunInSubprocess(function()
        return self.worker:run(path)
    end, progress_text)
    if not completed then
        return nil, domainError("cancelled", "Reader highlight import was cancelled.")
    end
    if not report then
        return nil, err or domainError("remote", "Reader highlights could not be read safely.")
    end
    return report
end

function UI:importAfterSync(path)
    local reader_ui, context_err = self:_readerContext(path)
    if not reader_ui then
        return {
            status = "skipped",
            skipped_reason = context_err.kind,
            imported = 0,
            notes_imported = 0,
            remote_writes = 0,
        }
    end

    local remote_report, fetch_err = self:_fetchRemote(
        path,
        _([[Document sync is complete. Importing existing Reader highlights into the open EPUB…

Tap to cancel only the Reader → KOReader import. The completed document sync is kept. No Reader mutation is performed.]])
    )
    if not remote_report then
        return {
            status = fetch_err and fetch_err.kind == "cancelled" and "cancelled" or "error",
            error_kind = fetch_err and fetch_err.kind or "remote",
            imported = 0,
            notes_imported = 0,
            remote_writes = 0,
        }, fetch_err
    end

    local result, apply_err = self:_applyRemoteReport(path, reader_ui, remote_report)
    if apply_err then
        result.status = "error"
        result.error_kind = apply_err.kind
        result.error_message = apply_err.message
    end
    return result, apply_err
end

function UI:run()
    local path, reader_ui = self:_preflight()
    if not path then return end

    Trapper:wrap(function()
        local remote_report, fetch_err = self:_fetchRemote(
            path,
            _([[Fetching Reader highlights for the open document…

Tap to cancel. No Reader mutation is performed. Local highlights are created only for exact unique KOReader XPointer matches.]])
        )
        if not remote_report then
            UIManager:show(InfoMessage:new{
                text = fetch_err and fetch_err.message or _("Reader highlights could not be read safely."),
            })
            return
        end

        local result, apply_err = self:_applyRemoteReport(path, reader_ui, remote_report)
        local lines = summaryLines(result)
        if apply_err then
            lines[#lines + 1] = ""
            lines[#lines + 1] = apply_err.message
        elseif (result.deferred_by_limit or 0) > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = _("Run Sync now again to continue the bounded import batch.")
        elseif (result.imported or 0) > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = _("Imported highlights were saved to the KOReader sidecar and linked to their existing Reader IDs.")
        else
            lines[#lines + 1] = ""
            lines[#lines + 1] = _("No new unambiguous Reader highlights were imported.")
        end
        UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
    end)
end

UI._exactLocalAt = exactLocalAt
UI._orderedCandidates = orderedCandidates
UI._rollbackLocal = rollbackLocal
UI._summaryLines = summaryLines

return UI
