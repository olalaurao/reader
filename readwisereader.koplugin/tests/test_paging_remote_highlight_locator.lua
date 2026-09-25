-- SPDX-License-Identifier: AGPL-3.0-only

local Locator = require("koreader/paging_remote_highlight_locator")

local function readerUI(document)
    return {
        paging = {},
        document = document,
    }
end

local function makeDocument(match, options)
    options = options or {}
    local document = {
        configurable = { text_wrap = options.text_wrap or 1 },
    }
    document.findAllText = function(_, text, case_insensitive, context, max_hits)
        assert(case_insensitive == false)
        assert(context == 0)
        assert(max_hits == 3)
        if options.find_error then error("synthetic find error") end
        if options.matches ~= nil then return options.matches end
        return { match }
    end
    document.getWordFromPosition = function(self, pos)
        assert(self.configurable.text_wrap == 0,
            "native endpoint validation must disable text wrapping")
        if options.word_error then error("synthetic word error") end
        if pos.x < 35 then
            return { word = options.first_word or "Exact" }
        end
        return { word = options.last_word or "passage" }
    end
    document.getTextFromPositions = function(self, pos0, pos1)
        assert(self.configurable.text_wrap == 0,
            "native full-text diagnostic must disable text wrapping")
        if options.text_error then error("synthetic text error") end
        return {
            text = options.roundtrip_text or "Exact passage",
            pos0 = pos0,
            pos1 = pos1,
            pboxes = match and match.boxes or {},
        }
    end
    return document
end

return function()
    do
        local match = {
            start = 7,
            matched_text = "Exact passage",
            boxes = {
                { x = 10, y = 20, w = 20, h = 10 },
                { x = 40, y = 20, w = 30, h = 10 },
            },
        }
        local document = makeDocument(match)
        local locator, status = Locator.findUnique(
            readerUI(document),
            "Exact passage"
        )
        assert(status == "unique_exact")
        assert(locator.page == 7)
        assert(locator.text == "Exact passage")
        assert(locator.matched_text == "Exact passage")
        assert(locator.boundary_kind == "exact")
        assert(locator.roundtrip_matches_search == true)
        assert(#locator.pboxes == 2)
        assert(locator.pos0.page == 7 and locator.pos1.page == 7)
        assert(document.configurable.text_wrap == 1,
            "text_wrap must be restored after the native checks")
    end

    -- KOReader paging search deliberately matches the first query word against
    -- the suffix of a PDF word and the last query word against its prefix.
    -- Search boxes therefore cover the complete boundary words.
    do
        local match = {
            start = 4,
            matched_text = "conhecimento que cruza Tarot",
            boxes = {
                { x = 10, y = 20, w = 20, h = 10 },
                { x = 40, y = 20, w = 20, h = 10 },
                { x = 70, y = 20, w = 20, h = 10 },
                { x = 100, y = 20, w = 20, h = 10 },
            },
        }
        local document = makeDocument(match, {
            first_word = "conhecimento",
            last_word = "Tarot",
            roundtrip_text = "conhecimento que cruza Tarot",
        })
        local locator, status = Locator.findUnique(
            readerUI(document),
            "hecimento que cruza Tar"
        )
        assert(status == "unique_boundary")
        assert(locator.boundary_kind == "boundary_expanded")
        assert(locator.first_word == "conhecimento")
        assert(locator.last_word == "Tarot")
        assert(locator.roundtrip_matches_search == true)
        assert(locator.text == "hecimento que cruza Tar")
        assert(#locator.pboxes == 4)
    end

    -- Whitespace representation alone does not turn an otherwise exact token
    -- sequence into a boundary expansion.
    do
        local match = {
            start = 2,
            matched_text = "One two",
            boxes = {
                { x = 10, y = 20, w = 20, h = 10 },
                { x = 40, y = 20, w = 20, h = 10 },
            },
        }
        local document = makeDocument(match, {
            first_word = "One",
            last_word = "two",
            roundtrip_text = "One two",
        })
        local locator, status = Locator.findUnique(
            readerUI(document),
            "One\ntwo"
        )
        assert(status == "unique_exact")
        assert(locator.roundtrip_matches_search == true)
    end

    -- Full-text reconstruction may differ because KOPT independently cleans
    -- spaces/hyphenation. Endpoint word evidence remains the position proof.
    do
        local match = {
            start = 2,
            matched_text = "alpha beta",
            boxes = {
                { x = 10, y = 20, w = 20, h = 10 },
                { x = 40, y = 20, w = 20, h = 10 },
            },
        }
        local document = makeDocument(match, {
            first_word = "alpha",
            last_word = "beta",
            roundtrip_text = "alphabeta",
        })
        local locator, status = Locator.findUnique(
            readerUI(document),
            "alpha beta"
        )
        assert(status == "unique_exact")
        assert(locator.roundtrip_matches_search == false)
    end

    do
        local match = {
            start = 2,
            matched_text = "alpha beta",
            boxes = {
                { x = 10, y = 20, w = 20, h = 10 },
                { x = 40, y = 20, w = 20, h = 10 },
            },
        }
        local document = makeDocument(match, {
            first_word = "wrong",
            last_word = "beta",
        })
        local locator, status = Locator.findUnique(
            readerUI(document),
            "alpha beta"
        )
        assert(locator == nil and status == "geometry_mismatch")
    end

    do
        local match = {
            start = 2,
            matched_text = "unrelated words",
            boxes = {
                { x = 10, y = 20, w = 20, h = 10 },
                { x = 40, y = 20, w = 20, h = 10 },
            },
        }
        local document = makeDocument(match, {
            first_word = "unrelated",
            last_word = "words",
        })
        local locator, status = Locator.findUnique(
            readerUI(document),
            "alpha beta"
        )
        assert(locator == nil and status == "search_text_diff")
    end

    do
        local document = makeDocument(nil, {
            matches = {
                {
                    start = 1,
                    matched_text = "Repeated",
                    boxes = { { x=1,y=1,w=5,h=5 } },
                },
                {
                    start = 2,
                    matched_text = "Repeated",
                    boxes = { { x=1,y=1,w=5,h=5 } },
                },
            },
        })
        local locator, status = Locator.findUnique(
            readerUI(document),
            "Repeated"
        )
        assert(locator == nil and status == "ambiguous")
    end

    do
        local document = makeDocument(nil, { matches = {} })
        local locator, status = Locator.findUnique(
            readerUI(document),
            "Missing"
        )
        assert(locator == nil and status == "missing")
    end

    do
        local match = {
            start = 3,
            matched_text = "Wanted",
            boxes = { { x=5,y=5,w=10,h=10 } },
        }
        local document = makeDocument(match, {
            first_word = "Wanted",
            last_word = "Wanted",
            word_error = true,
        })
        local locator, status = Locator.findUnique(
            readerUI(document),
            "Wanted"
        )
        assert(locator == nil and status == "error")
        assert(document.configurable.text_wrap == 1,
            "text_wrap must be restored after endpoint engine failure")
    end

    do
        local match = {
            start = 3,
            matched_text = "Wanted",
            boxes = { { x=5,y=5,w=10,h=10 } },
        }
        local document = makeDocument(match, {
            first_word = "Wanted",
            last_word = "Wanted",
            text_error = true,
        })
        local locator, status = Locator.findUnique(
            readerUI(document),
            "Wanted"
        )
        assert(status == "unique_exact")
        assert(locator.roundtrip_status == "error")
        assert(locator.roundtrip_matches_search == false)
        assert(document.configurable.text_wrap == 1,
            "text_wrap must be restored after full-text diagnostic failure")
    end

    do
        local document = makeDocument({
            start = 1,
            matched_text = "Bad",
            boxes = { { x=1,y=1,w=0,h=5 } },
        })
        local locator, status = Locator.findUnique(
            readerUI(document),
            "Bad"
        )
        assert(locator == nil and status == "invalid_locator")
    end
end
