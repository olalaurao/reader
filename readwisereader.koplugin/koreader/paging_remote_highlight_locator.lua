-- SPDX-License-Identifier: AGPL-3.0-only

local Locator = {}

local function validBox(box)
    return type(box) == "table"
        and type(box.x) == "number"
        and type(box.y) == "number"
        and type(box.w) == "number" and box.w > 0
        and type(box.h) == "number" and box.h > 0
end

local function persistedNumber(value)
    if type(value) ~= "number" then return value end
    return tonumber(tostring(value))
end

local function boxCenter(box, page, rotation, zoom)
    return {
        page = persistedNumber(page),
        rotation = persistedNumber(rotation),
        zoom = persistedNumber(zoom),
        x = persistedNumber(box.x + box.w / 2),
        y = persistedNumber(box.y + box.h / 2),
    }
end

local function words(value)
    local out = {}
    if type(value) ~= "string" then return out end
    for word in value:gmatch("%S+") do
        out[#out + 1] = word
    end
    return out
end

local function normalizedWhitespace(value)
    return table.concat(words(value), " ")
end

local function boundaryRelation(reader_text, matched_text)
    local reader_words = words(reader_text)
    local matched_words = words(matched_text)
    if #reader_words == 0 or #reader_words ~= #matched_words then
        return nil
    end

    if normalizedWhitespace(reader_text) == normalizedWhitespace(matched_text) then
        return {
            kind = "exact",
            first_word = matched_words[1],
            last_word = matched_words[#matched_words],
        }
    end

    if #reader_words == 1 then
        local query = reader_words[1]
        local matched = matched_words[1]
        if matched:find(query, 1, true) then
            return {
                kind = "boundary_expanded",
                first_word = matched,
                last_word = matched,
            }
        end
        return nil
    end

    for index = 2, #reader_words - 1 do
        if reader_words[index] ~= matched_words[index] then
            return nil
        end
    end

    local first_query = reader_words[1]
    local first_matched = matched_words[1]
    local last_query = reader_words[#reader_words]
    local last_matched = matched_words[#matched_words]

    local first_ok = #first_query <= #first_matched
        and first_matched:sub(-#first_query) == first_query
    local last_ok = #last_query <= #last_matched
        and last_matched:sub(1, #last_query) == last_query

    if not first_ok or not last_ok then return nil end

    return {
        kind = "boundary_expanded",
        first_word = first_matched,
        last_word = last_matched,
    }
end

local function nativeEvidence(document, pos0, pos1)
    if type(document.getWordFromPosition) ~= "function" then
        return nil, "unsupported"
    end

    local configurable = document.configurable
    local previous_wrap = configurable and configurable.text_wrap or nil
    if configurable then configurable.text_wrap = 0 end

    local endpoint_ok, first_word, last_word = pcall(function()
        return document:getWordFromPosition(pos0),
            document:getWordFromPosition(pos1)
    end)

    local selected
    local roundtrip_status = "unavailable"
    if endpoint_ok and type(document.getTextFromPositions) == "function" then
        local roundtrip_ok, roundtrip_result = pcall(
            document.getTextFromPositions,
            document,
            pos0,
            pos1
        )
        if roundtrip_ok then
            selected = roundtrip_result
            roundtrip_status = "ok"
        else
            roundtrip_status = "error"
        end
    end

    if configurable then configurable.text_wrap = previous_wrap end
    if not endpoint_ok then return nil, "error" end
    if type(first_word) ~= "table" or type(first_word.word) ~= "string"
        or type(last_word) ~= "table" or type(last_word.word) ~= "string" then
        return nil, "invalid_locator"
    end

    return {
        first_word = first_word.word,
        last_word = last_word.word,
        selected = selected,
        roundtrip_status = roundtrip_status,
    }
end

function Locator.findUnique(reader_ui, text)
    if not reader_ui or not reader_ui.document
        or not reader_ui.paging
        or type(text) ~= "string" or text == "" then
        return nil, "invalid"
    end

    local document = reader_ui.document
    if type(document.findAllText) ~= "function" then
        return nil, "unsupported"
    end

    local ok, matches = pcall(
        document.findAllText,
        document,
        text,
        false,
        0,
        3
    )
    if not ok then return nil, "error" end
    if type(matches) ~= "table" or #matches == 0 then
        return nil, "missing"
    end
    if #matches > 1 then return nil, "ambiguous" end

    local match = matches[1]
    if type(match) ~= "table"
        or type(match.start) ~= "number"
        or match.start < 1
        or type(match.boxes) ~= "table"
        or #match.boxes == 0
        or type(match.matched_text) ~= "string"
        or match.matched_text == "" then
        return nil, "invalid_locator"
    end

    for _, box in ipairs(match.boxes) do
        if not validBox(box) then
            return nil, "invalid_locator"
        end
    end

    -- KOReader's paging search intentionally allows the first query word to
    -- match the suffix of a PDF word and the last query word to match the
    -- prefix of a PDF word. It still returns the full word boxes. This is why
    -- a valid Reader selection that starts/ends mid-word can never round-trip
    -- literally through getTextFromPositions().
    local relation = boundaryRelation(text, match.matched_text)
    if not relation then return nil, "search_text_diff" end

    local page = match.start
    local rotation = type(document.getRotation) == "function"
        and document:getRotation() or nil
    local zoom = type(document.getZoom) == "function"
        and document:getZoom() or nil
    local pos0 = boxCenter(match.boxes[1], page, rotation, zoom)
    local pos1 = boxCenter(match.boxes[#match.boxes], page, rotation, zoom)
    local evidence, evidence_err = nativeEvidence(document, pos0, pos1)
    if not evidence then return nil, evidence_err end

    -- Validate geometry by proving the derived native positions land back on
    -- the exact first/last PDF words returned by findAllText(). Full selected
    -- text is diagnostic only because KOPT reconstructs spaces/hyphenation and
    -- full boundary words independently from Reader's exact selected string.
    if evidence.first_word ~= relation.first_word
        or evidence.last_word ~= relation.last_word then
        return nil, "geometry_mismatch"
    end

    local roundtrip_text =
        type(evidence.selected) == "table" and evidence.selected.text or nil
    local roundtrip_matches_search =
        type(roundtrip_text) == "string"
        and normalizedWhitespace(roundtrip_text)
            == normalizedWhitespace(match.matched_text)

    return {
        page = page,
        pos0 = pos0,
        pos1 = pos1,
        pboxes = match.boxes,
        text = text,
        matched_text = match.matched_text,
        boundary_kind = relation.kind,
        first_word = relation.first_word,
        last_word = relation.last_word,
        roundtrip_text = roundtrip_text,
        roundtrip_status = evidence.roundtrip_status,
        roundtrip_matches_search = roundtrip_matches_search,
    }, relation.kind == "exact"
        and "unique_exact" or "unique_boundary"
end

Locator._boxCenter = boxCenter
Locator._persistedNumber = persistedNumber
Locator._boundaryRelation = boundaryRelation
Locator._nativeEvidence = nativeEvidence
Locator._normalizedWhitespace = normalizedWhitespace
Locator._validBox = validBox
Locator._words = words

return Locator
