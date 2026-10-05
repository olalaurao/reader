-- SPDX-License-Identifier: AGPL-3.0-only

local Upload = require("sync/annotation_upload")
local Identity = require("sync/annotation_identity")

return function()
    local captured
    local fake_reader = {
        createHighlight = function(_, parent_id, content, note, tags, marker)
            captured = { parent_id=parent_id, content=content, note=note, tags=tags, marker=marker }
            return { id="remote-1" }
        end,
    }
    local upload = Upload:new{
        documents = {}, annotations = {}, adapter = {}, reader = fake_reader,
        queue = { db = {}, prepare = function(_, item) return item end },
        annotation_metadata = {
            getById = function(_, id)
                assert(id == "ann-1")
                return { pending_tags = { "kindle", "topic" } }
            end,
        },
        hasher = { sha256 = function() return "hash" end },
    }
    local created = assert(upload.reader:createHighlight(
        "doc-1", "selected", "note", nil, Identity.markerFor("ann-1")
    ))
    assert(created.id == "remote-1")
    assert(captured.parent_id == "doc-1")
    assert(captured.note == "note")
    assert(#captured.tags == 2)
    assert(captured.tags[1] == "kindle" and captured.tags[2] == "topic")
end
