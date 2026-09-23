-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Worker = require("sync/text_match_probe_worker")
local _ = require("gettext")

local UI = {}
UI.__index = UI

local function clip(value, limit)
    value = tostring(value or "")
    limit = limit or 240
    if #value <= limit then return value end
    return value:sub(1, limit) .. "…"
end

function UI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        get_current_path = assert(options.get_current_path, "get_current_path is required"),
        worker = options.worker or Worker,
    }, self)
end

function UI:getMenuItem()
    return {
        text = _("Test current highlight match (Gate 9)"),
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
    if type(path) ~= "string" or path == "" then
        UIManager:show(InfoMessage:new{ text = _("Open a Readwise-managed document first.") })
        return nil
    end
    return path
end

function UI:run()
    local path = self:_preflight()
    if not path then return end

    Trapper:wrap(function()
        local completed, report, err = Trapper:dismissableRunInSubprocess(function()
            return self.worker:run(path)
        end, _([[Checking the newest local highlight against Reader visible text…

Tap to cancel. This is read-only: it only fetches the current Reader document and never creates, updates, or deletes a remote annotation.]]))

        if not completed then
            UIManager:show(InfoMessage:new{ text = _("Gate 9 text-match diagnostic cancelled.") })
            return
        end
        if not report then
            UIManager:show(InfoMessage:new{
                text = err and err.message or _("Gate 9 text-match diagnostic failed safely."),
            })
            return
        end

        local lines = {
            _("Gate 9 text-match diagnostic"),
            "",
            string.format(_("Matched: %s"), report.matched and _("yes") or _("no")),
            string.format(_("Result: %s"), tostring(report.mode or report.status or "unknown")),
            string.format(_("Local selection: %s"), clip(report.local_text)),
        }
        if report.matched then
            lines[#lines + 1] = string.format(
                _("Reader exact visible text: %s"),
                clip(report.reader_exact_text)
            )
        else
            lines[#lines + 1] = string.format(
                _("Reason: %s"),
                clip(report.message)
            )
        end
        lines[#lines + 1] = _("Remote writes: none")

        UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
    end)
end

UI._clip = clip

return UI
