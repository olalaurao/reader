-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local FinishedDiagnostics = {}
FinishedDiagnostics.__index = FinishedDiagnostics

local function show(value)
    if value == nil then return "unavailable" end
    if value == true then return "yes" end
    if value == false then return "no" end
    return tostring(value)
end

local function percent(value)
    if type(value) ~= "number" then return "unavailable" end
    return string.format("%.4f", value)
end

function FinishedDiagnostics:new(options)
    options = options or {}
    return setmetatable({
        documents = assert(options.documents, "documents repository is required"),
        status = assert(options.status, "KOReader status adapter is required"),
        get_current_path = options.get_current_path or function() return nil end,
        get_runtime_summary = options.get_runtime_summary or function() return nil end,
    }, self)
end

function FinishedDiagnostics:getMenuItem()
    return {
        text = _("Inspect finished status (Gate 14)"),
        keep_menu_open = true,
        callback = function() self:run() end,
    }
end

function FinishedDiagnostics:run()
    local path = self.get_current_path()
    if not path then
        UIManager:show(InfoMessage:new{
            text = _("Open a managed Reader document before running the Gate 14 status diagnostic."),
        })
        return
    end

    local document = self.documents:getByLocalPath(path)
    if not document or document.is_managed ~= true then
        UIManager:show(InfoMessage:new{
            text = _("The current document is not managed by Readwise Reader."),
        })
        return
    end

    local report, err = self.status:scan(path)
    if not report then
        UIManager:show(InfoMessage:new{
            text = err and err.message or _("KOReader finished-status diagnostic failed safely."),
        })
        return
    end

    local runtime_summary
    local runtime_ok, runtime_value = pcall(self.get_runtime_summary)
    if runtime_ok and type(runtime_value) == "table" then
        runtime_summary = runtime_value
    end

    local lines = {
        _("Gate 14 finished-status diagnostic"),
        "",
        string.format(_("Managed Reader document: %s"), "yes"),
        string.format(_("Local file present: %s"), show(document.is_local_present == true)),
        string.format(_("Reader location in local DB: %s"), show(document.location)),
        string.format(_("Sidecar present: %s"), show(report.sidecar_present)),
        string.format(_("Sidecar summary.status: %s"), show(report.sidecar_status)),
        string.format(_("Sidecar summary.modified: %s"), show(report.sidecar_modified)),
        string.format(_("Sidecar percent_finished: %s"), percent(report.percent_finished)),
        string.format(_("BookList status: %s"), show(report.booklist_status)),
        string.format(
            _("Runtime summary.status: %s"),
            show(runtime_summary and runtime_summary.status)
        ),
        string.format(
            _("Runtime summary.modified: %s"),
            show(runtime_summary and runtime_summary.modified)
        ),
        "",
        string.format(
            _("Canonical finished candidate (summary.status=complete): %s"),
            show(report.finished)
        ),
        "",
        _("Remote requests: none"),
        _("Remote writes: none"),
        _("Local writes: none"),
    }

    UIManager:show(InfoMessage:new{
        text = table.concat(lines, "\n"),
    })
end

FinishedDiagnostics._show = show
FinishedDiagnostics._percent = percent

return FinishedDiagnostics
