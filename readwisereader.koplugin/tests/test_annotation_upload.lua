-- SPDX-License-Identifier: AGPL-3.0-only

local Upload = require("sync/annotation_upload")

return function()
    local linked = false
    local row = {
        local_annotation_id = "ann-1",
        reader_document_id = "doc-1",
        sync_state = "local_only",
        created_remote = false,
    }
    local annotations = {
        getById = function(_, id) if id == "ann-1" then return row end end,
        setReaderRemoteLink = function(_, id, remote_id, synced)
            assert(id == "ann-1")
            assert(remote_id == "remote-hl-1")
            assert(synced.note == "ver [[Foucault]]\n#pesquisar")
            linked = true
            row.created_remote = true
            row.sync_state = "synced"
        end,
    }
    local reader = {
        getDocument = function()
            return { html_content = "<p>Before Selected text After</p>" }
        end,
        createHighlight = function(_, parent, content, note)
            assert(parent == "doc-1")
            assert(content == "Selected text")
            assert(note == "ver [[Foucault]]\n#pesquisar")
            return { id = "remote-hl-1" }
        end,
    }
    local adapter = {
        scan = function()
            return {
                authoritative = true,
                annotations = {{
                    local_annotation_id = "ann-1",
                    text = "Selected text",
                    note = "ver [[Foucault]]\n#pesquisar",
                    text_hash = "th",
                    note_hash = "nh",
                }},
            }
        end,
    }
    local uploader = Upload:new{
        documents = { getByLocalPath = function() return {
            reader_id = "doc-1", local_path = "/Readwise/a.html",
            is_managed = true, is_local_present = true,
        } end },
        annotations = annotations,
        adapter = adapter,
        reader = reader,
        hasher = { sha256 = function(v) return v end },
        file_exists = function() return true end,
    }

    local result = assert(uploader:uploadOne("/Readwise/a.html"))
    assert(result.uploaded == 1)
    assert(result.match_mode == "exact")
    assert(linked == true)

    local second = assert(uploader:uploadOne("/Readwise/a.html"))
    assert(second.uploaded == 0)
    assert(second.status == "nothing_to_upload")
end
