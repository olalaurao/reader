-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local TagDiagnosticsWorker = require("sync/tag_diagnostics")
local _ = require("gettext")

local TagDiagnosticsUI = {}
TagDiagnosticsUI.__index = TagDiagnosticsUI

local function categoriesText(categories)
    local keys = {}
    for key, count in pairs(categories or {}) do
        if tonumber(count) and count > 0 then keys[#keys + 1] = key end
    end
    table.sort(keys)
    if #keys == 0 then return _("none") end
    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = string.format("%s=%d", key, categories[key])
    end
    return table.concat(parts, ", ")
end

function TagDiagnosticsUI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        worker = options.worker or TagDiagnosticsWorker,
        dialog = nil,
    }, self)
end

function TagDiagnosticsUI:getMenuItem()
    return {
        text = _("Check Reader document tag (Gate 4A)"),
        keep_menu_open = true,
        callback = function()
            self:showDialog()
        end,
    }
end

function TagDiagnosticsUI:_preflight()
    if not self.config:hasAccessToken() then
        UIManager:show(InfoMessage:new{ text = _("No access token is configured.") })
        return false
    end
    if not NetworkMgr:isOnline() then
        UIManager:show(InfoMessage:new{
            text = _("No internet connection. Turn Wi-Fi on outside the plugin and try again."),
        })
        return false
    end
    return true
end

function TagDiagnosticsUI:showDialog()
    if not self:_preflight() then return end

    self.dialog = MultiInputDialog:new{
        title = _("Reader document tag diagnostic"),
        fields = {
            {
                text = "gate4a-tag-test",
                hint = _("Exact document tag name"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.dialog)
                    end,
                },
                {
                    text = _("Check"),
                    is_enter_default = true,
                    callback = function()
                        local fields = self.dialog:getFields()
                        local tag_name = fields[1]
                        UIManager:close(self.dialog)
                        self.dialog = nil
                        if type(tag_name) ~= "string" or tag_name:match("^%s*$") then
                            UIManager:show(InfoMessage:new{ text = _("Enter a tag name.") })
                            return
                        end
                        self:run(tag_name:match("^%s*(.-)%s*$"))
                    end,
                },
            },
        },
    }
    UIManager:show(self.dialog)
    self.dialog:onShowKeyboard()
end

function TagDiagnosticsUI:run(tag_name)
    if not self:_preflight() then return end
    Trapper:wrap(function()
        local completed, report, err = Trapper:dismissableRunInSubprocess(function()
            return self.worker:run(tag_name)
        end, _([[Checking Reader document tag…

Tap to cancel. This uses Reader's Tag LIST and tag-filtered Document LIST only.]]))

        if not completed then
            UIManager:show(InfoMessage:new{ text = _("Tag diagnostic cancelled.") })
            return
        end
        if not report then
            UIManager:show(InfoMessage:new{
                text = err and err.message or _("Tag diagnostic failed safely."),
            })
            return
        end

        local lines = {
            _("Reader document tag diagnostic"),
            "",
            string.format(_("Tag: %s"), report.tag_name or tag_name),
            string.format(_("Tag exists in Reader Tag API: %s"),
                report.tag_found and _("yes") or _("no")),
        }
        if report.tag_found then
            lines[#lines + 1] = string.format(_("Documents returned for this tag: %d"),
                report.total_matches or 0)
            lines[#lines + 1] = string.format(_("Top-level documents: %d"),
                report.top_level_matches or 0)
            lines[#lines + 1] = string.format(_("Top-level articles: %d"),
                report.article_matches or 0)
            lines[#lines + 1] = string.format(_("Already managed by this plugin: %d"),
                report.managed_matches or 0)
            lines[#lines + 1] = string.format(_("Managed + local: %d"),
                report.managed_local_matches or 0)
            lines[#lines + 1] = string.format(_("Returned payloads containing this tag name: %d"),
                report.payload_has_tag or 0)
            lines[#lines + 1] = string.format(_("Categories: %s"),
                categoriesText(report.categories))
            lines[#lines + 1] = string.format(_("Tag API pages: %d; document pages: %d"),
                report.tag_pages or 0, report.document_pages or 0)
        end

        UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
    end)
end

TagDiagnosticsUI._categoriesText = categoriesText

return TagDiagnosticsUI
