-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubs(run)
    local names = {
        "ui/pdf_highlight_import",
        "ui/widget/infomessage",
        "ui/network/manager",
        "ui/trapper",
        "ui/uimanager",
        "sync/remote_highlight_import_worker",
        "koreader/paging_remote_highlight_locator",
        "gettext",
    }
    local loaded, preload = {}, {}
    local shown = {}

    for _, name in ipairs(names) do
        loaded[name] = package.loaded[name]
        preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    package.preload["gettext"] = function()
        return function(value) return value end
    end
    package.preload["ui/widget/infomessage"] = function()
        return { new = function(_, value) return value end }
    end
    package.preload["ui/network/manager"] = function()
        return { isOnline = function() return true end }
    end
    package.preload["ui/uimanager"] = function()
        return {
            show = function(_, widget)
                shown[#shown + 1] = widget
            end,
        }
    end
    package.preload["ui/trapper"] = function()
        return {
            wrap = function(_, fn) fn() end,
            dismissableRunInSubprocess = function(_, fn)
                local a, b = fn()
                return true, a, b
            end,
        }
    end
    package.preload["sync/remote_highlight_import_worker"] =
        function() return {} end
    package.preload["koreader/paging_remote_highlight_locator"] = function()
        return {
            findUnique = function(_, text)
                if text == "Reader partial" then
                    return {
                        page = 2,
                        pos0 = {
                            page = 2, rotation = 0, zoom = 1,
                            x = 10, y = 20,
                        },
                        pos1 = {
                            page = 2, rotation = 0, zoom = 1,
                            x = 80, y = 20,
                        },
                        pboxes = {
                            { x = 1, y = 2, w = 30, h = 10 },
                            { x = 40, y = 2, w = 50, h = 10 },
                        },
                        text = text,
                        matched_text = "Whole Reader partial word",
                    }, "unique_boundary"
                elseif text == "Second safe" then
                    return {
                        page = 3,
                        pos0 = { page = 3, x = 10, y = 10 },
                        pos1 = { page = 3, x = 40, y = 10 },
                        pboxes = {
                            { x = 5, y = 5, w = 40, h = 10 },
                        },
                        text = text,
                        matched_text = "Second safe",
                    }, "unique_exact"
                elseif text == "Repeated" then
                    return nil, "ambiguous"
                end
                return nil, "missing"
            end,
        }
    end

    local ok, failure = pcall(function()
        local UI = require("ui/pdf_highlight_import")
        run(UI, shown)
    end)

    for _, name in ipairs(names) do
        package.loaded[name] = loaded[name]
        package.preload[name] = preload[name]
    end
    if not ok then error(failure) end
end

local function makeReaderUI()
    local annotations = {}
    local save_calls, delete_calls, settings_calls = 0, 0, 0
    local reader_ui = {
        paging = {},
        document = { is_pdf = true },
        annotation = { annotations = annotations },
        highlight = {
            highlight_write_into_pdf = true,
        },
    }

    reader_ui.highlight.saveHighlight = function(self)
        assert(self.highlight_write_into_pdf == false,
            "PDF embedding must be disabled during saveHighlight")
        save_calls = save_calls + 1
        local selected = assert(self.selected_text)
        local item = {
            local_annotation_id = "local-" .. tostring(save_calls),
            page = selected.pos0.page,
            pos0 = selected.pos0,
            pos1 = selected.pos1,
            pboxes = selected.pboxes,
            text = selected.text,
            note = selected.note,
            datetime = "2026-09-25 12:00:00",
            drawer = "lighten",
        }
        annotations[#annotations + 1] = item
        return #annotations
    end

    reader_ui.highlight.deleteHighlight = function(self, index)
        assert(self.highlight_write_into_pdf == false,
            "PDF embedding must be disabled during rollback delete")
        delete_calls = delete_calls + 1
        table.remove(annotations, index)
    end

    reader_ui.saveSettings = function()
        assert(reader_ui.highlight.highlight_write_into_pdf == true,
            "user PDF embedding preference must be restored before saveSettings")
        settings_calls = settings_calls + 1
    end

    return reader_ui, annotations, function()
        return save_calls, delete_calls, settings_calls
    end
end

local function makeImporter(options)
    options = options or {}
    local linked = options.linked or {}
    local link_calls = 0
    return {
        api = {
            getDocument = function(_, path)
                assert(path == "/books/book.pdf")
                return {
                    reader_id = "pdf-parent",
                    local_path = path,
                    local_format = "pdf",
                    is_local_present = true,
                    is_managed = true,
                }
            end,
            isRemoteLinked = function(_, id)
                return linked[id] and {
                    local_annotation_id = linked[id],
                    reader_highlight_document_id = id,
                } or nil
            end,
            normalizeLocal = function(_, path, local_item)
                assert(path == "/books/book.pdf")
                return {
                    local_annotation_id = local_item.local_annotation_id,
                    text = local_item.text,
                    note = local_item.note,
                }
            end,
            linkPersisted = function(_, path, remote, local_item)
                assert(path == "/books/book.pdf")
                link_calls = link_calls + 1
                if options.link_failure then
                    return nil, { kind = "db" }
                end
                if options.on_link then
                    options.on_link(remote, local_item)
                end
                linked[remote.id] = local_item.local_annotation_id
                return {
                    status = "linked",
                    local_annotation_id = local_item.local_annotation_id,
                }
            end,
        },
        linkCalls = function() return link_calls end,
        linked = linked,
    }
end

local function remoteReport()
    return {
        reader_document_id = "pdf-parent",
        local_format = "pdf",
        parent_highlight_records = 2,
        remote_highlights = {
            {
                id = "remote-note",
                parent_id = "pdf-parent",
                content = "Reader partial",
                notes = "Reader note",
                note_present = true,
            },
            {
                id = "remote-second",
                parent_id = "pdf-parent",
                content = "Second safe",
                note_present = false,
            },
        },
    }
end

return function()
    -- Successful boundary import: one item only, full PDF-word text, note
    -- preserved, PDF embedding preference restored, file digest unchanged.
    withStubs(function(UI, shown)
        local reader_ui, annotations, calls = makeReaderUI()
        local importer = makeImporter{
            on_link = function(remote, local_item)
                assert(remote.id == "remote-note")
                assert(local_item.text == "Whole Reader partial word")
                assert(local_item.note == "Reader note")
                assert(#local_item.pboxes == 2)
            end,
        }
        local digest_calls = 0
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = importer.api,
            get_current_path = function() return "/books/book.pdf" end,
            get_reader_ui = function() return reader_ui end,
            worker = { run = function() return remoteReport() end },
            file_digest = function(path)
                assert(path == "/books/book.pdf")
                digest_calls = digest_calls + 1
                return "same-digest"
            end,
        }

        ui:run()

        assert(#annotations == 1)
        assert(annotations[1].text == "Whole Reader partial word")
        assert(annotations[1].note == "Reader note")
        assert(importer.linkCalls() == 1)
        assert(importer.linked["remote-note"] == "local-1")
        assert(reader_ui.highlight.highlight_write_into_pdf == true)
        local save_calls, delete_calls, settings_calls = calls()
        assert(save_calls == 1)
        assert(delete_calls == 0)
        assert(settings_calls == 1)
        assert(digest_calls == 2)

        local text = shown[#shown].text
        assert(text:find("Imported local PDF highlights: 1", 1, true))
        assert(text:find("Imported Reader note: yes", 1, true))
        assert(text:find("Locator class: unique_boundary", 1, true))
        assert(text:find("PDF file digest unchanged: yes", 1, true))
        assert(text:find("PDF embed preference restored: yes", 1, true))
        assert(text:find("Reader writes from import: none", 1, true))
    end)

    -- Link failure rolls back the sidecar item with embedding still disabled.
    withStubs(function(UI, shown)
        local reader_ui, annotations, calls = makeReaderUI()
        local importer = makeImporter{ link_failure = true }
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = importer.api,
            get_current_path = function() return "/books/book.pdf" end,
            get_reader_ui = function() return reader_ui end,
            worker = { run = function() return remoteReport() end },
            file_digest = function() return "same-digest" end,
        }

        ui:run()

        assert(#annotations == 0)
        assert(reader_ui.highlight.highlight_write_into_pdf == true)
        local save_calls, delete_calls, settings_calls = calls()
        assert(save_calls == 1)
        assert(delete_calls == 1)
        assert(settings_calls == 2)
        assert(importer.linkCalls() == 1)
        assert(shown[#shown].text:find("rolled back", 1, true))
    end)

    -- Rollback finds the created annotation by table reference, not by the
    -- original insertion index. Simulate another annotation being inserted
    -- ahead of it before the durable link returns a failure.
    withStubs(function(UI, shown)
        local reader_ui, annotations, calls = makeReaderUI()
        local importer = makeImporter{
            on_link = function()
                table.insert(annotations, 1, {
                    local_annotation_id = "concurrent-item",
                    page = 1,
                    text = "Other",
                    drawer = "lighten",
                })
                error("synthetic link failure after index shift")
            end,
        }
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = importer.api,
            get_current_path = function() return "/books/book.pdf" end,
            get_reader_ui = function() return reader_ui end,
            worker = { run = function() return remoteReport() end },
            file_digest = function() return "same-digest" end,
        }

        ui:run()

        assert(#annotations == 1)
        assert(annotations[1].local_annotation_id == "concurrent-item",
            "rollback must remove the imported item, not a shifted neighbor")
        local save_calls, delete_calls, settings_calls = calls()
        assert(save_calls == 1)
        assert(delete_calls == 1)
        assert(settings_calls == 2)
        assert(shown[#shown].text:find("rolled back", 1, true))
    end)

    -- A changed PDF digest is a hard stop before durable Reader linking.
    withStubs(function(UI, shown)
        local reader_ui, annotations, calls = makeReaderUI()
        local importer = makeImporter{}
        local digest_calls = 0
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = importer.api,
            get_current_path = function() return "/books/book.pdf" end,
            get_reader_ui = function() return reader_ui end,
            worker = { run = function() return remoteReport() end },
            file_digest = function()
                digest_calls = digest_calls + 1
                return digest_calls == 1 and "before" or "after"
            end,
        }

        ui:run()

        assert(#annotations == 0)
        assert(importer.linkCalls() == 0)
        assert(reader_ui.highlight.highlight_write_into_pdf == true)
        local save_calls, delete_calls, settings_calls = calls()
        assert(save_calls == 1)
        assert(delete_calls == 1)
        assert(settings_calls == 2)
        assert(shown[#shown].text:find(
            "PDF file bytes changed unexpectedly", 1, true
        ))
    end)

    -- Native pboxes, not zoom/rotation context, define an existing PDF
    -- collision. The colliding Reader child is skipped and a later safe child
    -- may be imported without stacking duplicate geometry.
    withStubs(function(UI, shown)
        local reader_ui, annotations = makeReaderUI()
        annotations[1] = {
            local_annotation_id = "existing-geometry",
            page = 2,
            pos0 = {
                page = 2, rotation = 3, zoom = 9,
                x = 999, y = 999,
            },
            pos1 = {
                page = 2, rotation = 3, zoom = 9,
                x = 1000, y = 999,
            },
            pboxes = {
                { x = 1, y = 2, w = 30, h = 10 },
                { x = 40, y = 2, w = 50, h = 10 },
            },
            text = "Whole Reader partial word",
            datetime = "2026-09-24 12:00:00",
            drawer = "lighten",
        }

        local importer = makeImporter{}
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = importer.api,
            get_current_path = function() return "/books/book.pdf" end,
            get_reader_ui = function() return reader_ui end,
            worker = { run = function() return remoteReport() end },
            file_digest = function() return "same-digest" end,
        }

        ui:run()

        assert(#annotations == 2)
        assert(annotations[1].local_annotation_id == "existing-geometry")
        assert(annotations[2].text == "Second safe")
        assert(importer.linkCalls() == 1)
        local text = shown[#shown].text
        assert(text:find("Local position collisions skipped: 1", 1, true))
        assert(text:find("Imported local PDF highlights: 1", 1, true))
    end)

    -- Already-linked first candidate is skipped and exactly one later safe
    -- candidate is imported; the action never imports a batch.
    withStubs(function(UI, shown)
        local reader_ui, annotations = makeReaderUI()
        local importer = makeImporter{
            linked = { ["remote-note"] = "existing-local" },
        }
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = importer.api,
            get_current_path = function() return "/books/book.pdf" end,
            get_reader_ui = function() return reader_ui end,
            worker = { run = function() return remoteReport() end },
            file_digest = function() return "same-digest" end,
        }

        ui:run()

        assert(#annotations == 1)
        assert(annotations[1].text == "Second safe")
        assert(importer.linkCalls() == 1)
        assert(importer.linked["remote-second"] == "local-1")
        local text = shown[#shown].text
        assert(text:find("Already-linked Reader highlights skipped: 1", 1, true))
        assert(text:find("Imported local PDF highlights: 1", 1, true))
    end)

    -- Normal Sync pre-reconciliation remains deliberately one-create-per-run.
    -- If another unlinked Reader child remains, outbound creates for the whole
    -- current PDF are withheld until a later pass examines it.
    withStubs(function(UI)
        local reader_ui, annotations = makeReaderUI()
        local importer = makeImporter{}
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = importer.api,
            get_current_path = function() return "/books/book.pdf" end,
            get_reader_ui = function() return reader_ui end,
            worker = { run = function()
                local report = remoteReport()
                report.cache_mode = "incremental"
                return report
            end },
            file_digest = function() return "same-digest" end,
            max_imports = 1,
            max_locator_attempts = 10,
        }

        local result = ui:prepareForSync("/books/book.pdf")
        assert(result.status == "partial")
        assert(result.imported == 1)
        assert(result.notes_imported == 1)
        assert(result.deferred_by_limit == 1)
        assert(result.suppress_current_document == true)
        assert(#annotations == 1)
        assert(importer.linked["remote-note"] == "local-1")
    end)

    -- After the physically-proven first child is already linked, the next
    -- ordinary Sync may import the next safe PDF child with no blanket hold.
    withStubs(function(UI)
        local reader_ui, annotations = makeReaderUI()
        local importer = makeImporter{
            linked = { ["remote-note"] = "existing-local" },
        }
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = importer.api,
            get_current_path = function() return "/books/book.pdf" end,
            get_reader_ui = function() return reader_ui end,
            worker = { run = function()
                local report = remoteReport()
                report.cache_mode = "incremental"
                return report
            end },
            file_digest = function() return "same-digest" end,
            max_imports = 1,
            max_locator_attempts = 10,
        }

        local result = ui:prepareForSync("/books/book.pdf")
        assert(result.status == "ok")
        assert(result.imported == 1)
        assert(result.linked_skipped == 1)
        assert(result.deferred_by_limit == 0)
        assert(result.suppress_current_document == false)
        assert(#annotations == 1)
        assert(annotations[1].text == "Second safe")
        assert(importer.linked["remote-second"] == "local-1")
    end)

    -- An exact native PDF-position collision with the same note is linked to
    -- the existing sidecar annotation instead of creating stacked geometry.
    withStubs(function(UI)
        local reader_ui, annotations = makeReaderUI()
        annotations[1] = {
            local_annotation_id = "existing-geometry",
            page = 2,
            pos0 = { page = 2, x = 999, y = 999 },
            pos1 = { page = 2, x = 1000, y = 999 },
            pboxes = {
                { x = 1, y = 2, w = 30, h = 10 },
                { x = 40, y = 2, w = 50, h = 10 },
            },
            text = "Whole Reader partial word",
            note = "Reader note",
            datetime = "2026-09-24 12:00:00",
            drawer = "lighten",
        }
        local importer = makeImporter{
            linked = { ["remote-second"] = "already-second" },
        }
        local digest_calls = 0
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = importer.api,
            get_current_path = function() return "/books/book.pdf" end,
            get_reader_ui = function() return reader_ui end,
            worker = { run = function()
                local report = remoteReport()
                report.cache_mode = "incremental"
                return report
            end },
            file_digest = function()
                digest_calls = digest_calls + 1
                return "same-digest"
            end,
        }

        local result = ui:prepareForSync("/books/book.pdf")
        assert(result.status == "ok")
        assert(result.imported == 0)
        assert(result.collisions_linked == 1)
        assert(result.linked_skipped == 1)
        assert(result.suppress_current_document == false)
        assert(importer.linked["remote-note"] == "existing-geometry")
        assert(#annotations == 1)
        assert(digest_calls == 0)
    end)

    -- If the Reader child cannot be located natively in the PDF, no guessing
    -- occurs and all outbound creates for this PDF are held for that run.
    withStubs(function(UI)
        local reader_ui = makeReaderUI()
        local importer = makeImporter{}
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = importer.api,
            get_current_path = function() return "/books/book.pdf" end,
            get_reader_ui = function() return reader_ui end,
            worker = { run = function()
                return {
                    reader_document_id = "pdf-parent",
                    local_format = "pdf",
                    parent_highlight_records = 1,
                    cache_mode = "incremental",
                    remote_highlights = {
                        {
                            id = "remote-ambiguous",
                            parent_id = "pdf-parent",
                            content = "Repeated",
                            note_present = false,
                        },
                    },
                }
            end },
            file_digest = function()
                error("digest must not run for an unresolved locator")
            end,
        }

        local result = ui:prepareForSync("/books/book.pdf")
        assert(result.status == "partial")
        assert(result.imported == 0)
        assert(result.ambiguous == 1)
        assert(result.unresolved_collision_risk == 1)
        assert(result.suppress_current_document == true)
        assert(#result.suppress_outbound_ids == 0)
    end)

end
