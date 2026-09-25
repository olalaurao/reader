-- SPDX-License-Identifier: AGPL-3.0-only

local TextMatch = {}

local NBSP = "\194\160"
local SOFT_HYPHEN = "\194\173"

local BLOCK_TAGS = {
    address = true, article = true, aside = true, blockquote = true,
    dd = true, div = true, dl = true, dt = true, fieldset = true,
    figcaption = true, figure = true, footer = true, form = true,
    h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true,
    header = true, hr = true, li = true, main = true, nav = true,
    ol = true, p = true, pre = true, section = true, table = true,
    tbody = true, td = true, tfoot = true, th = true, thead = true,
    tr = true, ul = true,
}

local ENTITY_MAP = {
    amp = "&",
    apos = "'",
    gt = ">",
    hellip = "…",
    ldquo = "“",
    lsquo = "‘",
    lt = "<",
    mdash = "—",
    nbsp = NBSP,
    ndash = "–",
    quot = '"',
    rdquo = "”",
    rsquo = "’",
    shy = SOFT_HYPHEN,
}

local PUNCT_EQUIV = {
    ["‘"] = "'",
    ["’"] = "'",
    ["‚"] = "'",
    ["‛"] = "'",
    ["“"] = '"',
    ["”"] = '"',
    ["„"] = '"',
    ["‟"] = '"',
    ["‐"] = "-",
    ["‑"] = "-",
    ["‒"] = "-",
    ["–"] = "-",
    ["—"] = "-",
    ["−"] = "-",
}

local GRAVE = "\204\128"
local ACUTE = "\204\129"
local CIRCUMFLEX = "\204\130"
local TILDE = "\204\131"
local DIAERESIS = "\204\136"
local CEDILLA = "\204\167"

local LATIN_COMPOSE = {
    ["A" .. GRAVE] = "À", ["a" .. GRAVE] = "à",
    ["A" .. ACUTE] = "Á", ["a" .. ACUTE] = "á",
    ["A" .. CIRCUMFLEX] = "Â", ["a" .. CIRCUMFLEX] = "â",
    ["A" .. TILDE] = "Ã", ["a" .. TILDE] = "ã",
    ["A" .. DIAERESIS] = "Ä", ["a" .. DIAERESIS] = "ä",
    ["E" .. GRAVE] = "È", ["e" .. GRAVE] = "è",
    ["E" .. ACUTE] = "É", ["e" .. ACUTE] = "é",
    ["E" .. CIRCUMFLEX] = "Ê", ["e" .. CIRCUMFLEX] = "ê",
    ["E" .. DIAERESIS] = "Ë", ["e" .. DIAERESIS] = "ë",
    ["I" .. GRAVE] = "Ì", ["i" .. GRAVE] = "ì",
    ["I" .. ACUTE] = "Í", ["i" .. ACUTE] = "í",
    ["I" .. CIRCUMFLEX] = "Î", ["i" .. CIRCUMFLEX] = "î",
    ["I" .. DIAERESIS] = "Ï", ["i" .. DIAERESIS] = "ï",
    ["O" .. GRAVE] = "Ò", ["o" .. GRAVE] = "ò",
    ["O" .. ACUTE] = "Ó", ["o" .. ACUTE] = "ó",
    ["O" .. CIRCUMFLEX] = "Ô", ["o" .. CIRCUMFLEX] = "ô",
    ["O" .. TILDE] = "Õ", ["o" .. TILDE] = "õ",
    ["O" .. DIAERESIS] = "Ö", ["o" .. DIAERESIS] = "ö",
    ["U" .. GRAVE] = "Ù", ["u" .. GRAVE] = "ù",
    ["U" .. ACUTE] = "Ú", ["u" .. ACUTE] = "ú",
    ["U" .. CIRCUMFLEX] = "Û", ["u" .. CIRCUMFLEX] = "û",
    ["U" .. DIAERESIS] = "Ü", ["u" .. DIAERESIS] = "ü",
    ["C" .. CEDILLA] = "Ç", ["c" .. CEDILLA] = "ç",
    ["N" .. TILDE] = "Ñ", ["n" .. TILDE] = "ñ",
}

-- Keep annotation matching independent from KOReader's native utf8proc FFI.
-- A native FFI fault cannot be caught by Lua pcall and can terminate the child
-- process without a traceback. For the normalization fallback needed by the
-- matcher we only compose the Latin base+combining sequences that we explicitly
-- support; exact matching remains the first and preferred stage.
local function normalizeNFC(value)
    return LATIN_COMPOSE[value] or value
end

local function utf8Encode(codepoint)
    if codepoint < 0 or codepoint > 0x10FFFF
        or (codepoint >= 0xD800 and codepoint <= 0xDFFF) then
        return "�"
    elseif codepoint < 0x80 then
        return string.char(codepoint)
    elseif codepoint < 0x800 then
        return string.char(
            0xC0 + math.floor(codepoint / 0x40),
            0x80 + (codepoint % 0x40)
        )
    elseif codepoint < 0x10000 then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    end
    return string.char(
        0xF0 + math.floor(codepoint / 0x40000),
        0x80 + (math.floor(codepoint / 0x1000) % 0x40),
        0x80 + (math.floor(codepoint / 0x40) % 0x40),
        0x80 + (codepoint % 0x40)
    )
end

local function readUtf8(text, index)
    local b1 = text:byte(index)
    if not b1 then return nil end
    if b1 < 0x80 then
        return text:sub(index, index), b1, 1
    end

    local b2 = text:byte(index + 1)
    if b1 >= 0xC2 and b1 <= 0xDF and b2 and b2 >= 0x80 and b2 <= 0xBF then
        local cp = (b1 - 0xC0) * 0x40 + (b2 - 0x80)
        return text:sub(index, index + 1), cp, 2
    end

    local b3 = text:byte(index + 2)
    if b1 >= 0xE0 and b1 <= 0xEF
        and b2 and b2 >= 0x80 and b2 <= 0xBF
        and b3 and b3 >= 0x80 and b3 <= 0xBF then
        local cp = (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80)
        return text:sub(index, index + 2), cp, 3
    end

    local b4 = text:byte(index + 3)
    if b1 >= 0xF0 and b1 <= 0xF4
        and b2 and b2 >= 0x80 and b2 <= 0xBF
        and b3 and b3 >= 0x80 and b3 <= 0xBF
        and b4 and b4 >= 0x80 and b4 <= 0xBF then
        local cp = (b1 - 0xF0) * 0x40000
            + (b2 - 0x80) * 0x1000
            + (b3 - 0x80) * 0x40
            + (b4 - 0x80)
        return text:sub(index, index + 3), cp, 4
    end

    return text:sub(index, index), b1, 1
end

local function isCombining(codepoint)
    return (codepoint >= 0x0300 and codepoint <= 0x036F)
        or (codepoint >= 0x1AB0 and codepoint <= 0x1AFF)
        or (codepoint >= 0x1DC0 and codepoint <= 0x1DFF)
        or (codepoint >= 0x20D0 and codepoint <= 0x20FF)
        or (codepoint >= 0xFE20 and codepoint <= 0xFE2F)
end

local function isWhitespace(codepoint)
    return codepoint == 0x09 or codepoint == 0x0A or codepoint == 0x0B
        or codepoint == 0x0C or codepoint == 0x0D or codepoint == 0x20
        or codepoint == 0x85 or codepoint == 0xA0
        or (codepoint >= 0x2000 and codepoint <= 0x200A)
        or codepoint == 0x2028 or codepoint == 0x2029
        or codepoint == 0x202F or codepoint == 0x205F
        or codepoint == 0x3000
end

local function decodeEntity(body)
    local named = ENTITY_MAP[body:lower()]
    if named then return named end

    local decimal = body:match("^#(%d+)$")
    if decimal then
        local cp = tonumber(decimal)
        if cp then return utf8Encode(cp) end
    end

    local hex = body:match("^#[xX]([0-9A-Fa-f]+)$")
    if hex then
        local cp = tonumber(hex, 16)
        if cp then return utf8Encode(cp) end
    end
    return nil
end

local function findTagEnd(html, start_index)
    local quote
    for i = start_index + 1, #html do
        local ch = html:sub(i, i)
        if quote then
            if ch == quote then quote = nil end
        elseif ch == '"' or ch == "'" then
            quote = ch
        elseif ch == ">" then
            return i
        end
    end
    return nil
end

local function appendBoundary(out)
    out[#out + 1] = "\n"
end

function TextMatch.visibleText(html)
    if type(html) ~= "string" then return "" end

    local out = {}
    local lower = html:lower()
    local i, n = 1, #html
    while i <= n do
        if html:sub(i, i + 3) == "<!--" then
            local finish = html:find("-->", i + 4, true)
            i = finish and (finish + 3) or (n + 1)
        elseif html:sub(i, i) == "<" then
            local tag_end = findTagEnd(html, i)
            if not tag_end then
                out[#out + 1] = "<"
                i = i + 1
            else
                local raw = html:sub(i + 1, tag_end - 1)
                local tag = raw:match("^%s*/?%s*([%w:_%-]+)")
                tag = tag and tag:lower() or nil
                local closing = raw:match("^%s*/") ~= nil

                if tag and not closing and (tag == "script" or tag == "style") then
                    local close_start = lower:find("</" .. tag, tag_end + 1, true)
                    if close_start then
                        local close_end = findTagEnd(html, close_start)
                        i = close_end and (close_end + 1) or (n + 1)
                    else
                        i = n + 1
                    end
                    appendBoundary(out)
                else
                    if tag == "br" or (tag and BLOCK_TAGS[tag]) then
                        appendBoundary(out)
                    end
                    i = tag_end + 1
                end
            end
        elseif html:sub(i, i) == "&" then
            local semi = html:find(";", i + 1, true)
            if semi and semi - i <= 32 then
                local decoded = decodeEntity(html:sub(i + 1, semi - 1))
                if decoded then
                    out[#out + 1] = decoded
                    i = semi + 1
                else
                    out[#out + 1] = "&"
                    i = i + 1
                end
            else
                out[#out + 1] = "&"
                i = i + 1
            end
        else
            -- Ordinary text is overwhelmingly the common case. Append one
            -- contiguous chunk instead of one Lua string/table slot per byte.
            local next_special = html:find("[<&]", i)
            if next_special then
                if next_special > i then
                    out[#out + 1] = html:sub(i, next_special - 1)
                end
                i = next_special
            else
                out[#out + 1] = html:sub(i)
                i = n + 1
            end
        end
    end

    return table.concat(out)
end

local function normalizedWithMap(source, options, build_map)
    options = options or {}
    local parts = {}
    local map = build_map and {} or nil
    local normalized_length = 0
    local i, n = 1, #source

    local function emit(value, source_start, source_end)
        if value == "" then return end
        parts[#parts + 1] = value
        local start_index = normalized_length + 1
        normalized_length = normalized_length + #value
        if map then
            map[#map + 1] = {
                normalized_start = start_index,
                normalized_end = normalized_length,
                source_start = source_start,
                source_end = source_end,
            }
        end
    end

    while i <= n do
        local unit, cp, len = readUtf8(source, i)
        if not unit then break end

        if options.remove_soft_hyphen and unit == SOFT_HYPHEN then
            i = i + len
        elseif options.collapse_whitespace and isWhitespace(cp) then
            local source_start = i
            local source_end = i + len - 1
            i = i + len
            while i <= n do
                local next_unit, next_cp, next_len = readUtf8(source, i)
                if not next_unit or not isWhitespace(next_cp) then break end
                source_end = i + next_len - 1
                i = i + next_len
            end
            emit(" ", source_start, source_end)
        else
            local source_start = i
            local source_end = i + len - 1
            i = i + len

            if options.nfc then
                while i <= n do
                    local next_unit, next_cp, next_len = readUtf8(source, i)
                    if not next_unit or not isCombining(next_cp) then break end
                    source_end = i + next_len - 1
                    i = i + next_len
                end
            end

            local value = source:sub(source_start, source_end)
            if options.nfc then value = normalizeNFC(value) end
            if options.punctuation then value = PUNCT_EQUIV[value] or value end
            emit(value, source_start, source_end)
        end
    end

    return table.concat(parts), map
end

local function sourceSpan(map, normalized_start, normalized_end)
    local source_start, source_end
    for _, item in ipairs(map) do
        if not source_start
            and normalized_start >= item.normalized_start
            and normalized_start <= item.normalized_end then
            source_start = item.source_start
        end
        if normalized_end >= item.normalized_start
            and normalized_end <= item.normalized_end then
            source_end = item.source_end
            break
        end
    end
    return source_start, source_end
end

local function sourceSpanForNormalizedRange(source, options, normalized_start, normalized_end)
    options = options or {}
    local normalized_length = 0
    local source_start, source_end
    local i, n = 1, #source

    local function consume(value, unit_start, unit_end)
        if value == "" then return false end
        local unit_normalized_start = normalized_length + 1
        normalized_length = normalized_length + #value
        local unit_normalized_end = normalized_length

        if not source_start
            and normalized_start >= unit_normalized_start
            and normalized_start <= unit_normalized_end then
            source_start = unit_start
        end
        if normalized_end >= unit_normalized_start
            and normalized_end <= unit_normalized_end then
            source_end = unit_end
            return true
        end
        return false
    end

    while i <= n do
        local unit, cp, len = readUtf8(source, i)
        if not unit then break end

        if options.remove_soft_hyphen and unit == SOFT_HYPHEN then
            i = i + len
        elseif options.collapse_whitespace and isWhitespace(cp) then
            local unit_start = i
            local unit_end = i + len - 1
            i = i + len
            while i <= n do
                local next_unit, next_cp, next_len = readUtf8(source, i)
                if not next_unit or not isWhitespace(next_cp) then break end
                unit_end = i + next_len - 1
                i = i + next_len
            end
            if consume(" ", unit_start, unit_end) then break end
        else
            local unit_start = i
            local unit_end = i + len - 1
            i = i + len

            if options.nfc then
                while i <= n do
                    local next_unit, next_cp, next_len = readUtf8(source, i)
                    if not next_unit or not isCombining(next_cp) then break end
                    unit_end = i + next_len - 1
                    i = i + next_len
                end
            end

            local value = source:sub(unit_start, unit_end)
            if options.nfc then value = normalizeNFC(value) end
            if options.punctuation then value = PUNCT_EQUIV[value] or value end
            if consume(value, unit_start, unit_end) then break end
        end
    end

    return source_start, source_end
end

local function uniqueLiteral(haystack, needle)
    local first = haystack:find(needle, 1, true)
    if not first then return nil, nil, "missing" end
    local second = haystack:find(needle, first + 1, true)
    if second then return nil, nil, "ambiguous" end
    return first, first + #needle - 1, "unique"
end

local function mappedStage(remote_visible, local_text, options, mode)
    -- Most stages are rejected before we ever need normalized->source offsets.
    -- Avoid allocating one Lua mapping table per UTF-8 unit on those paths.
    local normalized_remote = normalizedWithMap(remote_visible, options, false)
    local normalized_local = normalizedWithMap(local_text, options, false)
    if normalized_local == "" then return nil, "missing" end

    local first, last, state = uniqueLiteral(normalized_remote, normalized_local)
    if state ~= "unique" then return nil, state end

    -- Recover only the two source offsets we need with a second linear
    -- pass; do not allocate a mapping table per UTF-8 unit.
    local source_start, source_end = sourceSpanForNormalizedRange(
        remote_visible,
        options,
        first,
        last
    )
    if not source_start or not source_end then return nil, "missing" end

    return remote_visible:sub(source_start, source_end), {
        mode = mode,
        normalized_text = normalized_local,
    }
end

local function ambiguousError(message)
    return nil, {
        kind = "ambiguous",
        retryable = false,
        message = message or "Highlight text has multiple safe Reader matches.",
    }
end

function TextMatch.findExactSubstring(remote_content, local_text, options)
    options = options or {}
    local on_stage = options.on_stage
    local function stage(name)
        if type(on_stage) == "function" then on_stage(name) end
    end

    stage("validate")
    if type(remote_content) ~= "string" or remote_content == "" then
        return nil, { kind = "content", retryable = false, message = "Reader content is unavailable." }
    end
    if type(local_text) ~= "string" or local_text == "" then
        return nil, { kind = "text", retryable = false, message = "Local highlight text is empty." }
    end

    stage("visible_text")
    local remote_visible = TextMatch.visibleText(remote_content)
    if remote_visible == "" then
        return nil, { kind = "content", retryable = false, message = "Reader visible text is unavailable." }
    end

    stage("exact")
    local first, last, exact_state = uniqueLiteral(remote_visible, local_text)
    if exact_state == "unique" then
        return remote_visible:sub(first, last), { mode = "exact" }
    elseif exact_state == "ambiguous" then
        return ambiguousError("Highlight text occurs more than once in Reader visible text.")
    end

    local stages = {
        {
            mode = "unicode",
            options = { nfc = true },
            ambiguous = "Unicode-normalized highlight text has multiple Reader matches.",
        },
        {
            mode = "whitespace",
            options = { nfc = true, collapse_whitespace = true, remove_soft_hyphen = true },
            ambiguous = "Whitespace-normalized highlight text has multiple Reader matches.",
        },
        {
            mode = "punctuation",
            options = {
                nfc = true,
                collapse_whitespace = true,
                remove_soft_hyphen = true,
                punctuation = true,
            },
            ambiguous = "Punctuation-normalized highlight text has multiple Reader matches.",
        },
    }

    for _, candidate in ipairs(stages) do
        stage(candidate.mode)
        local result, info_or_state = mappedStage(
            remote_visible,
            local_text,
            candidate.options,
            candidate.mode
        )
        if result then return result, info_or_state end
        if info_or_state == "ambiguous" then
            return ambiguousError(candidate.ambiguous)
        end
    end

    return nil, {
        kind = "unmatched",
        retryable = false,
        message = "Highlight could not be matched safely to Reader visible text.",
    }
end

function TextMatch.canonicalPlainText(value)
    if type(value) ~= "string" then return "" end
    return normalizedWithMap(value, {
        nfc = true,
        collapse_whitespace = true,
        remove_soft_hyphen = true,
        punctuation = true,
    }, false)
end

function TextMatch.equivalentPlainText(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    if a == b then return true end
    return TextMatch.canonicalPlainText(a)
        == TextMatch.canonicalPlainText(b)
end

TextMatch._normalizedWithMap = normalizedWithMap
TextMatch._sourceSpanForNormalizedRange = sourceSpanForNormalizedRange
TextMatch._normalizeNFC = normalizeNFC

return TextMatch
