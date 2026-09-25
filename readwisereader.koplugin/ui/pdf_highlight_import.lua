-- SPDX-License-Identifier: AGPL-3.0-only

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
        and a.rotation == b.rotation
        and a.zoom == b.zoom
end

local function exactLocalAt(reader_ui, locator)
    for index, item in ipairs(reader_ui.annotation.annotations or {}) do
        if item.drawer ~= nil
            and item.page == locator.page
            and samePosition(item.pos0, locator.pos0)
            and samePosition(item.pos1, locator.pos1) then
            return index, item
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

local function withPdfEmbeddingDisabled(reader_ui, fn)
    local highlight = reader_ui.highlight
    local previous = highlight.highlight_write_into_pdf
    highlight.highlight_write_into_pdf = false
    local results = { pcall(fn) }
    highlight.highlight_write_into_pdf = previous
    return unpack(results)
end

local function rollbackLocal(reader_ui, index)
    local deleted = withPdfEmbeddingDisabled(reader_ui, function()
        reader_ui.highlight:deleteHighlight(index)
    end)
    if not deleted then return false end
    return pcall(reader_ui.saveSettings, reader_ui)
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
    }, self)
end

function UI:getMenuItem()
    return {
        text = _("Import one Reader PDF highlight (Gate 17D)"),
        keep_menu_open = true,
        callback = function() self:run() end,
    }
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
    local reader_ui = self.get_reader_ui()
    if type(path) ~= "string" or path == ""
        or not reader_ui or not reader_ui.document
        or not reader_ui.highlight or not reader_ui.annotation then
        return nil, nil, nil, domainError(
            "document",
            "Open the same Readwise-managed PDF first."
        )
    end
    if not reader_ui.paging or reader_ui.document.is_pdf ~= true then
        return nil, nil, nil, domainError(
            "format",
            "Gate 17D-2 imports paging PDF highlights only."
        )
    end
    if type(reader_ui.saveSettings) ~= "function" then
        return nil, nil, nil, domainError(
            "save",
            "KOReader save-settings API is unavailable."
        )
    end

    local document, document_err = self.importer:getDocument(path)
    if not document then return nil, nil, nil, document_err end
    if document.local_format ~= "pdf" then
        return nil, nil, nil, domainError(
            "format",
            "The managed Reader document is not recorded as an original PDF."
        )
    end

    return path, reader_ui, document
end

function UI:_fetchRemote(path)
    local completed, report, err = Trapper:dismissableRunInSubprocess(function()
        return self.worker:run(path)
    end, _([[Fetching Reader highlights for this PDF…

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

    -- The user's PDF-embedding preference has already been restored by
    -- withPdfEmbeddingDisabled(). Save only after restoration so this plugin
    -- does not silently change that preference.
    local saved_ok = pcall(reader_ui.saveSettings, reader_ui)
    if not saved_ok then
        rollbackLocal(reader_ui, index)
        return nil, domainError(
            "sidecar",
            "KOReader could not persist the PDF sidecar; the local import was rolled back."
        )
    end

    local digest_after, digest_err = self.file_digest(path)
    if not digest_after then
        rollbackLocal(reader_ui, index)
        return nil, domainError("integrity", digest_err)
    end
    if digest_after ~= digest_before then
        rollbackLocal(reader_ui, index)
        return nil, domainError(
            "pdf_changed",
            "The PDF file bytes changed unexpectedly. The sidecar item was rolled back and Gate 17D must stop."
        )
    end

    local local_item = reader_ui.annotation.annotations[index]
    local link_ok, linked = pcall(
        self.importer.linkPersisted,
        self.importer,
        path,
        remote,
        local_item
    )
    if not link_ok or not linked then
        local rollback_ok = rollbackLocal(reader_ui, index)
        return nil, domainError(
            rollback_ok and "db" or "rollback",
            rollback_ok
                and "The Reader/PDF identity link could not be persisted; the local sidecar item was rolled back."
                or "The identity link failed and local rollback also failed. Stop syncing and report this error."
        )
    end

    if linked.status == "already_linked" then
        local rollback_ok = rollbackLocal(reader_ui, index)
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

        local final_digest, final_digest_err = self.file_digest(path)
        if not final_digest then
            UIManager:show(InfoMessage:new{ text = final_digest_err })
            return
        end
        local pdf_unchanged = final_digest == digest_before

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

UI._defaultFileDigest = defaultFileDigest
UI._exactLocalAt = exactLocalAt
UI._orderedCandidates = orderedCandidates
UI._rollbackLocal = rollbackLocal
UI._samePosition = samePosition
UI._withPdfEmbeddingDisabled = withPdfEmbeddingDisabled

return UI
