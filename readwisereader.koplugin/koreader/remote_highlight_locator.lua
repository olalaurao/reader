-- SPDX-License-Identifier: AGPL-3.0-only

local Locator = {}

function Locator.findUnique(reader_ui, text)
    if not reader_ui or not reader_ui.document or type(text) ~= "string" or text == "" then
        return nil, "invalid"
    end

    local ok, matches = pcall(
        reader_ui.document.findAllText,
        reader_ui.document,
        text,
        false,
        0,
        3,
        false,
        0
    )
    if not ok then return nil, "error" end
    if type(matches) ~= "table" or #matches == 0 then return nil, "missing" end
    if #matches > 1 then return nil, "ambiguous" end

    local match = matches[1]
    if type(match.start) ~= "string" or type(match["end"]) ~= "string" then
        return nil, "invalid_locator"
    end

    local text_ok, local_text = pcall(
        reader_ui.document.getTextFromXPointers,
        reader_ui.document,
        match.start,
        match["end"]
    )
    if not text_ok or type(local_text) ~= "string" or local_text == "" then
        return nil, "invalid_locator"
    end
    if local_text ~= text then return nil, "text_diff" end

    return {
        pos0 = match.start,
        pos1 = match["end"],
        text = local_text,
    }, "unique"
end

return Locator
