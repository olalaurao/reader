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

    local one = Filenames.build("Same", "prefix-collision-A", "html")
    local two = Filenames.build("Same", "prefix-collision-B", "html")
    assert(one ~= two)

    local joined = Filenames.joinUnderRoot("/mnt/us/documents/Readwise/", "Articles", ascii)
    assert(joined == "/mnt/us/documents/Readwise/Articles/" .. ascii)
end
