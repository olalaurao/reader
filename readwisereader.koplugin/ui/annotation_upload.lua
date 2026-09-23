-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local UI = {}
UI.__index = UI

function UI:new(options)
    options = options or {}
    return setmetatable({
        uploader = assert(options.uploader, "uploader is required"),
        get_current_path = assert(options.get_current_path, "get_current_path is required"),
    }, self)
end

function UI:getMenuItem()
    return {
        text = _("Upload one current highlight (Gate 9)"),
        keep_menu_open = true,
        callback = function() self:uploadCurrent() end,
    }
end

function UI:uploadCurrent()
    local path = self.get_current_path()
    if type(path) ~= "string" or path == "" then
        UIManager:show(InfoMessage:new{ text = _("Open a Readwise-managed document first.") })
        return
    end
    local report, e = self.uploader:uploadOne(path)
    if not report then
        UIManager:show(InfoMessage:new{ text = (e and e.message) or _("Highlight upload failed safely.") })
        return
    end
    if report.uploaded == 0 then
        UIManager:show(InfoMessage:new{ text = _("No unsynced highlight was found in the current document.") })
        return
    end
    UIManager:show(InfoMessage:new{
        text = string.format(
            _("Gate 9 upload complete\n\nCreated: yes\nMatch: %s\nRemote link persisted: yes\n\nRefresh Reader and confirm the highlight and note are attached to this document. Then run this action again: it must report that there is nothing to upload."),
            tostring(report.match_mode)
        ),
    })
end

return UI
