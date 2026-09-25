-- SPDX-License-Identifier: AGPL-3.0-only

local Locator = require("koreader/paging_remote_highlight_locator")

return function()
    do
        local seen_pos0, seen_pos1
        local document = {
            configurable = { text_wrap = 1 },
            findAllText = function(_, text, case_insensitive, context, max_hits)
                assert(text == "Exact passage")
                assert(case_insensitive == false)
                assert(context == 0)
                assert(max_hits == 3)
                return {
                    {
                        start = 7,
                        matched_text = "Exact passage",
                        boxes = {
                            { x = 10, y = 20, w = 20, h = 10 },
                            { x = 40, y = 20, w = 30, h = 10 },
                        },
                    },
                }
            end,
            getTextFromPositions = function(self, pos0, pos1)
                assert(self.configurable.text_wrap == 0,
                    "PDF round-trip must use native page positions")
                seen_pos0, seen_pos1 = pos0, pos1
                return {
                    text = "Exact passage",
                    pos0 = pos0,
                    pos1 = pos1,
                    pboxes = {
                        { x = 10, y = 20, w = 20, h = 10 },
                        { x = 40, y = 20, w = 30, h = 10 },
                    },
                }
            end,
        }
        local locator, status = Locator.findUnique({
            paging = {},
            document = document,
        }, "Exact passage")
        assert(status == "unique")
        assert(locator.page == 7)
        assert(locator.text == "Exact passage")
        assert(#locator.pboxes == 2)
        assert(seen_pos0.page == 7 and seen_pos1.page == 7)
        assert(seen_pos0.x > 10 and seen_pos0.x < 30)
        assert(seen_pos1.x > 40 and seen_pos1.x < 70)
        assert(document.configurable.text_wrap == 1,
            "text_wrap must be restored after the native round-trip")
    end

    do
        local locator, status = Locator.findUnique({
            paging = {},
            document = {
                configurable = { text_wrap = 0 },
                findAllText = function()
                    return {
                        { start = 1, boxes = { { x=1,y=1,w=5,h=5 } } },
                        { start = 2, boxes = { { x=1,y=1,w=5,h=5 } } },
                    }
                end,
                getTextFromPositions = function()
                    error("ambiguous result must not be round-tripped")
                end,
            },
        }, "Repeated")
        assert(locator == nil and status == "ambiguous")
    end

    do
        local locator, status = Locator.findUnique({
            paging = {},
            document = {
                configurable = { text_wrap = 0 },
                findAllText = function() return nil end,
                getTextFromPositions = function() error("must not run") end,
            },
        }, "Missing")
        assert(locator == nil and status == "missing")
    end

    do
        local document = {
            configurable = { text_wrap = 1 },
            findAllText = function()
                return {
                    {
                        start = 3,
                        boxes = { { x=5,y=5,w=10,h=10 } },
                    },
                }
            end,
            getTextFromPositions = function(self)
                assert(self.configurable.text_wrap == 0)
                return { text = "Different" }
            end,
        }
        local locator, status = Locator.findUnique({
            paging = {},
            document = document,
        }, "Wanted")
        assert(locator == nil and status == "text_diff")
        assert(document.configurable.text_wrap == 1)
    end

    do
        local document = {
            configurable = { text_wrap = 1 },
            findAllText = function()
                return {
                    {
                        start = 3,
                        boxes = { { x=5,y=5,w=10,h=10 } },
                    },
                }
            end,
            getTextFromPositions = function(self)
                assert(self.configurable.text_wrap == 0)
                error("synthetic engine error")
            end,
        }
        local locator, status = Locator.findUnique({
            paging = {},
            document = document,
        }, "Wanted")
        assert(locator == nil and status == "error")
        assert(document.configurable.text_wrap == 1,
            "text_wrap must be restored after engine failure")
    end

    local invalid, invalid_status = Locator.findUnique({
        paging = {},
        document = {
            findAllText = function()
                return { { start = 1, boxes = { { x=1,y=1,w=0,h=5 } } } }
            end,
            getTextFromPositions = function() error("must not run") end,
        },
    }, "Bad")
    assert(invalid == nil and invalid_status == "invalid_locator")
end
