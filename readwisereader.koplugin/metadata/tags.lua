-- SPDX-License-Identifier: AGPL-3.0-only

local Tags = {}

local function trim(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value == "" then return nil end
    return value
end

function Tags.normalize(values)
    local out, seen = {}, {}
    for _, value in ipairs(type(values) == "table" and values or {}) do
        value = trim(value)
        if value and not seen[value] then
            seen[value] = true
            out[#out + 1] = value
        end
    end
    table.sort(out)
    return out
end

function Tags.parse(value)
    if type(value) ~= "string" then return {} end
    local out = {}
    for item in value:gmatch("[^,\n]+") do
        local tag = trim(item)
        if tag then out[#out + 1] = tag end
    end
    return Tags.normalize(out)
end

function Tags.display(values)
    return table.concat(Tags.normalize(values), ", ")
end

function Tags.equal(a, b)
    a, b = Tags.normalize(a), Tags.normalize(b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

function Tags.diff(baseline, desired)
    baseline, desired = Tags.normalize(baseline), Tags.normalize(desired)
    local base_set, desired_set = {}, {}
    for _, tag in ipairs(baseline) do base_set[tag] = true end
    for _, tag in ipairs(desired) do desired_set[tag] = true end
    local add, remove = {}, {}
    for _, tag in ipairs(desired) do
        if not base_set[tag] then add[#add + 1] = tag end
    end
    for _, tag in ipairs(baseline) do
        if not desired_set[tag] then remove[#remove + 1] = tag end
    end
    return add, remove
end

function Tags.apply(current, add, remove)
    local set = {}
    for _, tag in ipairs(Tags.normalize(current)) do set[tag] = true end
    for _, tag in ipairs(Tags.normalize(remove)) do set[tag] = nil end
    for _, tag in ipairs(Tags.normalize(add)) do set[tag] = true end
    local out = {}
    for tag in pairs(set) do out[#out + 1] = tag end
    table.sort(out)
    return out
end

function Tags.encode(values)
    local ok, encoded = pcall(require("json").encode, Tags.normalize(values))
    if not ok or type(encoded) ~= "string" then return "[]" end
    return encoded
end

function Tags.decode(value)
    if type(value) ~= "string" or value == "" then return {} end
    local ok, decoded = pcall(require("json").decode, value)
    if not ok or type(decoded) ~= "table" then return {} end
    return Tags.normalize(decoded)
end

return Tags
