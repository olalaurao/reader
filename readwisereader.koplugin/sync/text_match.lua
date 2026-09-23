-- SPDX-License-Identifier: AGPL-3.0-only

local TextMatch = {}

local function isSpace(ch)
    return ch == " " or ch == "\t" or ch == "\r" or ch == "\n" or ch == "\f"
end

local function whitespacePattern(text)
    local parts = {}
    local i, n = 1, #text
    while i <= n do
        local ch = text:sub(i, i)
        if isSpace(ch) then
            while i <= n and isSpace(text:sub(i, i)) do i = i + 1 end
            parts[#parts + 1] = "%s+"
        else
            local start = i
            while i <= n and not isSpace(text:sub(i, i)) do i = i + 1 end
            parts[#parts + 1] = text:sub(start, i - 1):gsub("([^%w])", "%%%1")
        end
    end
    return table.concat(parts)
end

local function uniqueLiteral(haystack, needle)
    local first = haystack:find(needle, 1, true)
    if not first then return nil end
    local second = haystack:find(needle, first + 1, true)
    if second then return nil, "ambiguous" end
    return needle, "exact"
end

function TextMatch.findExactSubstring(remote_content, local_text)
    if type(remote_content) ~= "string" or remote_content == "" then
        return nil, { kind = "content", retryable = false, message = "Reader content is unavailable." }
    end
    if type(local_text) ~= "string" or local_text == "" then
        return nil, { kind = "text", retryable = false, message = "Local highlight text is empty." }
    end

    local literal, mode = uniqueLiteral(remote_content, local_text)
    if literal then return literal, { mode = mode } end
    if mode == "ambiguous" then
        return nil, { kind = "ambiguous", retryable = false, message = "Highlight text occurs more than once in Reader content." }
    end

    local pattern = whitespacePattern(local_text)
    if pattern == "" then
        return nil, { kind = "unmatched", retryable = false, message = "Highlight could not be matched safely." }
    end
    local s, e = remote_content:find(pattern)
    if not s then
        return nil, { kind = "unmatched", retryable = false, message = "Highlight could not be matched safely." }
    end
    local s2 = remote_content:find(pattern, e + 1)
    if s2 then
        return nil, { kind = "ambiguous", retryable = false, message = "Normalized highlight text has multiple Reader matches." }
    end
    return remote_content:sub(s, e), { mode = "whitespace" }
end

return TextMatch
