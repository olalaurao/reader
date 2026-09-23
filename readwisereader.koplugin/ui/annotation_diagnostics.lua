-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local AnnotationDiagnosticsUI = {}
AnnotationDiagnosticsUI.__index = AnnotationDiagnosticsUI

local function clipped(value, limit)
    if value == nil then return _("(none)") end
    value = tostring(value)
    limit = limit or 600
    if #value <= limit then return value end
    return value:sub(1, limit) .. _("… [truncated]")
end

local function errorText(err)
    if not err then return _("Annotation scan failed safely.") end
    if err.kind == "not_managed" then
        return _("This document is not managed by Readwise Reader.")
    elseif err.kind == "not_local" then
        return _("This Reader document is not recorded as a local file.")
    elseif err.kind == "sidecar" then
        return _("KOReader's sidecar could not be read safely. No deletion state was inferred.")
    end
    return err.message or _("Annotation scan failed safely.")
end

function AnnotationDiagnosticsUI:new(options)
    options = options or {}
    return setmetatable({
        scanner = assert(options.scanner, "scanner is required"),
        get_current_path = assert(options.get_current_path, "get_current_path is required"),
    }, self)
end

function AnnotationDiagnosticsUI:getMenuItem()
    return {
        text = _("Scan current annotations (Gate 7)"),
        keep_menu_open = true,
        callback = function()
            self:scanCurrent()
        end,
    }
end

function AnnotationDiagnosticsUI:scanCurrent()
    local path = self.get_current_path()
    if type(path) ~= "string" or path == "" then
        UIManager:show(InfoMessage:new{
            text = _("Open a Readwise-managed document first, then run this diagnostic from the reader menu."),
        })
        return
    end

    local report, err = self.scanner:scanPath(path)
    if not report then
        UIManager:show(InfoMessage:new{ text = errorText(err) })
        return
    end

    if not report.authoritative then
        local message = report.status == "no_sidecar"
            and _("No valid KOReader sidecar exists yet. Close and reopen the document after creating the highlight/note, then retry.")
            or _("The sidecar exists but does not contain the current KOReader annotations table. No deletion state was inferred.")
        UIManager:show(InfoMessage:new{ text = message })
        return
    end

    local lines = {
        _("Gate 7 annotation scan"),
        "",
        string.format(_("Highlights found: %d"), report.highlights or 0),
        string.format(_("With notes: %d"), report.notes or 0),
        string.format(_("New: %d"), report.new or 0),
        string.format(_("Changed: %d"), report.changed or 0),
        string.format(_("Unchanged: %d"), report.unchanged or 0),
        string.format(_("Deleted since prior scan: %d"), report.deleted or 0),
        string.format(_("Malformed skipped: %d"), report.malformed or 0),
    }

    if report.sample then
        lines[#lines + 1] = ""
        lines[#lines + 1] = _("Most recently modified highlight")
        lines[#lines + 1] = _("Local ID: ") .. report.sample.local_annotation_id
        lines[#lines + 1] = _("Selected text:")
        lines[#lines + 1] = clipped(report.sample.text)
        lines[#lines + 1] = ""
        lines[#lines + 1] = _("Note:")
        lines[#lines + 1] = clipped(report.sample.note)
    end

    UIManager:show(InfoMessage:new{
        text = table.concat(lines, "\n"),
    })
end

AnnotationDiagnosticsUI._clipped = clipped
AnnotationDiagnosticsUI._errorText = errorText

return AnnotationDiagnosticsUI
