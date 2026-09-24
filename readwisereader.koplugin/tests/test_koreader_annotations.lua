-- SPDX-License-Identifier: AGPL-3.0-only

local KOReaderAnnotations = require("koreader/annotations")

local hasher = {
    sha256 = function(value)
        return "H[" .. tostring(value) .. "]"
    end,
}

local function docSettings(data, source_candidate)
    return {
        open = function(_, path)
            return {
                source_candidate = source_candidate,
                readSetting = function(_, key)
                    return data and data[key] or nil
                end,
            }
        end,
    }
end

return function()
    do
        local adapter = KOReaderAnnotations:new{
            doc_settings = docSettings({}, "/book.sdr/metadata.epub.lua"),
            hasher = hasher,
        }
        local base = {
            datetime = "2026-09-23 10:00:00",
            datetime_updated = "2026-09-23 10:01:00",
            drawer = "lighten",
            color = "yellow",
            text = "Selected text",
            note = "Relacionar com [[Foucault]]\n\n#pesquisar 🧠",
            page = "/body/DocFragment[1]/body/p[3]/text().5",
            pos0 = "/body/DocFragment[1]/body/p[3]/text().5",
            pos1 = "/body/DocFragment[1]/body/p[3]/text().18",
            pageno = 3,
            pageref = "iii",
            chapter = "Chapter",
        }
        local first = assert(adapter:normalize("reader-1", base))
        assert(first.identity_quality == "strong")
        assert(first.note == "Relacionar com [[Foucault]]\n\n#pesquisar 🧠")
        assert(first.text == "Selected text")

        local edited = {}
        for key, value in pairs(base) do edited[key] = value end
        edited.text = "Edited selected text"
        edited.note = "Changed note\n[[Biopolítica]]"
        edited.datetime_updated = "2026-09-23 10:02:00"
        local second = assert(adapter:normalize("reader-1", edited))
        assert(second.local_annotation_id == first.local_annotation_id,
            "text/note edits must not change local annotation identity")
        assert(second.locator_fingerprint == first.locator_fingerprint)
        assert(second.text_hash ~= first.text_hash)
        assert(second.note_hash ~= first.note_hash)

        local moved = {}
        for key, value in pairs(base) do moved[key] = value end
        moved.pos1 = "/body/DocFragment[1]/body/p[3]/text().22"
        local third = assert(adapter:normalize("reader-1", moved))
        assert(third.local_annotation_id ~= first.local_annotation_id,
            "locator change must change local annotation identity")

        local recreated = {}
        for key, value in pairs(base) do recreated[key] = value end
        recreated.datetime = "2026-09-23 11:00:00"
        local fourth = assert(adapter:normalize("reader-1", recreated))
        assert(fourth.local_annotation_id ~= first.local_annotation_id,
            "delete/recreate at same locator must remain distinguishable by creation time")

        local no_datetime = {}
        for key, value in pairs(base) do no_datetime[key] = value end
        no_datetime.datetime = nil
        local degraded = assert(adapter:normalize("reader-1", no_datetime))
        assert(degraded.identity_quality == "degraded")
    end

    do
        local pos0a = {}
        pos0a.x, pos0a.y, pos0a.page = 10.5, 20.25, 4
        local pos0b = {}
        pos0b.page, pos0b.y, pos0b.x = 4, 20.25, 10.5
        local a = {
            datetime = "2026-09-23 12:00:00",
            drawer = "underscore",
            text = "PDF text",
            page = 4,
            pos0 = pos0a,
            pos1 = { x = 30, y = 40, page = 4 },
        }
        local b = {
            datetime = a.datetime,
            drawer = a.drawer,
            text = a.text,
            page = a.page,
            pos0 = pos0b,
            pos1 = { page = 4, y = 40, x = 30 },
        }
        local adapter = KOReaderAnnotations:new{
            doc_settings = docSettings({}, "/pdf.sdr/metadata.pdf.lua"),
            hasher = hasher,
        }
        local ia = assert(adapter:normalize("reader-pdf", a))
        local ib = assert(adapter:normalize("reader-pdf", b))
        assert(ia.local_annotation_id == ib.local_annotation_id,
            "PDF locator table key order must not affect identity")
    end

    do
        local annotations = {
            {
                datetime = "2026-09-23 10:00:00",
                drawer = "lighten",
                text = "Older",
                note = nil,
                page = "xp-1",
                pos0 = "xp-1",
                pos1 = "xp-2",
            },
            {
                datetime = "2026-09-23 10:02:00",
                datetime_updated = "2026-09-23 10:03:00",
                drawer = "lighten",
                text = "Newest",
                note = "gate7 [[Foucault]] 🧠",
                page = "xp-3",
                pos0 = "xp-3",
                pos1 = "xp-4",
            },
            {
                datetime = "2026-09-23 10:04:00",
                text = "Page bookmark",
                page = "xp-5",
            },
            {
                datetime = "2026-09-23 10:05:00",
                drawer = "lighten",
                text = nil,
                page = "xp-6",
                pos0 = "xp-6",
                pos1 = "xp-7",
            },
        }
        local adapter = KOReaderAnnotations:new{
            doc_settings = docSettings({ annotations = annotations }, "/book.sdr/metadata.epub.lua"),
            hasher = hasher,
        }
        local result, err = adapter:scan("/book.epub", "reader-1")
        assert(err == nil)
        assert(result.authoritative == true)
        assert(result.status == "ok")
        assert(#result.annotations == 2)
        assert(result.malformed == 1)
        assert(result.annotations[1].text == "Newest")
        assert(result.annotations[1].note == "gate7 [[Foucault]] 🧠")
    end

    do
        local cyclic = {}
        cyclic.self = cyclic
        local annotations = {
            {
                datetime = "2026-09-23 11:00:00",
                drawer = "lighten",
                text = "Malformed locator",
                page = "xp-bad",
                pos0 = "xp-bad",
                pos1 = "xp-bad-2",
                ext = cyclic,
            },
            {
                datetime = "2026-09-23 11:01:00",
                drawer = "lighten",
                text = "Valid after malformed",
                page = "xp-ok",
                pos0 = "xp-ok",
                pos1 = "xp-ok-2",
            },
        }
        local adapter = KOReaderAnnotations:new{
            doc_settings = docSettings({ annotations = annotations }, "/book.sdr/metadata.epub.lua"),
            hasher = hasher,
        }
        local result = assert(adapter:scan("/book.epub", "reader-1"))
        assert(result.authoritative == true)
        assert(#result.annotations == 1)
        assert(result.annotations[1].text == "Valid after malformed")
        assert(result.malformed == 1)
        assert(result.normalize_exceptions == 1,
            "one malformed annotation must not abort the entire sidecar")
    end

    do
        local adapter = KOReaderAnnotations:new{
            doc_settings = docSettings({}, nil),
            hasher = hasher,
        }
        local result = assert(adapter:scan("/missing.epub", "reader-1"))
        assert(result.authoritative == false)
        assert(result.status == "no_sidecar")
    end

    do
        local adapter = KOReaderAnnotations:new{
            doc_settings = docSettings({ progress = 0.5 }, "/book.sdr/metadata.epub.lua"),
            hasher = hasher,
        }
        local result = assert(adapter:scan("/book.epub", "reader-1"))
        assert(result.authoritative == false)
        assert(result.status == "annotations_missing")
    end

    do
        local adapter = KOReaderAnnotations:new{
            doc_settings = docSettings({ annotations = {} }, "/book.sdr/metadata.epub.lua"),
            hasher = hasher,
        }
        local result = assert(adapter:scan("/book.epub", "reader-1"))
        assert(result.authoritative == true)
        assert(#result.annotations == 0)
    end
end
