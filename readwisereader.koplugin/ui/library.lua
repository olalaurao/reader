-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local LibraryUI = {}
LibraryUI.__index = LibraryUI

local function sortedCountLines(counts)
    local keys = {}
    for key in pairs(counts or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)

    local lines = {}
    if #keys == 0 then
        lines[1] = "  (none)"
        return lines
    end

    for _, key in ipairs(keys) do
        lines[#lines + 1] = string.format("  %s: %d", tostring(key), counts[key])
    end
    return lines
end

local function summaryText(report)
    local lines = {
        _("Reader metadata scan complete"),
        "",
        string.format(_("Top-level documents: %d"), report.top_level_documents or 0),
        string.format(_("API pages: %d"), report.pages or 0),
        string.format(_("Duplicate records ignored: %d"), report.duplicates_ignored or 0),
        string.format(_("Child records ignored: %d"), report.child_records or 0),
        "",
        _("Locations"),
    }

    for _, line in ipairs(sortedCountLines(report.by_location)) do
        lines[#lines + 1] = line
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = _("Categories")
    for _, line in ipairs(sortedCountLines(report.by_category)) do
        lines[#lines + 1] = line
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = _("No documents were downloaded or changed.")
    return table.concat(lines, "\n")
end

local function errorText(err)
    if not err then
        return _("The Reader metadata scan failed.")
    end

    if err.kind == "auth" then
        return _("Readwise rejected the access token. Check Account settings and try again.")
    elseif err.kind == "offline" then
        return _("The network is unavailable. Turn Wi-Fi on outside the plugin and try again.")
    elseif err.kind == "timeout" then
        return _("The Reader metadata scan timed out. Try again.")
    elseif err.kind == "tls" then
        return _("A secure TLS connection to Readwise could not be established.")
    elseif err.kind == "rate_limit" then
        if err.retry_after then
            return string.format(
                _("Readwise rate limit reached. Try again after about %d seconds."),
                err.retry_after
            )
        end
        return _("Readwise rate limit reached. Try again later.")
    elseif err.kind == "decode" then
        return _("Readwise returned metadata in an unexpected format. Nothing was downloaded.")
    elseif err.kind == "pagination" then
        return _("Reader pagination became inconsistent, so the scan stopped safely.")
    elseif err.kind == "cancelled" then
        return _("Reader metadata scan cancelled.")
    end

    return _("The Reader metadata scan failed safely. Nothing was downloaded.")
end

function LibraryUI:new(options)
    options = options or {}
    return setmetatable({
        config = assert(options.config, "config is required"),
        scanner = assert(options.scanner, "scanner is required"),
    }, self)
end

function LibraryUI:getScanMenuItem()
    return {
        text = _("Scan Reader metadata (Gate 2)"),
        keep_menu_open = true,
        callback = function()
            self:scanMetadata()
        end,
    }
end

function LibraryUI:scanMetadata()
    if not self.config:hasAccessToken() then
        UIManager:show(InfoMessage:new{
            text = _("No access token is configured."),
        })
        return
    end

    -- Deliberately inspect connectivity only; V1 never enables/disables Wi-Fi.
    if not NetworkMgr:isOnline() then
        UIManager:show(InfoMessage:new{
            text = _("No internet connection. Turn Wi-Fi on outside the plugin and try again."),
        })
        return
    end

    -- KOReader 2025.04 only makes dismissableRunInSubprocess interactive
    -- when it runs from a Trapper coroutine. Without this wrapper, Trapper
    -- deliberately falls back to a blocking in-process call.
    -- Keep this as the final action in the menu callback, per Trapper:wrap().
    Trapper:wrap(function()
        self:_scanMetadataWrapped()
    end)
end

function LibraryUI:_scanMetadataWrapped()
    local completed, report, err = Trapper:dismissableRunInSubprocess(function()
        return self.scanner:scan()
    end, _([[Scanning Reader library metadata…

Tap to cancel. This Gate 2 scan only reads metadata; it will not download or change documents.]]))

    if not completed then
        UIManager:show(InfoMessage:new{
            text = _("Reader metadata scan cancelled. Nothing was downloaded or changed."),
        })
        return
    end

    if not report then
        UIManager:show(InfoMessage:new{
            text = errorText(err),
        })
        return
    end

    UIManager:show(InfoMessage:new{
        text = summaryText(report),
    })
end

LibraryUI._sortedCountLines = sortedCountLines
LibraryUI._summaryText = summaryText
LibraryUI._errorText = errorText

return LibraryUI
