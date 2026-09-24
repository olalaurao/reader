-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local UI = {}
UI.__index = UI

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

function UI:new(options)
    options = options or {}
    return setmetatable({
        documents = assert(options.documents, "documents repository is required"),
        status = assert(options.status, "KOReader status adapter is required"),
        worker = assert(options.worker, "content refresh worker is required"),
        get_current_path = options.get_current_path or function() return nil end,
    }, self)
end

function UI:getMenuItem()
    return {
        text = _("Inspect content refresh safety (Gate 15)"),
        keep_menu_open = true,
        callback = function() self:run() end,
    }
end

function UI:run()
    local path = self.get_current_path()
    if not path then
        UIManager:show(InfoMessage:new{
            text = _("Open a managed Reader document before running the Gate 15 diagnostic."),
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

    local reading_state, status_err = self.status:scan(path)
    if not reading_state then
        UIManager:show(InfoMessage:new{
            text = status_err and status_err.message
                or _("KOReader reading state could not be inspected safely."),
        })
        return
    end

    local sanitized = {
        sidecar_present = reading_state.sidecar_present == true,
        percent_finished = reading_state.percent_finished,
        annotation_count = reading_state.annotation_count or 0,
        last_xpointer_present = reading_state.last_xpointer_present == true,
        last_page_present = reading_state.last_page_present == true,
        partial_md5_checksum_present =
            reading_state.partial_md5_checksum_present == true,
        has_reading_state = reading_state.has_reading_state == true,
    }

    Trapper:wrap(function()
        local completed, report, err = Trapper:dismissableRunInSubprocess(
            function()
                return self.worker:run{
                    local_path = path,
                    reading_state = sanitized,
                }
            end,
            _([[Inspecting Gate 15 content-refresh safety…

Tap to cancel. This diagnostic reads the local document and Reader document but never replaces content or writes remote/local state.]])
        )

        if not completed then
            UIManager:show(InfoMessage:new{
                text = _("Gate 15 content-refresh diagnostic cancelled."),
            })
            return
        end
        if not report then
            UIManager:show(InfoMessage:new{
                text = err and err.message
                    or _("Gate 15 content-refresh diagnostic failed safely."),
            })
            return
        end

        local lines = {
            _("Gate 15 content-refresh diagnostic"),
            "",
            string.format(_("Category: %s"), show(report.category)),
            string.format(_("Local format: %s"), show(report.local_format)),
            string.format(
                _("Download strategy: %s"),
                show(report.download_strategy)
            ),
            string.format(_("Local file present: %s"), show(report.local_present)),
            string.format(_("Sidecar present: %s"), show(report.sidecar_present)),
            string.format(
                _("Sidecar percent_finished: %s"),
                percent(report.percent_finished)
            ),
            string.format(
                _("Sidecar annotations: %d"),
                report.annotation_count or 0
            ),
            string.format(
                _("Last XPointer present: %s"),
                show(report.last_xpointer_present)
            ),
            string.format(
                _("Last page present: %s"),
                show(report.last_page_present)
            ),
            string.format(
                _("Partial file checksum present: %s"),
                show(report.partial_md5_checksum_present)
            ),
            string.format(
                _("Reading state at risk: %s"),
                show(report.has_reading_state)
            ),
            "",
            string.format(
                _("DB remote revision: %s"),
                show(report.db_remote_updated_at)
            ),
            string.format(
                _("Materialized remote revision: %s"),
                show(report.materialized_remote_updated_at)
            ),
            string.format(
                _("Refresh pending: %s"),
                show(report.refresh_pending)
            ),
            string.format(
                _("Pending remote revision: %s"),
                show(report.refresh_remote_updated_at)
            ),
            string.format(
                _("Current Reader revision: %s"),
                show(report.remote_updated_at)
            ),
            string.format(
                _("Remote revision state: %s"),
                show(report.remote_revision_state)
            ),
            "",
            string.format(_("Remote probe: %s"), show(report.remote_probe)),
            string.format(
                _("Visible-text comparison: %s"),
                show(report.comparison)
            ),
            string.format(_("Local HTML bytes: %d"), report.local_bytes or 0),
            string.format(
                _("Remote HTML bytes: %d"),
                report.remote_html_bytes or 0
            ),
            string.format(
                _("V1 refresh decision: %s"),
                show(report.decision)
            ),
            string.format(
                _("Automatic replacement allowed: %s"),
                show(report.replacement_allowed)
            ),
            "",
            _("Remote writes: none"),
            _("Local writes: none"),
        }

        UIManager:show(InfoMessage:new{
            text = table.concat(lines, "\n"),
        })
    end)
end

UI._show = show
UI._percent = percent

return UI
