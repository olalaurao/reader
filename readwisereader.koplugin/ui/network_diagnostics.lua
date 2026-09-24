-- SPDX-License-Identifier: AGPL-3.0-only

local InfoMessage = require("ui/widget/infomessage")
local NetworkState = require("platform/network_state")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local UI = {}
UI.__index = UI

local function show(value)
    if value == nil then return "unavailable" end
    if value == true then return "true" end
    if value == false then return "false" end
    return tostring(value)
end

function UI:new(options)
    options = options or {}
    return setmetatable({
        network_state = options.network_state or NetworkState:new(),
    }, self)
end

function UI:getMenuItem()
    return {
        text = _("Inspect network state (Gate 13)"),
        keep_menu_open = true,
        callback = function() self:run() end,
    }
end

function UI:run()
    local r = self.network_state:diagnostics()
    local lines = {
        _("Gate 13 network diagnostic"),
        "",
        string.format("Kindle: %s", show(r.is_kindle)),
        string.format(
            "native airplaneMode: %s (%s)",
            show(r.airplane_mode),
            show(r.airplane_mode_source)
        ),
        string.format(
            "native wirelessEnable: %s (%s)",
            show(r.wireless_enable),
            show(r.wireless_enable_source)
        ),
        string.format(
            "native wifid enable: %s (%s)",
            show(r.wifid_enable),
            show(r.wifid_enable_source)
        ),
        "",
        string.format("KOReader interface: %s", show(r.interface)),
        string.format("KOReader isWifiOn: %s", show(r.koreader_is_wifi_on)),
        string.format("KOReader isConnected: %s", show(r.koreader_is_connected)),
        string.format("KOReader isOnline: %s", show(r.koreader_is_online)),
        string.format("KOReader cached Wi-Fi: %s", show(r.koreader_cached_wifi)),
        string.format(
            "KOReader cached connected: %s",
            show(r.koreader_cached_connected)
        ),
        "",
        string.format(
            "Local network hint: %s",
            show(r.plugin_network_available)
        ),
        string.format("Local hint reason: %s", show(r.plugin_network_reason)),
        "",
        _("Sync authority: read-only Readwise probe before writes"),
        _("Remote requests in this diagnostic: none"),
        _("Remote writes: none"),
    }
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
end

UI._show = show

return UI
