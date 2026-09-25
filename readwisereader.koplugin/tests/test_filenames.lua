-- SPDX-License-Identifier: AGPL-3.0-only

local Filenames = require("content/filenames")

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
    assert(not unicode_edge:find("[\128-\191][\128-\191]*%-%-rw%-"),
        "UTF-8 truncation must not leave a continuation-byte fragment before the suffix")


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
