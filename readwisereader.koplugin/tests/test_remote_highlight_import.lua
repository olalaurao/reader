-- SPDX-License-Identifier: AGPL-3.0-only

local Import = require("sync/remote_highlight_import")

return function()
    do
        local linked_payload
        local annotations = {
            getByReaderRemoteId = function() return nil end,
            linkImported = function(_, payload)
                linked_payload = payload
                return {
                    local_annotation_id = payload.local_annotation_id,
                    reader_highlight_document_id = payload.reader_highlight_document_id,
                    created_remote = true,
                    sync_state = "synced",
                }
            end,
        }
        local importer = Import:new{
            documents = {
                getByLocalPath = function(_, path)
                    assert(path == "/books/book.epub")
                    return {
                        reader_id = "parent-1",
                        local_path = path,
                        local_format = "epub",
                        is_local_present = true,
                        is_managed = true,
                    }
                end,
            },
            annotations = annotations,
            adapter = {
                normalize = function(_, reader_id, item)
                    assert(reader_id == "parent-1")
                    assert(item.text == "Exact passage")
                    return {
                        local_annotation_id = "ko-local-1",
                        locator_fingerprint = "loc-1",
                        datetime = "2026-09-25 00:00:00",
                        text = item.text,
                        note = item.note,
                        text_hash = "text-hash",
                        note_hash = "note-hash",
                    }
                end,
                scan = function(_, path, reader_id)
                    assert(path == "/books/book.epub")
                    assert(reader_id == "parent-1")
                    return {
                        authoritative = true,
                        annotations = {
                            {
                                local_annotation_id = "ko-local-1",
                                locator_fingerprint = "loc-1",
                                datetime = "2026-09-25 00:00:00",
                                text = "Exact passage",
                                note = "Reader note",
                                text_hash = "text-hash",
                                note_hash = "note-hash",
                            },
                        },
                    }
                end,
            },
        }

        local result, err = importer:linkPersisted(
            "/books/book.epub",
            {
                id = "reader-highlight-1",
                parent_id = "parent-1",
                updated_at = "2026-09-25T00:00:01Z",
            },
            { drawer = "lighten", text = "Exact passage", note = "Reader note" }
        )
        assert(err == nil)
        assert(result.status == "linked")
        assert(result.local_annotation_id == "ko-local-1")
        assert(linked_payload.reader_highlight_document_id == "reader-highlight-1")
        assert(linked_payload.reader_document_id == "parent-1")
        assert(linked_payload.text == "Exact passage")
        assert(linked_payload.note == "Reader note")
        assert(linked_payload.remote_updated_marker == "2026-09-25T00:00:01Z")
    end

    do
        local importer = Import:new{
            documents = {
                getByLocalPath = function()
                    return {
                        reader_id = "parent-1",
                        local_path = "/books/book.epub",
                        local_format = "epub",
                        is_local_present = true,
                        is_managed = true,
                    }
                end,
            },
            annotations = {
                getByReaderRemoteId = function(_, id)
                    assert(id == "reader-highlight-1")
                    return {
                        local_annotation_id = "ko-existing",
                        reader_highlight_document_id = id,
                    }
                end,
            },
            adapter = {},
        }
        local result = assert(importer:linkPersisted(
            "/books/book.epub",
            { id = "reader-highlight-1", parent_id = "parent-1" },
            {}
        ))
        assert(result.status == "already_linked")
        assert(result.local_annotation_id == "ko-existing")
    end

    do
        local importer = Import:new{
            documents = {
                getByLocalPath = function()
                    return {
                        reader_id = "parent-1",
                        local_path = "/books/book.epub",
                        local_format = "epub",
                        is_local_present = true,
                        is_managed = true,
                    }
                end,
            },
            annotations = { getByReaderRemoteId = function() return nil end },
            adapter = {},
        }
        local result, err = importer:linkPersisted(
            "/books/book.epub",
            { id = "reader-highlight-1", parent_id = "other-parent" },
            {}
        )
        assert(result == nil)
        assert(err.kind == "parent")
    end
    do
        local importer = Import:new{
            documents = {
                getByLocalPath = function(_, path)
                    assert(path == "/books/book.pdf")
                    return {
                        reader_id = "pdf-parent",
                        local_path = path,
                        local_format = "pdf",
                        is_local_present = true,
                        is_managed = true,
                    }
                end,
            },
            annotations = {},
            adapter = {},
        }
        local document, err = importer:getDocument("/books/book.pdf")
        assert(err == nil)
        assert(document.local_format == "pdf")
        assert(document.reader_id == "pdf-parent")
    end

    do
        local importer = Import:new{
            documents = {
                getByLocalPath = function()
                    return {
                        reader_id = "mobi-parent",
                        local_path = "/books/book.mobi",
                        local_format = "mobi",
                        is_local_present = true,
                        is_managed = true,
                    }
                end,
            },
            annotations = {},
            adapter = {},
        }
        local document, err = importer:getDocument("/books/book.mobi")
        assert(document == nil)
        assert(err.kind == "format")
    end

    do
        local linked_payload
        local importer = Import:new{
            documents = {
                getByLocalPath = function(_, path)
                    assert(path == "/books/book.pdf")
                    return {
                        reader_id = "pdf-parent",
                        local_path = path,
                        local_format = "pdf",
                        is_local_present = true,
                        is_managed = true,
                    }
                end,
            },
            annotations = {
                getByReaderRemoteId = function() return nil end,
                linkImported = function(_, payload)
                    linked_payload = payload
                    return {
                        local_annotation_id = payload.local_annotation_id,
                        reader_highlight_document_id =
                            payload.reader_highlight_document_id,
                        created_remote = true,
                        sync_state = "synced",
                    }
                end,
            },
            adapter = {
                normalize = function(_, reader_id, item)
                    assert(reader_id == "pdf-parent")
                    assert(item.text == "PDF selected text")
                    return {
                        local_annotation_id = "ko-in-memory",
                        locator_fingerprint = "loc-in-memory",
                        datetime = "2026-09-25 12:00:00",
                        text = item.text,
                        note = item.note,
                        text_hash = "pdf-text-hash",
                        note_hash = "pdf-note-hash",
                        page = 2,
                        pboxes = {
                            { x = 10, y = 20, w = 30, h = 10 },
                            { x = 50, y = 20, w = 40, h = 10 },
                        },
                    }
                end,
                scan = function(_, path, reader_id)
                    assert(path == "/books/book.pdf")
                    assert(reader_id == "pdf-parent")
                    return {
                        authoritative = true,
                        annotations = {
                            {
                                local_annotation_id = "ko-sidecar",
                                locator_fingerprint = "loc-sidecar",
                                datetime = "2026-09-25 12:00:00",
                                text = "PDF selected text",
                                note = "PDF note",
                                text_hash = "pdf-text-hash",
                                note_hash = "pdf-note-hash",
                                page = 2,
                                pboxes = {
                                    { x = 10, y = 20, w = 30, h = 10 },
                                    { x = 50, y = 20, w = 40, h = 10 },
                                },
                            },
                        },
                    }
                end,
            },
        }

        local result, err = importer:linkPersisted(
            "/books/book.pdf",
            {
                id = "reader-pdf-highlight",
                parent_id = "pdf-parent",
                updated_at = "2026-09-25T12:00:01Z",
            },
            {
                drawer = "lighten",
                text = "PDF selected text",
                note = "PDF note",
                page = 2,
                pboxes = {
                    { x = 10, y = 20, w = 30, h = 10 },
                    { x = 50, y = 20, w = 40, h = 10 },
                },
            }
        )
        assert(err == nil)
        assert(result.status == "linked")
        assert(result.local_annotation_id == "ko-sidecar",
            "PDF persisted geometry fallback must link the sidecar identity")
        assert(linked_payload.local_annotation_id == "ko-sidecar")
        assert(linked_payload.reader_highlight_document_id
            == "reader-pdf-highlight")
        assert(linked_payload.locator_fingerprint == "loc-sidecar")
    end

    do
        local importer = Import:new{
            documents = {
                getByLocalPath = function()
                    return {
                        reader_id = "pdf-parent",
                        local_path = "/books/book.pdf",
                        local_format = "pdf",
                        is_local_present = true,
                        is_managed = true,
                    }
                end,
            },
            annotations = {
                getByReaderRemoteId = function() return nil end,
                linkImported = function()
                    error("ambiguous PDF sidecar lookup must not link")
                end,
            },
            adapter = {
                normalize = function()
                    return {
                        local_annotation_id = "ko-in-memory",
                        locator_fingerprint = "loc-in-memory",
                        datetime = "2026-09-25 12:00:00",
                        text = "PDF selected text",
                        note = nil,
                        text_hash = "same-text",
                        note_hash = "same-note",
                        page = 2,
                        pboxes = {
                            { x = 1, y = 2, w = 3, h = 4 },
                        },
                    }
                end,
                scan = function()
                    local function item(id)
                        return {
                            local_annotation_id = id,
                            locator_fingerprint = "loc-" .. id,
                            datetime = "2026-09-25 12:00:00",
                            text = "PDF selected text",
                            note = nil,
                            text_hash = "same-text",
                            note_hash = "same-note",
                            page = 2,
                            pboxes = {
                                { x = 1, y = 2, w = 3, h = 4 },
                            },
                        }
                    end
                    return {
                        authoritative = true,
                        annotations = { item("ko-a"), item("ko-b") },
                    }
                end,
            },
        }

        local result, err = importer:linkPersisted(
            "/books/book.pdf",
            { id = "reader-pdf-highlight", parent_id = "pdf-parent" },
            { drawer = "lighten", text = "PDF selected text" }
        )
        assert(result == nil)
        assert(err.kind == "sidecar_ambiguous")
    end

end
