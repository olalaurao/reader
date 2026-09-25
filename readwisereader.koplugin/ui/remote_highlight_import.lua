-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local Locator = require("koreader/remote_highlight_locator")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Worker = require("sync/remote_highlight_probe_worker")
local _ = require("gettext")

local UI = {}
UI.__index = UI

local MAX_LOCATOR_ATTEMPTS = 3

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
    for _, wants_note in ipairs({ true, false }) do
        for _, item in ipairs(highlights or {}) do
            if (item.note_present == true) == wants_note then
                out[#out + 1] = item
            end
        end
    end
    return out
end

function UI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        importer = assert(options.importer, "importer is required"),
        get_current_path = assert(options.get_current_path, "get_current_path is required"),
        get_reader_ui = assert(options.get_reader_ui, "get_reader_ui is required"),
        worker = options.worker or Worker,
    }, self)
end

function UI:getMenuItem()
    return {
        text = _("Import one Reader highlight (Gate 17B)"),
        keep_menu_open = true,
        callback = function() self:run() end,
    }
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
    local reader_ui = self.get_reader_ui()
    if type(path) ~= "string" or path == "" or not reader_ui
        or not reader_ui.document or not reader_ui.highlight
        or not reader_ui.annotation then
        UIManager:show(InfoMessage:new{ text = _("Open a Readwise-managed EPUB first.") })
        return nil
    end
    if not reader_ui.rolling then
        UIManager:show(InfoMessage:new{
            text = _("Gate 17B currently supports rolling EPUB/HTML documents only."),
        })
        return nil
    end
    if type(reader_ui.saveSettings) ~= "function" then
        UIManager:show(InfoMessage:new{
            text = _("KOReader save-settings API is unavailable; no highlight was imported."),
        })
        return nil
    end
    return path, reader_ui
end

function UI:run()
    local path, reader_ui = self:_preflight()
    if not path then return end

    Trapper:wrap(function()
        local completed, report, err = Trapper:dismissableRunInSubprocess(function()
            return self.worker:run(path)
        end, _([[Fetching Reader highlights for a one-item import…

Tap to cancel. No remote mutation is performed. A local highlight is created only after an exact unique KOReader XPointer match is found.]]))

        if not completed then
            UIManager:show(InfoMessage:new{ text = _("Gate 17B import cancelled before local mutation.") })
            return
        end
        if not report then
            UIManager:show(InfoMessage:new{
                text = err and err.message or _("Gate 17B could not read Reader highlights safely."),
            })
            return
        end

        local attempts, linked_skipped, local_skipped = 0, 0, 0
        local last_locator_status = "none"

        for _, remote in ipairs(orderedCandidates(report.remote_highlights)) do
            if attempts >= MAX_LOCATOR_ATTEMPTS then break end

            local existing_link = self.importer:isRemoteLinked(remote.id)
            if existing_link then
                linked_skipped = linked_skipped + 1
            else
                attempts = attempts + 1
                local locator, locator_status = Locator.findUnique(reader_ui, remote.content)
                last_locator_status = locator_status

                if locator then
                    local existing_index = exactLocalAt(reader_ui, locator)
                    if existing_index then
                        local_skipped = local_skipped + 1
                    else
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
                            UIManager:show(InfoMessage:new{
                                text = _("Gate 17B could not create the local KOReader highlight. Nothing was written to Reader."),
                            })
                            return
                        end

                        local saved_ok = pcall(reader_ui.saveSettings, reader_ui)
                        if not saved_ok then
                            rollbackLocal(reader_ui, index)
                            UIManager:show(InfoMessage:new{
                                text = _("Gate 17B could not persist the KOReader sidecar; the local import was rolled back."),
                            })
                            return
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
                            UIManager:show(InfoMessage:new{
                                text = rollback_ok
                                    and _("Gate 17B could not persist the remote/local identity link; the local import was rolled back.")
                                    or _("Gate 17B link failed and local rollback also failed. Do not run Sync; report this screen."),
                            })
                            return
                        end

                        local lines = {
                            _("Gate 17B Reader → KOReader import"),
                            "",
                            _("Imported local highlights: 1"),
                            string.format(_("Reader highlights for document: %d"), report.parent_highlight_records or 0),
                            string.format(_("Remote highlights already linked/skipped: %d"), linked_skipped),
                            string.format(_("Exact local-position collisions skipped: %d"), local_skipped),
                            string.format(_("Locator attempts: %d"), attempts),
                            string.format(_("Imported note present: %s"),
                                remote.note_present and _("yes") or _("no")),
                            _("Remote identity linked durably: yes"),
                            _("Sidecar persistence verified: yes"),
                            _("Remote writes: none"),
                            "",
                            _("Close and reopen the EPUB now. Do not run Sync until the imported highlight is visibly present after reopen."),
                        }
                        UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
                        return
                    end
                end
            end
        end

        UIManager:show(InfoMessage:new{
            text = table.concat({
                _("Gate 17B did not import a highlight."),
                "",
                string.format(_("Reader highlights for document: %d"), report.parent_highlight_records or 0),
                string.format(_("Remote highlights already linked/skipped: %d"), linked_skipped),
                string.format(_("Exact local-position collisions skipped: %d"), local_skipped),
                string.format(_("Locator attempts: %d"), attempts),
                string.format(_("Last locator result: %s"), tostring(last_locator_status)),
                _("Remote writes: none"),
                _("Local writes: none"),
            }, "\n"),
        })
    end)
end

UI._exactLocalAt = exactLocalAt
UI._orderedCandidates = orderedCandidates
UI._rollbackLocal = rollbackLocal

return UI
