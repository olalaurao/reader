-- SPDX-License-Identifier: AGPL-3.0-only

local Config = require("config")

local function fakeSettings(initial)
    local settings = {
        data = initial or {},
        flush_count = 0,
        close_count = 0,
    }

    function settings:readSetting(key)
        return self.data[key]
    end

    function settings:saveSetting(key, value)
        self.data[key] = value
        return self
    end

    function settings:delSetting(key)
        self.data[key] = nil
        return self
    end

    function settings:flush()
        self.flush_count = self.flush_count + 1
        return self
    end

    function settings:close()
        self.close_count = self.close_count + 1
    end

    return settings
end

return function()
    local settings = fakeSettings()
    local config = Config:new{ settings = settings }

    assert(config:getAccessToken() == nil)
    assert(config:hasAccessToken() == false)

    local ok, err = config:setAccessToken("   ")
    assert(ok == false)
    assert(err == "empty")
    assert(settings.flush_count == 0)

    ok = config:setAccessToken("  abc123  ")
    assert(ok == true)
    assert(config:getAccessToken() == "abc123")
    assert(config:hasAccessToken() == true)
    assert(settings.flush_count == 1)

    config:clearAccessToken()
    assert(config:getAccessToken() == nil)
    assert(config:hasAccessToken() == false)
    assert(settings.flush_count == 2)

    config:close()
    assert(settings.close_count == 1)
end
