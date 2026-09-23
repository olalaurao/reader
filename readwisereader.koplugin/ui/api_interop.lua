-- SPDX-License-Identifier: AGPL-3.0-only

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local ApiInteropWorker = require("sync/api_interop_worker")
local _ = require("gettext")

local ApiInteropUI = {}
ApiInteropUI.__index = ApiInteropUI

local function yesno(value)
    return value and _("yes") or _("no")
end

local function errText(err)
    if not err then return _("Gate 8 operation failed safely.") end
    if err.kind == "gate8_state" then
        return err.message or _("Gate 8 steps must be run in order.")
    elseif err.kind == "gate8_mapping" or err.kind == "gate8_mapping_ambiguous" then
        return err.message or _("A deterministic Reader ↔ Readwise highlight mapping was not proven.")
    elseif err.kind == "auth" then
        return _("Readwise rejected the access token.")
    elseif err.kind == "offline" then
        return _("The network is unavailable. Turn Wi-Fi on outside the plugin and try again.")
    elseif err.kind == "rate_limit" then
        return _("Readwise rate limit reached. Wait briefly and retry this same step.")
    elseif err.kind == "timeout" then
        return _("The API request timed out. The disposable spike state was kept for safe retry/cleanup.")
    end
    return err.message or _("Gate 8 operation failed safely.")
end

function ApiInteropUI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        worker = options.worker or ApiInteropWorker,
    }, self)
end

function ApiInteropUI:_preflight()
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

function ApiInteropUI:_confirm(text, ok_text, callback)
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = ok_text,
        ok_callback = callback,
    })
end

function ApiInteropUI:_run(action, progress_text, formatter)
    if not self:_preflight() then return end
    Trapper:wrap(function()
        local completed, report, err = Trapper:dismissableRunInSubprocess(function()
            return self.worker:run(action)
        end, progress_text)

        if not completed then
            UIManager:show(InfoMessage:new{
                text = _("Gate 8 operation cancelled. Use the cleanup action if a disposable document may have been created."),
            })
            return
        end
        if not report then
            UIManager:show(InfoMessage:new{ text = errText(err) })
            return
        end
        UIManager:show(InfoMessage:new{ text = formatter(report) })
    end)
end

function ApiInteropUI:_create()
    self:_confirm(
        _([[Gate 8 will create a temporary Reader article and one temporary highlight with a diagnostic note/tag.

It will not touch your existing Reader documents. Later Gate 8 steps will update and delete only this disposable data. Continue?]]),
        _("Create disposable test"),
        function()
            self:_run(
                "create",
                _([[Creating disposable Reader document and highlight…

This can take several seconds while Reader makes the supplied HTML highlightable.]]),
                function(r)
                    return table.concat({
                        _("Gate 8 · Step 1 complete"),
                        "",
                        string.format(_("v3 child category is highlight: %s"), yesno(r.v3_category == "highlight")),
                        string.format(_("v3 parent link matches: %s"), yesno(r.v3_parent_matches)),
                        string.format(_("Initial note matches: %s"), yesno(r.v3_note_matches)),
                        string.format(_("Highlight tag matches: %s"), yesno(r.v3_tag_matches)),
                        string.format(_("Highlight offset present: %s"), yesno(r.highlight_offset_present)),
                        string.format(_("Highlight DOM location present: %s"), yesno(r.highlight_location_present)),
                        "",
                        _("Now open Reader on web/phone and confirm the temporary 'KOReader Gate 8 disposable' document contains one highlight with:"),
                        r.expected_initial_note or "",
                        _("and tag: ") .. tostring(r.expected_tag or ""),
                        "",
                        _("Then run Gate 8 step 2."),
                    }, "\n")
                end
            )
        end
    )
end

function ApiInteropUI:_probeV3()
    self:_confirm(
        _([[Step 2 will probe the same temporary highlight in Readwise v2 and then update its note/tags through the documented Reader v3 PATCH endpoint.

Only the Gate 8 disposable highlight will be changed.]]),
        _("Probe + update"),
        function()
            self:_run(
                "probe_v3",
                _([[Finding Reader ↔ Readwise mapping and updating the disposable highlight through Reader v3…

The v2 representation may take a few seconds to appear.]]),
                function(r)
                    return table.concat({
                        _("Gate 8 · Step 2 complete"),
                        "",
                        _("Mapping method: ") .. tostring(r.mapping_method or "none"),
                        string.format(_("v2 external_id = Reader child id: %s"), yesno(r.v2_external_id_matches_reader_child)),
                        string.format(_("v2 text matches: %s"), yesno(r.v2_text_matches)),
                        string.format(_("v3 parent still matches: %s"), yesno(r.v3_parent_matches)),
                        string.format(_("v3 note update verified: %s"), yesno(r.v3_note_update_verified)),
                        string.format(_("v3 tag update verified: %s"), yesno(r.v3_tag_update_verified)),
                        string.format(_("Highlight offset present: %s"), yesno(r.highlight_offset_present)),
                        string.format(_("Highlight DOM location present: %s"), yesno(r.highlight_location_present)),
                        "",
                        _("Refresh the temporary document in Reader and confirm its highlight note is now:"),
                        r.expected_v3_note or "",
                        "",
                        _("Then run Gate 8 step 3."),
                    }, "\n")
                end
            )
        end
    )
end

function ApiInteropUI:_updateV2()
    self:_confirm(
        _([[Step 3 will update the temporary highlight note and color through Readwise v2, then query Reader v3 to see whether the same change propagates back.

Only the Gate 8 disposable highlight will be changed.]]),
        _("Update through v2"),
        function()
            self:_run(
                "update_v2",
                _([[Updating disposable highlight through Readwise v2 and verifying through Reader v3…]]),
                function(r)
                    return table.concat({
                        _("Gate 8 · Step 3 complete"),
                        "",
                        string.format(_("v2 note response matches: %s"), yesno(r.v2_note_update_response_matches)),
                        string.format(_("v2 color response is green: %s"), yesno(r.v2_color_update_response_matches)),
                        string.format(_("Reader v3 saw v2 note update: %s"), yesno(r.v3_saw_v2_note_update)),
                        "",
                        _("Refresh Reader and confirm the temporary highlight note is now:"),
                        r.expected_v2_note or "",
                        _("and its color is green if Reader exposes that color."),
                        "",
                        _("Then run Gate 8 step 4 to test deletion and clean up."),
                    }, "\n")
                end
            )
        end
    )
end

function ApiInteropUI:_deleteCleanup()
    self:_confirm(
        _([[Step 4 will DELETE the disposable highlight through Reader v3, probe whether Readwise v2 also considers it gone, and then delete the temporary parent document.

If v2 still exposes the disposable highlight, the diagnostic will use the already-proven numeric v2 ID to delete that same temporary highlight during cleanup.]]),
        _("Delete + clean up"),
        function()
            self:_run(
                "delete_cleanup",
                _([[Deleting the disposable highlight, checking both APIs, and cleaning the temporary Reader document…]]),
                function(r)
                    return table.concat({
                        _("Gate 8 · Step 4 complete"),
                        "",
                        string.format(_("Reader v3 DELETE succeeded: %s"), yesno(r.v3_delete_success)),
                        string.format(_("Reader v3 no longer lists highlight: %s"), yesno(r.v3_missing_after_delete)),
                        string.format(_("Readwise v2 no longer exposes it after v3 delete: %s"), yesno(r.v2_missing_after_v3_delete)),
                        string.format(_("Readwise v2 still exposed it initially: %s"), yesno(r.v2_still_visible_after_v3_delete)),
                        string.format(_("v2 DELETE needed for cleanup: %s"), yesno(r.v2_delete_used)),
                        string.format(_("v2 DELETE cleanup succeeded: %s"), yesno(not r.v2_delete_used or r.v2_delete_success)),
                        string.format(_("Temporary parent cleanup succeeded: %s"), yesno(r.parent_cleanup_success)),
                        "",
                        _("Refresh Reader and confirm the temporary Gate 8 document is gone."),
                    }, "\n")
                end
            )
        end
    )
end

function ApiInteropUI:_cleanup()
    self:_confirm(
        _([[This recovery action tries to delete only the IDs stored for the Gate 8 disposable document/highlight and clears Gate 8 state after successful cleanup.

Use it after a cancelled/failed Gate 8 step.]]),
        _("Clean disposable data"),
        function()
            self:_run(
                "cleanup",
                _("Cleaning Gate 8 disposable data…"),
                function(r)
                    return table.concat({
                        _("Gate 8 cleanup"),
                        "",
                        string.format(_("Reader highlight cleanup: %s"), yesno(r.highlight_cleanup)),
                        string.format(_("Readwise v2 cleanup: %s"), yesno(r.v2_cleanup)),
                        string.format(_("Parent document cleanup: %s"), yesno(r.parent_cleanup)),
                        string.format(_("Local Gate 8 state cleared: %s"), yesno(r.cleared)),
                    }, "\n")
                end
            )
        end
    )
end

function ApiInteropUI:getMenuItem()
    return {
        text = _("Annotation API spike (Gate 8)"),
        sub_item_table = {
            {
                text = _("1. Create disposable highlight"),
                callback = function() self:_create() end,
            },
            {
                text = _("2. Probe mapping + v3 note update"),
                callback = function() self:_probeV3() end,
            },
            {
                text = _("3. Update note/color through v2"),
                callback = function() self:_updateV2() end,
            },
            {
                text = _("4. Delete + cleanup"),
                callback = function() self:_deleteCleanup() end,
            },
            {
                text = _("Recovery: clean disposable Gate 8 data"),
                callback = function() self:_cleanup() end,
            },
        },
    }
end

ApiInteropUI._yesno = yesno
ApiInteropUI._errText = errText

return ApiInteropUI
