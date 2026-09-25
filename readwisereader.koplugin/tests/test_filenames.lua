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

    local multilingual = Filenames.build(
        "漢字 café é 👩🏽‍💻 العربية",
        "reader-multilingual",
        "html"
    )
    assert(multilingual:find("漢字", 1, true))
    assert(multilingual:find("العربية", 1, true))
    assert(multilingual:find("👩🏽‍💻", 1, true))

    -- Byte truncation must never cut a multibyte codepoint in half.
    assert(Filenames._truncateUtf8Bytes("A🧠B", 3) == "A")
    assert(Filenames._truncateUtf8Bytes("A🧠B", 5) == "A🧠")
    assert(Filenames._truncateUtf8Bytes("A🧠B", 6) == "A🧠B")

    local hostile = Filenames.build("../bad\\path/:*?\"<>| .. title", "reader-hostile", "html")
    assert(not hostile:find("/", 1, true))
    assert(not hostile:find("\\", 1, true))
    assert(not hostile:find("..", 1, true))

    local long = Filenames.build(string.rep("á", 200), "reader-long", "html")
    assert(#long <= Filenames.DEFAULT_MAX_FILENAME_BYTES)
    assert(long:sub(-5) == ".html")

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
