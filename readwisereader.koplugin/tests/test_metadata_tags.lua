-- SPDX-License-Identifier: AGPL-3.0-only

local Tags = require("metadata/tags")

local function joined(values) return table.concat(values, "|") end

return function()
    assert(joined(Tags.parse(" beta, alpha\nalpha , gamma ")) == "alpha|beta|gamma")
    assert(Tags.equal({ "b", "a" }, { "a", "b", "a" }))
    local add, remove = Tags.diff({ "a", "b" }, { "b", "c" })
    assert(joined(add) == "c")
    assert(joined(remove) == "a")
    assert(joined(Tags.apply({ "a", "remote" }, { "b" }, { "a" })) == "b|remote")
end
