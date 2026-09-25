-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Worker = require("sync/remote_highlight_probe_worker")
local _ = require("gettext")

local UI = {}
UI.__index = UI

local MAX_PROBES = 3

local function clip(value, limit)
    value = tostring(value or "")
    limit = limit or 120
    if #value <= limit then return value end
    return value:sub(1, limit) .. "…"
end

local function matchOne(reader_ui, text)
    local ok, matches = pcall(
        reader_ui.document.findAllText,
        reader_ui.document,
        text,
        false,
        0,
        3,
        false,
        0
    )
    if not ok then return "error" end
    if type(matches) ~= "table" or #matches == 0 then return "missing" end
    if #matches > 1 then return "ambiguous" end
    local match = matches[1]
    if type(match.start) ~= "string" or type(match["end"]) ~= "string" then
        return "invalid_locator"
    end

    local text_ok, local_text = pcall(
        reader_ui.document.getTextFromXPointers,
        reader_ui.document,
        match.start,
        match["end"]
    )
    if not text_ok or type(local_text) ~= "string" or local_text == "" then
        return "invalid_locator"
    end
    if local_text ~= text then return "text_diff" end
    return "unique"
end

function UI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        get_current_path = assert(options.get_current_path, "get_current_path is required"),
        get_reader_ui = assert(options.get_reader_ui, "get_reader_ui is required"),
        worker = options.worker or Worker,
    }, self)
end

function UI:getMenuItem()
    return {
        text = _("Inspect Reader highlights (Gate 17A)"),
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
    if type(path) ~= "string" or path == "" or not reader_ui or not reader_ui.document then
        UIManager:show(InfoMessage:new{ text = _("Open a Readwise-managed EPUB first.") })
        return nil
    end
    if reader_ui.rolling ~= true then
        UIManager:show(InfoMessage:new{
            text = _("Gate 17A currently supports rolling EPUB/HTML documents only."),
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
        end, _([[Scanning Reader highlights for this document…

Tap to cancel. This gate is read-only: it fetches Reader highlight records and tests KOReader text/XPointer matching, but it does not create, edit, or delete any local or remote annotation.]]))

        if not completed then
            UIManager:show(InfoMessage:new{ text = _("Gate 17A highlight probe cancelled.") })
            return
        end
        if not report then
            UIManager:show(InfoMessage:new{
                text = err and err.message or _("Gate 17A highlight probe failed safely."),
            })
            return
        end

        local tested, unique, ambiguous, missing, other = 0, 0, 0, 0, 0
        local samples = {}
        for _, highlight in ipairs(report.remote_highlights or {}) do
            if tested >= MAX_PROBES then break end
            tested = tested + 1
            local status = matchOne(reader_ui, highlight.content)
            if status == "unique" then
                unique = unique + 1
            elseif status == "ambiguous" then
                ambiguous = ambiguous + 1
            elseif status == "missing" then
                missing = missing + 1
            else
                other = other + 1
            end
            samples[#samples + 1] = string.format(
                "%d. %s — %s",
                tested,
                status,
                clip(highlight.content)
            )
        end

        local lines = {
            _("Gate 17A Reader → KOReader highlight probe"),
            "",
            string.format(_("Reader highlight pages scanned: %d"), report.pages or 0),
            string.format(_("Reader highlight records scanned: %d"), report.records_scanned or 0),
            string.format(_("Highlights for this document: %d"), report.parent_highlight_records or 0),
            string.format(_("Highlights with text: %d"), report.highlights_with_text or 0),
            string.format(_("Local match probes run: %d"), tested),
            string.format(_("Unique exact XPointer matches: %d"), unique),
            string.format(_("Ambiguous matches: %d"), ambiguous),
            string.format(_("Missing matches: %d"), missing),
            string.format(_("Other/invalid matches: %d"), other),
        }
        if #samples > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = _("Samples:")
            for _, sample in ipairs(samples) do lines[#lines + 1] = sample end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = _("Remote writes: none")
        lines[#lines + 1] = _("Local writes: none")

        UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
    end)
end

UI._clip = clip
UI._matchOne = matchOne

return UI
