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

    local saved_foldercovers = package.loaded["features/library/sui_foldercovers"]
    local saved_filemanager = package.loaded["apps/filemanager/filemanager"]
    local simpleui_invalidations = 0
    local filemanager_refreshes = 0
    package.loaded["features/library/sui_foldercovers"] = {
        invalidateItemTableCache = function()
            simpleui_invalidations = simpleui_invalidations + 1
        end,
    }
    package.loaded["apps/filemanager/filemanager"] = {
        instance = {
            file_chooser = {
                refreshPath = function()
                    filemanager_refreshes = filemanager_refreshes + 1
                end,
            },
        },
    }

    ok = adapter:refresh()
    assert(ok == true)
    assert(rc.refreshed == true)
    assert(simpleui_invalidations == 1, "SimpleUI folder item cache must be invalidated")
    assert(filemanager_refreshes == 1, "live FileManager path must be refreshed")

    -- A third-party UI refresh failure must not turn a successful document
    -- sync into a collection/persistence failure.
    package.loaded["features/library/sui_foldercovers"] = {
        invalidateItemTableCache = function() error("synthetic SimpleUI failure") end,
    }
    package.loaded["apps/filemanager/filemanager"] = {
        instance = {
            file_chooser = {
                refreshPath = function() error("synthetic FileManager failure") end,
            },
        },
    }
    assert(adapter:refresh() == true)

    package.loaded["features/library/sui_foldercovers"] = saved_foldercovers
    package.loaded["apps/filemanager/filemanager"] = saved_filemanager
end
