-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Worker = require("sync/reconnect_probe_worker")
local _ = require("gettext")

local UI = {}
UI.__index = UI

local function yesNo(value)
    return value and "yes" or "no"
end

local function itemLine(index, item)
    local parts = {
        string.format("#%d", index),
        "status=" .. tostring(item.status or "unknown"),
        "attempts=" .. tostring(item.attempts or 0),
        "remote_id=" .. yesNo(item.has_remote_id == true),
        "marker_matches=" .. tostring(item.marker_matches or 0),
        "parent_read=" .. tostring(item.parent_read or "not_run"),
        "match=" .. tostring(item.match_status or "not_run"),
    }
    if item.match_mode then
        parts[#parts + 1] = "mode=" .. tostring(item.match_mode)
    end
    if item.error_kind then
        parts[#parts + 1] = "error=" .. tostring(item.error_kind)
    end
    return table.concat(parts, " ")
end

function UI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        worker = options.worker or Worker,
    }, self)
end

function UI:getMenuItem()
    return {
        text = _("Inspect reconnect queue (Gate 13)"),
        keep_menu_open = true,
        callback = function() self:run() end,
    }
end

function UI:run()
    if not self.config:hasAccessToken() then
        UIManager:show(InfoMessage:new{
            text = _("No access token is configured."),
        })
        return
    end

    Trapper:wrap(function()
        local completed, report, err = Trapper:dismissableRunInSubprocess(function()
            return self.worker:run()
        end, _([[Inspecting Gate 13 reconnect state…

Tap to cancel. This diagnostic is read-only remotely: it inspects the durable local queue and performs Reader GET/LIST requests only. It never creates, updates, or deletes a remote annotation.]]))

        if not completed then
            UIManager:show(InfoMessage:new{
                text = _("Gate 13 reconnect diagnostic cancelled."),
            })
            return
        end

        if not report then
            local stage = err and err.stage
                or (self.worker.lastStage and self.worker:lastStage())
                or "unavailable"
            UIManager:show(InfoMessage:new{
                text = string.format(
                    _("Gate 13 reconnect diagnostic ended without a report. Last durable stage: %s. Remote writes: none."),
                    tostring(stage)
                ),
            })
            return
        end

        local lines = {
            _("Gate 13 reconnect diagnostic"),
            "",
            string.format(_("Stage: %s"), tostring(report.stage or "unknown")),
            string.format(_("Auth probe: %s"), tostring(report.auth_status or "unknown")),
            string.format(_("Queue pending: %d"), report.queue_pending or 0),
            string.format(_("Queue retry_wait: %d"), report.queue_retry_wait or 0),
            string.format(_("Queue in_flight: %d"), report.queue_in_flight or 0),
            string.format(_("Queue blocked: %d"), report.queue_blocked or 0),
            string.format(_("Queue succeeded: %d"), report.queue_succeeded or 0),
            string.format(_("Marker scan: %s"), tostring(report.marker_scan_status or "unknown")),
            string.format(_("Marker scan pages: %d"), report.marker_scan_pages or 0),
            string.format(_("Active marker matches: %d"), report.marker_matches_total or 0),
            "",
            _("Recent create queue items"),
        }

        for index, item in ipairs(report.items or {}) do
            lines[#lines + 1] = itemLine(index, item)
        end
        if #(report.items or {}) == 0 then
            lines[#lines + 1] = _("(none)")
        end

        lines[#lines + 1] = ""
        lines[#lines + 1] = _("Remote writes: none")

        UIManager:show(InfoMessage:new{
            text = table.concat(lines, "\n"),
        })
    end)
end

UI._itemLine = itemLine
UI._yesNo = yesNo

return UI
