-- SPDX-License-Identifier: AGPL-3.0-only

local Constants = require("constants")
local InfoMessage = require("ui/widget/infomessage")
local Locator = require("koreader/paging_remote_highlight_locator")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Worker = require("sync/remote_highlight_import_worker")
local _ = require("gettext")

local UI = {}
UI.__index = UI

local function domainError(kind, message)
    return { kind = kind, retryable = false, message = message }
end

local function defaultFileDigest(path)
    local file, open_err = io.open(path, "rb")
    if not file then
        return nil, "PDF could not be opened for the sidecar-only integrity check: "
            .. tostring(open_err)
    end

    local ok, digest_or_err = pcall(function()
        local md5 = require("ffi/sha2").md5
        local update = md5()
        while true do
            local chunk = file:read(128 * 1024)
            if not chunk then break end
            if #chunk == 0 then break end
            update(chunk)
        end
        return update()
    end)
    file:close()

    if not ok then
        return nil, "PDF integrity digest failed: " .. tostring(digest_or_err)
    end
    return tostring(digest_or_err)
end

local function samePosition(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a.page == b.page
        and a.x == b.x
        and a.y == b.y
end

local function sameBoxes(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
        return false
    end
    for index = 1, #a do
        local left, right = a[index], b[index]
        if type(left) ~= "table" or type(right) ~= "table"
            or left.x ~= right.x or left.y ~= right.y
            or left.w ~= right.w or left.h ~= right.h then
            return false
        end
    end
    return #a > 0
end

local function exactLocalAt(reader_ui, locator)
    for index, item in ipairs(reader_ui.annotation.annotations or {}) do
        if item.drawer ~= nil and item.page == locator.page then
            if sameBoxes(item.pboxes, locator.pboxes)
                or (samePosition(item.pos0, locator.pos0)
                    and samePosition(item.pos1, locator.pos1)) then
                return index, item
            end
        end
    end
end

local function orderedCandidates(highlights)
    local out = {}
    for _, wants_note in ipairs({ true, false }) do
        for _, item in ipairs(highlights or {}) do
            if (item.note_present == true) == wants_note then
                out[#out + 1] = item
            end
        end
    end
    return out
end

local function sameNote(a, b)
    local left = type(a) == "string" and a or ""
    local right = type(b) == "string" and b or ""
    return left == right
end

local function rotateAfter(items, cursor_id)
    if type(cursor_id) ~= "string" or cursor_id == "" then return items end
    local pivot
    for index, state in ipairs(items or {}) do
        local remote = state.remote or state
        if remote.id == cursor_id then
            pivot = index
            break
        end
    end
    if not pivot or pivot == #items then return items end

    local out = {}
    for index = pivot + 1, #items do out[#out + 1] = items[index] end
    for index = 1, pivot do out[#out + 1] = items[index] end
    return out
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

local function newSyncReport(remote_report, document)
    return {
        status = "ok",
        scan_mode = remote_report.cache_mode or "cache",
        reader_document_id = document.reader_id,
        reader_highlights = remote_report.parent_highlight_records or 0,
        highlights_with_text = remote_report.highlights_with_text
            or #(remote_report.remote_highlights or {}),
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

local function withPdfEmbeddingDisabled(reader_ui, fn)
    local highlight = reader_ui.highlight
    local previous = highlight.highlight_write_into_pdf
    highlight.highlight_write_into_pdf = false
    local results = { pcall(fn) }
    highlight.highlight_write_into_pdf = previous
    return unpack(results)
end

local function annotationIndex(reader_ui, target)
    for index, item in ipairs(reader_ui.annotation.annotations or {}) do
        if item == target then return index end
    end
end

local function rollbackLocal(reader_ui, target)
    local index = annotationIndex(reader_ui, target)
    if not index then return false end

    local deleted = withPdfEmbeddingDisabled(reader_ui, function()
        reader_ui.highlight:deleteHighlight(index)
    end)
    if not deleted then return false end
    if annotationIndex(reader_ui, target) then return false end

    local saved = pcall(reader_ui.saveSettings, reader_ui)
    if not saved then return false end
    return annotationIndex(reader_ui, target) == nil
end

function UI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        importer = assert(options.importer, "importer is required"),
        get_current_path =
            assert(options.get_current_path, "get_current_path is required"),
        get_reader_ui =
            assert(options.get_reader_ui, "get_reader_ui is required"),
        worker = options.worker or Worker,
        file_digest = options.file_digest or defaultFileDigest,
        sync_meta = options.sync_meta,
        max_imports = options.max_imports
            or Constants.PDF_REMOTE_HIGHLIGHT_IMPORT_MAX_PER_SYNC,
        max_locator_attempts = options.max_locator_attempts
            or Constants.PDF_REMOTE_HIGHLIGHT_IMPORT_MAX_LOCATOR_ATTEMPTS,
    }, self)
end

function UI:getMenuItem()
    return {
        text = _("Import one Reader PDF highlight (Gate 17D)"),
        keep_menu_open = true,
        callback = function() self:run() end,
    }
end

function UI:_readerContext(path)
    local current_path = self.get_current_path()
    local reader_ui = self.get_reader_ui()
    if type(path) ~= "string" or path == "" or current_path ~= path
        or not reader_ui or not reader_ui.document
        or not reader_ui.highlight or not reader_ui.annotation then
        return nil, nil, domainError(
            "document",
            "Open the same Readwise-managed PDF first."
        )
    end
    if not reader_ui.paging or reader_ui.document.is_pdf ~= true then
        return nil, nil, domainError(
            "format",
            "Reader PDF highlight import requires the open original paging PDF."
        )
    end
    if type(reader_ui.saveSettings) ~= "function" then
        return nil, nil, domainError(
            "save",
            "KOReader save-settings API is unavailable."
        )
    end

    local document, document_err = self.importer:getDocument(path)
    if not document then return nil, nil, document_err end
    if document.local_format ~= "pdf" then
        return nil, nil, domainError(
            "format",
            "The managed Reader document is not recorded as an original PDF."
        )
    end
    return reader_ui, document
end

function UI:_preflight()
    if not self.config:hasAccessToken() then
        return nil, nil, nil, domainError(
            "auth",
            "No access token is configured."
        )
    end
    if not NetworkMgr:isOnline() then
        return nil, nil, nil, domainError(
            "offline",
            "No internet connection. Turn Wi-Fi on outside the plugin and try again."
        )
    end

    local path = self.get_current_path()
    local reader_ui, document, context_err = self:_readerContext(path)
    if not reader_ui then return nil, nil, nil, context_err end
    return path, reader_ui, document
end

function UI:_fetchRemote(path, progress_text)
    local completed, report, err = Trapper:dismissableRunInSubprocess(function()
        return self.worker:run(path)
    end, progress_text or _([[Fetching Reader highlights for this PDF…

Tap to cancel. This Gate 17D-2 action imports at most one safe local PDF highlight. It performs no Reader mutation.]]))

    if not completed then
        return nil, domainError("cancelled", "PDF highlight import was cancelled.")
    end
    if not report then
        return nil, err or domainError(
            "remote",
            "Reader highlights for this PDF could not be read safely."
        )
    end
    return report
end

function UI:_createAndLink(path, reader_ui, remote, locator, digest_before)
    local previous_selected = reader_ui.highlight.selected_text
    local previous_hold = reader_ui.highlight.hold_pos

    reader_ui.highlight.hold_pos = nil
    reader_ui.highlight.selected_text = {
        text = locator.matched_text or locator.text,
        pos0 = locator.pos0,
        pos1 = locator.pos1,
        pboxes = locator.pboxes,
        note = remote.notes,
    }

    local created_ok, index = withPdfEmbeddingDisabled(reader_ui, function()
        return reader_ui.highlight:saveHighlight(false)
    end)

    reader_ui.highlight.selected_text = previous_selected
    reader_ui.highlight.hold_pos = previous_hold

    if not created_ok or type(index) ~= "number"
        or not reader_ui.annotation.annotations[index] then
        return nil, domainError(
            "local_create",
            "KOReader could not create the sidecar-only PDF highlight."
        )
    end
    local local_item = reader_ui.annotation.annotations[index]

    -- The user's PDF-embedding preference has already been restored by
    -- withPdfEmbeddingDisabled(). Save only after restoration so this plugin
    -- does not silently change that preference.
    local saved_ok = pcall(reader_ui.saveSettings, reader_ui)
    if not saved_ok then
        local rollback_ok = rollbackLocal(reader_ui, local_item)
        return nil, domainError(
            rollback_ok and "sidecar" or "rollback",
            rollback_ok
                and "KOReader could not persist the PDF sidecar; the local import was rolled back."
                or "KOReader could not persist the PDF sidecar and rollback also failed. Stop syncing and report this error."
        )
    end

    local digest_after, digest_err = self.file_digest(path)
    if not digest_after then
        rollbackLocal(reader_ui, local_item)
        return nil, domainError("integrity", digest_err)
    end
    if digest_after ~= digest_before then
        rollbackLocal(reader_ui, local_item)
        return nil, domainError(
            "pdf_changed",
            "The PDF file bytes changed unexpectedly. The sidecar item was rolled back and Gate 17D must stop."
        )
    end

    local link_ok, linked, link_err = pcall(
        self.importer.linkPersisted,
        self.importer,
        path,
        remote,
        local_item
    )
    if not link_ok or not linked then
        local rollback_ok = rollbackLocal(reader_ui, local_item)
        local reason
        if link_ok and type(link_err) == "table"
            and type(link_err.message) == "string"
            and link_err.message ~= "" then
            reason = link_err.message
        elseif not link_ok then
            reason = "The durable Reader/PDF link raised an internal error."
        else
            reason = "The durable Reader/PDF link returned no result."
        end
        return nil, domainError(
            rollback_ok and "link" or "rollback",
            rollback_ok
                and (reason .. " The local sidecar item was rolled back.")
                or (reason .. " Local rollback also failed. Stop syncing and report this error.")
        )
    end

    if linked.status == "already_linked" then
        local rollback_ok = rollbackLocal(reader_ui, local_item)
        if not rollback_ok then
            return nil, domainError(
                "rollback",
                "A Reader-link race was detected and the duplicate local sidecar item could not be rolled back."
            )
        end
        return {
            status = "already_linked_race",
            pdf_digest_unchanged = true,
        }
    end

    return {
        status = "linked",
        local_annotation_id = linked.local_annotation_id,
        pdf_digest_unchanged = true,
    }
end

function UI:_scanState(document)
    local cursor_key = "pdf_remote_highlight_cursor:" .. tostring(document.reader_id)
    local cursor_id
    if self.sync_meta and type(self.sync_meta.get) == "function" then
        local ok, value = pcall(self.sync_meta.get, self.sync_meta, cursor_key)
        if ok then cursor_id = value end
    end
    return {
        cursor_key = cursor_key,
        cursor_id = cursor_id,
    }
end

function UI:_saveScanProgress(result, scan_state)
    if not self.sync_meta then return true end
    if result.deferred_by_limit > 0 and result.last_processed_remote_id then
        return pcall(
            self.sync_meta.set,
            self.sync_meta,
            scan_state.cursor_key,
            result.last_processed_remote_id
        )
    end
    if type(self.sync_meta.delete) == "function" then
        return pcall(
            self.sync_meta.delete,
            self.sync_meta,
            scan_state.cursor_key
        )
    end
    return true
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
                "Could not read the durable Reader/PDF highlight links."
            )
        end
        states[#states + 1] = {
            remote = remote,
            existing_link = existing_link,
        }
    end
    return states
end

function UI:_linkExistingCollision(path, remote, existing_item, result)
    result.local_collisions = result.local_collisions + 1

    local normalize_ok, normalized, normalize_err = pcall(
        self.importer.normalizeLocal,
        self.importer,
        path,
        existing_item
    )
    if not normalize_ok or not normalized then
        result.failures = result.failures + 1
        result.status = "error"
        result.suppress_current_document = true
        return nil, normalize_err or domainError(
            "annotation",
            "Existing PDF highlight could not be normalized safely."
        )
    end

    if not sameNote(existing_item.note, remote.notes) then
        result.collision_conflicts = result.collision_conflicts + 1
        result.status = "partial"
        addSuppressedId(result, normalized.local_annotation_id)
        return true
    end

    local link_ok, linked, link_err = pcall(
        self.importer.linkPersisted,
        self.importer,
        path,
        remote,
        existing_item
    )
    if not link_ok or not linked then
        result.failures = result.failures + 1
        result.status = "error"
        result.suppress_current_document = true
        addSuppressedId(result, normalized.local_annotation_id)
        return nil, link_err or domainError(
            "db",
            "Existing PDF highlight could not be linked durably."
        )
    end

    if linked.status == "already_linked" then
        if linked.local_annotation_id ~= normalized.local_annotation_id then
            result.collision_conflicts = result.collision_conflicts + 1
            result.status = "error"
            result.suppress_current_document = true
            addSuppressedId(result, normalized.local_annotation_id)
            return nil, domainError(
                "identity",
                "Reader PDF highlight is already linked to a different local annotation."
            )
        end
        result.linked_skipped = result.linked_skipped + 1
    else
        result.collisions_linked = result.collisions_linked + 1
    end
    return true
end

function UI:_applyForSync(path, reader_ui, document, remote_report, scan_state)
    local result = newSyncReport(remote_report, document)
    local states, state_err = self:_candidateStates(remote_report.remote_highlights)
    if not states then
        result.failures = 1
        result.status = "error"
        result.suppress_current_document = true
        return result, state_err
    end

    local rotated = rotateAfter(states, scan_state.cursor_id)
    local digest_before

    for position, state in ipairs(rotated) do
        local remote = state.remote
        if state.existing_link then
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
                if locator_status == "ambiguous" then
                    result.ambiguous = result.ambiguous + 1
                elseif locator_status == "missing" then
                    result.missing = result.missing + 1
                else
                    result.invalid = result.invalid + 1
                end
                result.unresolved_collision_risk =
                    result.unresolved_collision_risk + 1
                result.status = "partial"
                result.suppress_current_document = true
            else
                local _, existing_item = exactLocalAt(reader_ui, locator)
                if existing_item then
                    local linked_ok, linked_err = self:_linkExistingCollision(
                        path,
                        remote,
                        existing_item,
                        result
                    )
                    if not linked_ok then
                        return result, linked_err
                    end
                else
                    if not digest_before then
                        local digest, digest_err = self.file_digest(path)
                        if not digest then
                            result.failures = result.failures + 1
                            result.status = "error"
                            result.suppress_current_document = true
                            return result, domainError("integrity", digest_err)
                        end
                        digest_before = digest
                    end

                    local created, create_err = self:_createAndLink(
                        path,
                        reader_ui,
                        remote,
                        locator,
                        digest_before
                    )
                    if not created then
                        result.failures = result.failures + 1
                        result.status = "error"
                        result.suppress_current_document = true
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
            result.last_processed_remote_id = remote.id
        end
    end

    if result.deferred_by_limit > 0 then
        result.status = result.status == "error" and "error" or "partial"
        result.suppress_current_document = true
    end

    return result
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
        _([[Reconciling Reader PDF highlights before outbound annotation sync…

Tap to cancel. PDF imports remain sidecar-only and bounded. No Reader mutation is performed by this reconciliation.]]))
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

    local result, apply_err = self:_applyForSync(
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
    if not self:_saveScanProgress(result, scan_state) then
        result.status = result.status == "error" and "error" or "partial"
    end
    result._suppressed_set = nil
    return result, apply_err
end

function UI:run()
    local path, reader_ui, document, preflight_err = self:_preflight()
    if not path then
        UIManager:show(InfoMessage:new{
            text = preflight_err and preflight_err.message
                or _("Gate 17D-2 preflight failed."),
        })
        return
    end

    Trapper:wrap(function()
        local digest_before, digest_err = self.file_digest(path)
        if not digest_before then
            UIManager:show(InfoMessage:new{ text = digest_err })
            return
        end

        local report, fetch_err = self:_fetchRemote(path)
        if not report then
            UIManager:show(InfoMessage:new{
                text = fetch_err and fetch_err.message
                    or _("Reader PDF highlights could not be read safely."),
            })
            return
        end

        local linked_skipped = 0
        local ambiguous, missing, invalid = 0, 0, 0
        local collisions = 0
        local imported
        local imported_remote
        local locator_status

        for _, remote in ipairs(orderedCandidates(report.remote_highlights)) do
            local linked_ok, existing_link = pcall(
                self.importer.isRemoteLinked,
                self.importer,
                remote.id
            )
            if not linked_ok then
                UIManager:show(InfoMessage:new{
                    text = _("Could not read the durable Reader/PDF highlight links."),
                })
                return
            end

            if existing_link then
                linked_skipped = linked_skipped + 1
            else
                local locator, status =
                    Locator.findUnique(reader_ui, remote.content)
                if locator then
                    local existing_index = exactLocalAt(reader_ui, locator)
                    if existing_index then
                        collisions = collisions + 1
                    else
                        local created, create_err = self:_createAndLink(
                            path,
                            reader_ui,
                            remote,
                            locator,
                            digest_before
                        )
                        if not created then
                            UIManager:show(InfoMessage:new{
                                text = create_err and create_err.message
                                    or _("PDF highlight import failed safely."),
                            })
                            return
                        end
                        if created.status == "linked" then
                            imported = created
                            imported_remote = remote
                            locator_status = status
                            break
                        end
                        linked_skipped = linked_skipped + 1
                    end
                elseif status == "ambiguous" then
                    ambiguous = ambiguous + 1
                elseif status == "missing" then
                    missing = missing + 1
                else
                    invalid = invalid + 1
                end
            end
        end

        -- A successful import already compared the complete PDF digest
        -- immediately after sidecar persistence and before durable DB linking.
        -- Nothing after that check writes the document file, so avoid a third
        -- full PDF read on low-power devices.
        local pdf_unchanged = imported == nil
            or imported.pdf_digest_unchanged == true

        local lines = {
            _("Gate 17D-2 Reader → KOReader PDF one-item import"),
            "",
            string.format(
                _("Reader highlights for this PDF: %d"),
                report.parent_highlight_records or 0
            ),
            string.format(
                _("Already-linked Reader highlights skipped: %d"),
                linked_skipped
            ),
            string.format(_("Local position collisions skipped: %d"), collisions),
            string.format(_("Ambiguous locators skipped: %d"), ambiguous),
            string.format(_("Missing locators skipped: %d"), missing),
            string.format(_("Invalid locators skipped: %d"), invalid),
            string.format(_("Imported local PDF highlights: %d"), imported and 1 or 0),
            string.format(
                _("Imported Reader note: %s"),
                imported_remote and imported_remote.note_present
                    and _("yes") or _("no")
            ),
            string.format(
                _("Locator class: %s"),
                locator_status or _("none")
            ),
            string.format(
                _("PDF file digest unchanged: %s"),
                pdf_unchanged and _("yes") or _("NO")
            ),
            string.format(
                _("PDF embed preference restored: %s"),
                _("yes")
            ),
            _("Reader writes from import: none"),
        }

        if imported then
            lines[#lines + 1] = ""
            lines[#lines + 1] = _(
                "One PDF highlight was saved to the KOReader sidecar and linked to its existing Reader child ID."
            )
        else
            lines[#lines + 1] = ""
            lines[#lines + 1] = _(
                "No safe unlinked PDF highlight was imported."
            )
        end

        UIManager:show(InfoMessage:new{
            text = table.concat(lines, "\n"),
        })
    end)
end

UI._annotationIndex = annotationIndex
UI._defaultFileDigest = defaultFileDigest
UI._exactLocalAt = exactLocalAt
UI._orderedCandidates = orderedCandidates
UI._rollbackLocal = rollbackLocal
UI._addSuppressedId = addSuppressedId
UI._newSyncReport = newSyncReport
UI._orderedCandidates = orderedCandidates
UI._rotateAfter = rotateAfter
UI._sameBoxes = sameBoxes
UI._sameNote = sameNote
UI._samePosition = samePosition
UI._withPdfEmbeddingDisabled = withPdfEmbeddingDisabled

return UI
