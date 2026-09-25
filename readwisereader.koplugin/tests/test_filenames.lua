-- SPDX-License-Identifier: AGPL-3.0-only

local Filenames = require("content/filenames")

local function isValidUtf8(value)
    local i = 1
    while i <= #value do
        local b = value:byte(i)
        local width
        if b < 0x80 then width = 1
        elseif b >= 0xC2 and b <= 0xDF then width = 2
        elseif b >= 0xE0 and b <= 0xEF then width = 3
        elseif b >= 0xF0 and b <= 0xF4 then width = 4
        else return false end
        if i + width - 1 > #value then return false end
        for j = i + 1, i + width - 1 do
            local continuation = value:byte(j)
            if continuation < 0x80 or continuation > 0xBF then return false end
        end
        i = i + width
    end
    return true
end

return function()
    local ascii = Filenames.build("A simple title", "reader-123", "html")
    assert(ascii:find("^A simple title%-%-rw%-"))
    assert(ascii:sub(-5) == ".html")

    local portuguese = Filenames.build("Coração, ação e memória", "reader-pt", "html")
    assert(portuguese:find("Coração", 1, true))

    local emoji = Filenames.build("Thinking 🧠 clearly", "reader-emoji", "html")
    assert(emoji:find("🧠", 1, true))

    local hostile = Filenames.build("../bad\\path/:*?\"<>| .. title", "reader-hostile", "html")
    assert(not hostile:find("/", 1, true))
    assert(not hostile:find("\\", 1, true))
    assert(not hostile:find("..", 1, true))

    local long = Filenames.build(string.rep("á", 200), "reader-long", "html")
    assert(#long <= Filenames.DEFAULT_MAX_FILENAME_BYTES)
    assert(long:sub(-5) == ".html")


    local unicode_edge = Filenames.build(
        string.rep("界", 80) .. "🧠e\204\129",
        "reader-unicode-edge",
        "html"
    )
    assert(#unicode_edge <= Filenames.DEFAULT_MAX_FILENAME_BYTES)
    assert(unicode_edge:sub(-5) == ".html")
    assert(isValidUtf8(unicode_edge),
        "UTF-8 truncation must preserve complete code points")


    local one = Filenames.build("Same", "prefix-collision-A", "html")
    local two = Filenames.build("Same", "prefix-collision-B", "html")
    assert(one ~= two)

    local joined = Filenames.joinUnderRoot("/mnt/us/documents/Readwise/", "Articles", ascii)
    assert(joined == "/mnt/us/documents/Readwise/Articles/" .. ascii)
    local asset_dir = Filenames.assetDirectory("reader-123")
    assert(asset_dir:find("^%.rw%-assets%-"))
    assert(not asset_dir:find("/", 1, true))
    assert(asset_dir == Filenames.assetDirectory("reader-123"))
end
