-- SPDX-License-Identifier: AGPL-3.0-only

local Match = require("sync/text_match")

return function()
    local exact, info = Match.findExactSubstring("<p>alpha beta gamma</p>", "beta gamma")
    assert(exact == "beta gamma")
    assert(info.mode == "exact")

    local normalized, normalized_info = Match.findExactSubstring("<p>alpha  beta\ngamma</p>", "alpha beta gamma")
    assert(normalized == "alpha  beta\ngamma")
    assert(normalized_info.mode == "whitespace")

    local none, ambiguous = Match.findExactSubstring("same x same", "same")
    assert(none == nil and ambiguous.kind == "ambiguous")

    local missing, unmatched = Match.findExactSubstring("alpha beta", "not here")
    assert(missing == nil and unmatched.kind == "unmatched")
end
