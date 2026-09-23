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
    assert(config:getDownloadDirectory() == "/mnt/us/documents/Readwise")
    assert(config:isSyncLocationEnabled("new") == true)
    assert(config:isSyncLocationEnabled("later") == true)
    assert(config:isSyncLocationEnabled("archive") == false)
    assert(config:isSyncCategoryEnabled("article") == true)

    local root_ok, root_err = config:setDownloadDirectory("../unsafe")
    assert(root_ok == false)
    assert(root_err == "unsafe")
    root_ok, root_err = config:setDownloadDirectory("/mnt/us/documents/../escape")
    assert(root_ok == false)
    assert(root_err == "unsafe")
    root_ok, root_err = config:setDownloadDirectory("/mnt/us/other")
    assert(root_ok == false)
    assert(root_err == "unsafe")

    root_ok = config:setDownloadDirectory("/mnt/us/documents/My Reader/")
    assert(root_ok == true)
    assert(config:getDownloadDirectory() == "/mnt/us/documents/My Reader")

    config:setSyncLocationEnabled("archive", true)
    config:setSyncLocationEnabled("new", false)
    assert(config:isSyncLocationEnabled("archive") == true)
    assert(config:isSyncLocationEnabled("new") == false)

    local flush_before_token = settings.flush_count
    local ok, err = config:setAccessToken("   ")
    assert(ok == false)
    assert(err == "empty")
    assert(settings.flush_count == flush_before_token)

    ok = config:setAccessToken("  abc123  ")
    assert(ok == true)
    assert(config:getAccessToken() == "abc123")
    assert(config:hasAccessToken() == true)
    assert(settings.flush_count == flush_before_token + 1)

    config:clearAccessToken()
    assert(config:getAccessToken() == nil)
    assert(config:hasAccessToken() == false)
    assert(settings.flush_count == flush_before_token + 2)

    config:close()
    assert(settings.close_count == 1)
end
