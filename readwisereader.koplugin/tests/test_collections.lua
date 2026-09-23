-- SPDX-License-Identifier: AGPL-3.0-only

local Collections = require("koreader/collections")

return function()
    local writes = {}
    local rc = {
        coll = {
            favorites = { ["/book.html"] = { file = "/book.html" } },
            ["Readwise: Inbox"] = { ["/book.html"] = { file = "/book.html" } },
        },
        coll_settings = {
            favorites = { order = 1 },
            ["Readwise: Inbox"] = { order = 2 },
        },
    }
    function rc:addCollection(name)
        self.coll[name] = {}
        self.coll_settings[name] = { order = 3 }
    end
    function rc:addItem(file, name) self.coll[name][file] = { file = file } end
    function rc:removeItem(file, name) self.coll[name][file] = nil return true end
    function rc:write(updated) writes[#writes + 1] = updated end
    function rc:_read() self.refreshed = true end

    local adapter = Collections:new{ read_collection = rc }
    local ok = adapter:syncLocation("/book.html", "later")
    assert(ok == true)
    assert(rc.coll.favorites["/book.html"] ~= nil, "unrelated collection must be preserved")
    assert(rc.coll["Readwise: Inbox"]["/book.html"] == nil)
    assert(rc.coll["Readwise: Later"]["/book.html"] ~= nil)
    assert(#writes == 1)

    ok = adapter:syncLocation("/book.html", "later")
    assert(ok == true)
    assert(#writes == 1, "no-op collection sync should not rewrite settings")

    adapter:refresh()
    assert(rc.refreshed == true)
end
