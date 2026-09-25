-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Worker = require("sync/pdf_highlight_probe_worker")
local Locator = require("koreader/paging_remote_highlight_locator")
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

function UI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        get_current_path =
            assert(options.get_current_path, "get_current_path is required"),
        get_reader_ui =
            assert(options.get_reader_ui, "get_reader_ui is required"),
        worker = options.worker or Worker,
    }, self)
end

function UI:getMenuItem()
    return {
        text = _("Inspect PDF Reader highlights (Gate 17D)"),
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
            text = _(
                "No internet connection. Turn Wi-Fi on outside the plugin and try again."
            ),
        })
        return nil
    end

    local path = self.get_current_path()
    local reader_ui = self.get_reader_ui()
    if type(path) ~= "string" or path == ""
        or not reader_ui or not reader_ui.document then
        UIManager:show(InfoMessage:new{
            text = _("Open a Readwise-managed PDF first."),
        })
        return nil
    end
    if not reader_ui.paging or reader_ui.document.is_pdf ~= true then
        UIManager:show(InfoMessage:new{
            text = _("Gate 17D currently probes paging PDF documents only."),
        })
        return nil
    end
    return path, reader_ui
end

function UI:run()
    local path, reader_ui = self:_preflight()
    if not path then return end

    Trapper:wrap(function()
        local completed, report, err =
            Trapper:dismissableRunInSubprocess(function()
                return self.worker:run(path)
            end, _([[Scanning Reader highlights for this PDF…

Tap to cancel. Gate 17D is read-only: it fetches Reader highlight records and tests KOReader paging/PDF text positions. It does not create, edit, or delete any local or remote annotation.]]))

        if not completed then
            UIManager:show(InfoMessage:new{
                text = _("Gate 17D PDF highlight probe cancelled."),
            })
            return
        end
        if not report then
            UIManager:show(InfoMessage:new{
                text = err and err.message
                    or _("Gate 17D PDF highlight probe failed safely."),
            })
            return
        end

        local tested, unique, ambiguous, missing, text_diff, other =
            0, 0, 0, 0, 0, 0
        local samples = {}
        for _, highlight in ipairs(report.remote_highlights or {}) do
            if tested >= MAX_PROBES then break end
            tested = tested + 1
            local locator, status =
                Locator.findUnique(reader_ui, highlight.content)
            if status == "unique" then
                unique = unique + 1
            elseif status == "ambiguous" then
                ambiguous = ambiguous + 1
            elseif status == "missing" then
                missing = missing + 1
            elseif status == "text_diff" then
                text_diff = text_diff + 1
            else
                other = other + 1
            end

            local page_suffix = locator and locator.page
                and string.format(" [page %d]", locator.page)
                or ""
            samples[#samples + 1] = string.format(
                "%d. %s%s — %s",
                tested,
                status,
                page_suffix,
                clip(highlight.content)
            )
        end

        local lines = {
            _("Gate 17D Reader → KOReader PDF position probe"),
            "",
            string.format(
                _("Reader highlight pages scanned: %d"),
                report.pages or 0
            ),
            string.format(
                _("Reader highlight records scanned: %d"),
                report.records_scanned or 0
            ),
            string.format(
                _("Highlights for this PDF: %d"),
                report.parent_highlight_records or 0
            ),
            string.format(
                _("Highlights with text: %d"),
                report.highlights_with_text or 0
            ),
            string.format(_("Local PDF probes run: %d"), tested),
            string.format(_("Unique exact paging matches: %d"), unique),
            string.format(_("Ambiguous matches: %d"), ambiguous),
            string.format(_("Missing matches: %d"), missing),
            string.format(
                _("Text round-trip differences: %d"),
                text_diff
            ),
            string.format(_("Other/invalid matches: %d"), other),
        }
        if #samples > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = _("Samples:")
            for _, sample in ipairs(samples) do
                lines[#lines + 1] = sample
            end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = _("Remote writes: none")
        lines[#lines + 1] = _("Local annotation/sidecar writes: none")

        UIManager:show(InfoMessage:new{
            text = table.concat(lines, "\n"),
        })
    end)
end

UI._clip = clip

return UI
