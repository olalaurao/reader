-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubbedUI(run)
    local names = {
        "ui/network_diagnostics",
        "ui/widget/infomessage",
        "ui/uimanager",
        "gettext",
        "platform/network_state",
    }
    local loaded, preload = {}, {}
    for _, name in ipairs(names) do
        loaded[name] = package.loaded[name]
        preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    local state = { shown = {} }
    package.preload["gettext"] = function()
        return function(v) return v end
    end
    package.preload["ui/widget/infomessage"] = function()
        return { new = function(_, value) return value end }
    end
    package.preload["ui/uimanager"] = function()
        return {
            show = function(_, value)
                state.shown[#state.shown + 1] = value
            end,
        }
    end
    package.preload["platform/network_state"] = function()
        return {
            new = function()
                return {
                    diagnostics = function()
                        return {
                            is_kindle = true,
                            airplane_mode = 1,
                            airplane_mode_source = "liblipclua",
                            wireless_enable = 0,
                            wireless_enable_source = "liblipclua",
                            wifid_enable = 0,
                            wifid_enable_source = "liblipclua",
                            interface = "wlan0",
                            koreader_is_wifi_on = false,
                            koreader_is_connected = false,
                            koreader_is_online = false,
                            koreader_cached_wifi = true,
                            koreader_cached_connected = true,
                            plugin_network_available = false,
                            plugin_network_reason = "kindle_airplane_mode",
                        }
                    end,
                }
            end,
        }
    end

    local ok, err = pcall(function()
        run(require("ui/network_diagnostics"), state)
    end)

    for _, name in ipairs(names) do
        package.loaded[name] = loaded[name]
        package.preload[name] = preload[name]
    end
    if not ok then error(err) end
end

return function()
    withStubbedUI(function(UI, state)
        local ui = UI:new{}
        local item = ui:getMenuItem()
        assert(item.text:find("network state", 1, true))
        item.callback()
        assert(#state.shown == 1)
        local text = state.shown[1].text
        assert(text:find("native airplaneMode: 1", 1, true))
        assert(text:find("native wirelessEnable: 0", 1, true))
        assert(text:find("KOReader isOnline: false", 1, true))
        assert(text:find("Local network hint: false", 1, true))
        assert(text:find("Sync authority: read-only Readwise probe before writes", 1, true))
        assert(text:find("Remote requests in this diagnostic: none", 1, true))
        assert(text:find("Remote writes: none", 1, true))
    end)
end
