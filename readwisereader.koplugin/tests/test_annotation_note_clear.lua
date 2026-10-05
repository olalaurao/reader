-- SPDX-License-Identifier: AGPL-3.0-only

local Mutations = require("sync/annotation_mutations")

return function()
    local sent
    local mutator = Mutations:new{
        documents = {}, annotations = {}, adapter = {}, readwise = {},
        reader = {
            updateDocument = function(_, id, patch)
                assert(id == "remote-1")
                sent = patch.notes
                return { id = id }
            end,
            getDocument = function()
                return {
                    id="remote-1", parent_id="doc-1", category="highlight",
                    source="reader", notes="",
                }
            end,
        },
        sleep = function() end,
        reader_verify_attempts = 1,
        reader_verify_delay = 0,
    }
    local report = {
        reader_v3_note_repairs=0, reader_note_verification_reads=0,
        legacy_identity_accepted=0, durable_link_identity_accepted=0,
    }
    local repaired, err = mutator:_repairReaderNote(
        { reader_id="doc-1" },
        { note=nil },
        { reader_highlight_document_id="remote-1", local_annotation_id="ann-1" },
        report
    )
    assert(repaired and not err)
    assert(sent == "")
    assert(report.reader_v3_note_repairs == 1)
end
