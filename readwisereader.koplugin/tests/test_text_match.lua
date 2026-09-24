-- SPDX-License-Identifier: AGPL-3.0-only

local Match = require("sync/text_match")

return function()
    local exact, info = Match.findExactSubstring("<p>alpha beta gamma</p>", "beta gamma")
    assert(exact == "beta gamma")
    assert(info.mode == "exact")

    local inline, inline_info = Match.findExactSubstring(
        "<p>Before Sel<em>ect</em>ed text After</p>",
        "Selected text"
    )
    assert(inline == "Selected text")
    assert(inline_info.mode == "exact")

    local line_break, line_info = Match.findExactSubstring(
        "<p>alpha<br>beta gamma</p>",
        "alpha beta gamma"
    )
    assert(line_break == "alpha\nbeta gamma")
    assert(line_info.mode == "whitespace")

    local nbsp, nbsp_info = Match.findExactSubstring(
        "<p>alpha&nbsp;beta</p>",
        "alpha beta"
    )
    assert(nbsp == "alpha\194\160beta")
    assert(nbsp_info.mode == "whitespace")

    local curly, curly_info = Match.findExactSubstring(
        "<p>She said &ldquo;hello&rdquo; — today.</p>",
        'She said "hello" - today.'
    )
    assert(curly == "She said “hello” — today.")
    assert(curly_info.mode == "punctuation")

    local shy, shy_info = Match.findExactSubstring(
        "<p>inter&shy;national</p>",
        "international"
    )
    assert(shy == "inter\194\173national")
    assert(shy_info.mode == "whitespace")

    local decomposed = "Cafe" .. "\204\129"
    local unicode, unicode_info = Match.findExactSubstring(
        "<p>" .. decomposed .. " society</p>",
        "Café society"
    )
    assert(unicode == decomposed .. " society")
    assert(unicode_info.mode == "unicode")

    local hidden, hidden_info = Match.findExactSubstring(
        "<style>.same{}</style><p>visible text</p><script>visible text</script>",
        "visible text"
    )
    assert(hidden == "visible text")
    assert(hidden_info.mode == "exact")

    local none, ambiguous = Match.findExactSubstring(
        "<p>same sentence</p><p>same sentence</p>",
        "same sentence"
    )
    assert(none == nil and ambiguous.kind == "ambiguous")

    local normalized_none, normalized_ambiguous = Match.findExactSubstring(
        "<p>same  sentence</p><p>same\nsentence</p>",
        "same sentence"
    )
    assert(normalized_none == nil and normalized_ambiguous.kind == "ambiguous")

    local missing, unmatched = Match.findExactSubstring(
        "<p>alpha beta</p>",
        "not here"
    )
    assert(missing == nil and unmatched.kind == "unmatched")


    local stages = {}
    local staged, staged_info = Match.findExactSubstring(
        "<p>alpha  beta</p>",
        "alpha beta",
        {
            on_stage = function(stage)
                stages[#stages + 1] = stage
            end,
        }
    )
    assert(staged == "alpha  beta")
    assert(staged_info.mode == "whitespace")
    assert(table.concat(stages, ",") == "validate,visible_text,exact,unicode,whitespace")

    assert(Match._normalizeNFC("e" .. "\204\129") == "é")
    assert(Match._normalizeNFC("\255") == "\255",
        "invalid/non-Latin bytes must stay in Lua and never cross native FFI")

    local visible = Match.visibleText(
        '<div title="1 > 0">one &amp; two</div><!-- hidden --><p>three</p>'
    )
    assert(visible:find("one & two", 1, true))
    assert(visible:find("three", 1, true))
    assert(not visible:find("hidden", 1, true))
end
