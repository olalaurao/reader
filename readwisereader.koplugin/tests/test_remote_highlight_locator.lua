-- SPDX-License-Identifier: AGPL-3.0-only

local Locator = require("koreader/remote_highlight_locator")

return function()
    local reader_ui = {
        document = {
            findAllText = function(_, text)
                if text == "Unique" then
                    return { { start = "xp-a", ["end"] = "xp-b" } }
                elseif text == "Repeated" then
                    return {
                        { start = "xp-1", ["end"] = "xp-2" },
                        { start = "xp-3", ["end"] = "xp-4" },
                    }
                end
                return nil
            end,
            getTextFromXPointers = function(_, start, finish)
                assert(start == "xp-a" and finish == "xp-b")
                return "Unique"
            end,
        },
    }

    local locator, status = Locator.findUnique(reader_ui, "Unique")
    assert(status == "unique")
    assert(locator.pos0 == "xp-a")
    assert(locator.pos1 == "xp-b")
    assert(locator.text == "Unique")

    local missing, missing_status = Locator.findUnique(reader_ui, "Missing")
    assert(missing == nil)
    assert(missing_status == "missing")

    local repeated, repeated_status = Locator.findUnique(reader_ui, "Repeated")
    assert(repeated == nil)
    assert(repeated_status == "ambiguous")
end
