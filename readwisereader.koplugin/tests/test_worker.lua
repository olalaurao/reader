-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = require("sync/worker")

return function()
    local source_tags = { "research", "deep work" }
    local metadata = Worker._copyMetadata({
        title = "Title",
        author = "Author",
        summary = "Summary",
        site_name = "Site",
        tags = source_tags,
    })

    assert(metadata.title == "Title")
    assert(metadata.author == "Author")
    assert(metadata.summary == "Summary")
    assert(metadata.site_name == "Site")
    assert(metadata.tags[1] == "research")
    assert(metadata.tags[2] == "deep work")
    assert(metadata.tags ~= source_tags, "worker metadata payload must own its tag array")
end
