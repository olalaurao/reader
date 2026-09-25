-- SPDX-License-Identifier: AGPL-3.0-only

local Locator = {}

local function validBox(box)
    return type(box) == "table"
        and type(box.x) == "number"
        and type(box.y) == "number"
        and type(box.w) == "number" and box.w > 0
        and type(box.h) == "number" and box.h > 0
end

local function boxCenter(box, page)
    return {
        page = page,
        x = box.x + math.floor((box.w - 1) / 2),
        y = box.y + math.floor((box.h - 1) / 2),
    }
end

local function nativeText(document, pos0, pos1)
    local configurable = document.configurable
    local previous_wrap = configurable and configurable.text_wrap or nil
    if configurable then configurable.text_wrap = 0 end

    local ok, result = pcall(
        document.getTextFromPositions,
        document,
        pos0,
        pos1
    )

    if configurable then configurable.text_wrap = previous_wrap end
    if not ok then return nil, "error" end
    return result
end

function Locator.findUnique(reader_ui, text)
    if not reader_ui or not reader_ui.document
        or not reader_ui.paging
        or type(text) ~= "string" or text == "" then
        return nil, "invalid"
    end

    local document = reader_ui.document
    if type(document.findAllText) ~= "function"
        or type(document.getTextFromPositions) ~= "function" then
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
        or #match.boxes == 0 then
        return nil, "invalid_locator"
    end

    for _, box in ipairs(match.boxes) do
        if not validBox(box) then
            return nil, "invalid_locator"
        end
    end

    local page = match.start
    local pos0 = boxCenter(match.boxes[1], page)
    local pos1 = boxCenter(match.boxes[#match.boxes], page)
    local selected, selected_err = nativeText(document, pos0, pos1)
    if not selected then return nil, selected_err or "invalid_locator" end
    if type(selected) ~= "table"
        or type(selected.text) ~= "string"
        or selected.text == "" then
        return nil, "invalid_locator"
    end
    if selected.text ~= text then return nil, "text_diff" end

    local pboxes = selected.pboxes
    if type(pboxes) ~= "table" or #pboxes == 0 then
        pboxes = match.boxes
    end

    return {
        page = page,
        pos0 = selected.pos0 or pos0,
        pos1 = selected.pos1 or pos1,
        pboxes = pboxes,
        text = selected.text,
        matched_text = match.matched_text,
    }, "unique"
end

Locator._boxCenter = boxCenter
Locator._nativeText = nativeText
Locator._validBox = validBox

return Locator
