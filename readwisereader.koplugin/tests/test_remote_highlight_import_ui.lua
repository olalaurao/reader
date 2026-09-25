-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubs(run)
    local names = {
        "ui/remote_highlight_import",
        "ui/widget/infomessage",
        "ui/network/manager",
        "ui/trapper",
        "ui/uimanager",
        "sync/remote_highlight_probe_worker",
        "gettext",
    }
    local loaded, preload = {}, {}
    local shown = {}
    for _, name in ipairs(names) do
        loaded[name] = package.loaded[name]
        preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    package.preload["gettext"] = function() return function(v) return v end end
    package.preload["ui/widget/infomessage"] = function()
        return { new = function(_, v) return v end }
    end
    package.preload["ui/network/manager"] = function()
        return { isOnline = function() return true end }
    end
    package.preload["ui/uimanager"] = function()
        return { show = function(_, widget) shown[#shown + 1] = widget end }
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
    package.preload["sync/remote_highlight_probe_worker"] = function() return {} end

    local ok, failure = pcall(function()
        local UI = require("ui/remote_highlight_import")
        run(UI, shown)
    end)

    for _, name in ipairs(names) do
        package.loaded[name] = loaded[name]
        package.preload[name] = preload[name]
    end
    if not ok then error(failure) end
end

local function newSyncMeta()
    local data = {}
    return {
        data = data,
        get = function(_, key) return data[key] end,
        set = function(_, key, value) data[key] = value end,
        setMany = function(_, values)
            for key, value in pairs(values) do data[key] = value end
        end,
        delete = function(_, key) data[key] = nil end,
    }
end

local function document()
    return {
        reader_id = "parent-1",
        local_path = "/books/book.epub",
        local_format = "epub",
        is_local_present = true,
        is_managed = true,
    }
end

local function makeReaderUI(find_mode)
    local annotations = {}
    local save_calls, delete_calls = 0, 0
    local reader_ui = {
        rolling = {},
        annotation = { annotations = annotations },
        document = {},
        highlight = {},
    }

    reader_ui.document.findAllText = function(_, text)
        if find_mode and find_mode(text) == "ambiguous" then
            return {
                { start = "xp:" .. text .. ":0a", ["end"] = "xp:" .. text .. ":1a" },
                { start = "xp:" .. text .. ":0b", ["end"] = "xp:" .. text .. ":1b" },
            }
        end
        return {
            { start = "xp:" .. text .. ":0", ["end"] = "xp:" .. text .. ":1" },
        }
    end
    reader_ui.document.getTextFromXPointers = function(_, start)
        return start:match("^xp:(.*):0$")
    end
    reader_ui.highlight.saveHighlight = function(self)
        local item = {
            page = self.selected_text.pos0,
            pos0 = self.selected_text.pos0,
            pos1 = self.selected_text.pos1,
            text = self.selected_text.text,
            note = self.selected_text.note,
            datetime = "2026-09-25 00:00:00",
            drawer = "lighten",
        }
        annotations[#annotations + 1] = item
        return #annotations
    end
    reader_ui.highlight.deleteHighlight = function(_, index)
        delete_calls = delete_calls + 1
        table.remove(annotations, index)
    end
    reader_ui.saveSettings = function()
        save_calls = save_calls + 1
    end

    return reader_ui, annotations, function()
        return save_calls, delete_calls
    end
end

local function makeImporter(linked, options)
    options = options or {}
    linked = linked or {}
    return {
        getDocument = function(_, path)
            assert(path == "/books/book.epub")
            return document()
        end,
        isRemoteLinked = function(_, id)
            return linked[id] and {
                local_annotation_id = linked[id],
                reader_highlight_document_id = id,
            } or nil
        end,
        normalizeLocal = function(_, path, item)
            assert(path == "/books/book.epub")
            return {
                local_annotation_id = item.local_annotation_id
                    or ("local:" .. tostring(item.text)),
                locator_fingerprint = tostring(item.pos0) .. "|" .. tostring(item.pos1),
                text = item.text,
                note = item.note,
                text_hash = "th:" .. tostring(item.text),
                note_hash = "nh:" .. tostring(item.note),
            }, document()
        end,
        linkPersisted = function(_, path, remote, local_item)
            if options.link_failure then
                return nil, { kind = "db", message = "simulated link failure" }
            end
            if options.on_link then options.on_link(remote, local_item) end
            linked[remote.id] = local_item.local_annotation_id
                or ("ko:" .. remote.id)
            return {
                status = "linked",
                local_annotation_id = linked[remote.id],
            }
        end,
    }
end

local function remoteReport(highlights, options)
    options = options or {}
    return {
        parent_highlight_records = #highlights,
        remote_highlights = highlights,
        updated_after = options.updated_after,
        scan_started_at = options.scan_started_at
            or "2026-09-25T04:00:00Z",
        proposed_query_after = options.proposed_query_after
            or "2026-09-25T03:55:00Z",
    }
end

return function()
    -- Bulk import + idempotent repeat + historical->incremental watermark.
    withStubs(function(UI)
        local reader_ui, annotations, calls = makeReaderUI()
        local linked = { ["remote-existing"] = "ko-existing" }
        local link_calls = 0
        local worker_options = {}
        local sync_meta = newSyncMeta()
        local highlights = {
            {
                id = "remote-1", parent_id = "parent-1",
                content = "Passage one", notes = "Reader note",
                note_present = true,
            },
            {
                id = "remote-existing", parent_id = "parent-1",
                content = "Already linked", note_present = false,
            },
            {
                id = "remote-2", parent_id = "parent-1",
                content = "Passage two", note_present = false,
            },
        }
        local importer = makeImporter(linked, {
            on_link = function()
                link_calls = link_calls + 1
            end,
        })

        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = importer,
            sync_meta = sync_meta,
            get_current_path = function() return "/books/book.epub" end,
            get_reader_ui = function() return reader_ui end,
            worker = {
                run = function(_, path, options)
                    assert(path == "/books/book.epub")
                    worker_options[#worker_options + 1] = options or {}
                    return remoteReport(highlights, {
                        updated_after = options and options.updated_after,
                    })
                end,
            },
        }

        local first = assert(ui:prepareForSync("/books/book.epub"))
        assert(first.status == "ok")
        assert(first.scan_mode == "historical")
        assert(first.imported == 2)
        assert(first.notes_imported == 1)
        assert(first.linked_skipped == 1)
        assert(first.deferred_by_limit == 0)
        assert(first.suppress_current_document == false)
        assert(#first.suppress_outbound_ids == 0)
        assert(#annotations == 2)
        assert(annotations[1].note == "Reader note")
        assert(link_calls == 2)
        local save_calls, delete_calls = calls()
        assert(save_calls == 2 and delete_calls == 0)

        assert(sync_meta.data["remote_highlight_baseline:parent-1"] == "1")
        assert(sync_meta.data["remote_highlight_watermark:parent-1"]
            == "2026-09-25T04:00:00Z")
        assert(sync_meta.data["remote_highlight_query_after:parent-1"]
            == "2026-09-25T03:55:00Z")
        assert(worker_options[1].updated_after == nil)

        local second = assert(ui:prepareForSync("/books/book.epub"))
        assert(second.scan_mode == "incremental")
        assert(second.imported == 0)
        assert(second.linked_skipped == 3)
        assert(#annotations == 2)
        assert(link_calls == 2)
        assert(worker_options[2].updated_after == "2026-09-25T03:55:00Z")
    end)

    -- Link failure rolls back the just-created local highlight and suppresses
    -- outbound creates for the current document in the same Sync.
    withStubs(function(UI)
        local reader_ui, annotations, calls = makeReaderUI()
        local sync_meta = newSyncMeta()
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = makeImporter({}, { link_failure = true }),
            sync_meta = sync_meta,
            get_current_path = function() return "/books/book.epub" end,
            get_reader_ui = function() return reader_ui end,
            worker = {
                run = function()
                    return remoteReport({
                        {
                            id = "remote-1", parent_id = "parent-1",
                            content = "Exact passage", note_present = false,
                        },
                    })
                end,
            },
        }

        local result = assert(ui:prepareForSync("/books/book.epub"))
        assert(result.status == "error")
        assert(result.failures == 1)
        assert(result.suppress_current_document == true)
        assert(result.reader_document_id == "parent-1")
        assert(#annotations == 0)
        local save_calls, delete_calls = calls()
        assert(save_calls == 2 and delete_calls == 1)
        assert(sync_meta.data["remote_highlight_baseline:parent-1"] == nil)
    end)

    -- Cursor rotation prevents permanent starvation when early candidates are
    -- ambiguous and consume the locator-attempt budget.
    withStubs(function(UI)
        local reader_ui, annotations = makeReaderUI(function(text)
            if text == "Bad one" or text == "Bad two" then return "ambiguous" end
        end)
        local linked = {}
        local sync_meta = newSyncMeta()
        local highlights = {
            { id = "bad-1", parent_id = "parent-1", content = "Bad one", note_present = false },
            { id = "bad-2", parent_id = "parent-1", content = "Bad two", note_present = false },
            { id = "good-3", parent_id = "parent-1", content = "Good three", note_present = false },
            { id = "good-4", parent_id = "parent-1", content = "Good four", note_present = false },
        }
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = makeImporter(linked),
            sync_meta = sync_meta,
            get_current_path = function() return "/books/book.epub" end,
            get_reader_ui = function() return reader_ui end,
            max_imports = 10,
            max_locator_attempts = 2,
            worker = {
                run = function()
                    return remoteReport(highlights)
                end,
            },
        }

        local first = assert(ui:prepareForSync("/books/book.epub"))
        assert(first.imported == 0)
        assert(first.ambiguous == 2)
        assert(first.deferred_by_limit == 2)
        assert(sync_meta.data["remote_highlight_cursor:parent-1"] == "bad-2")

        local second = assert(ui:prepareForSync("/books/book.epub"))
        assert(second.imported == 2)
        assert(second.deferred_by_limit == 2)
        assert(#annotations == 2)
        assert(annotations[1].text == "Good three")
        assert(annotations[2].text == "Good four")
        assert(sync_meta.data["remote_highlight_cursor:parent-1"] == "good-4")

        local third = assert(ui:prepareForSync("/books/book.epub"))
        assert(third.imported == 0)
        assert(third.ambiguous == 2)
        assert(third.deferred_by_limit == 0)
        assert(sync_meta.data["remote_highlight_cursor:parent-1"] == nil)
        assert(sync_meta.data["remote_highlight_baseline:parent-1"] == "1")
    end)

    -- Existing exact local range with the same note is safely linked instead
    -- of creating a duplicate local annotation.
    withStubs(function(UI)
        local reader_ui, annotations = makeReaderUI()
        annotations[1] = {
            local_annotation_id = "local-existing",
            page = "xp:Same passage:0",
            pos0 = "xp:Same passage:0",
            pos1 = "xp:Same passage:1",
            text = "Same passage",
            note = "same note",
            datetime = "2026-09-25 00:00:00",
            drawer = "lighten",
        }
        local linked = {}
        local link_calls = 0
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = makeImporter(linked, {
                on_link = function(remote, local_item)
                    link_calls = link_calls + 1
                    assert(remote.id == "remote-same")
                    assert(local_item.local_annotation_id == "local-existing")
                end,
            }),
            sync_meta = newSyncMeta(),
            get_current_path = function() return "/books/book.epub" end,
            get_reader_ui = function() return reader_ui end,
            worker = {
                run = function()
                    return remoteReport({
                        {
                            id = "remote-same", parent_id = "parent-1",
                            content = "Same passage", notes = "same note",
                            note_present = true,
                        },
                    })
                end,
            },
        }

        local result = assert(ui:prepareForSync("/books/book.epub"))
        assert(result.imported == 0)
        assert(result.local_collisions == 1)
        assert(result.collisions_linked == 1)
        assert(result.collision_conflicts == 0)
        assert(#result.suppress_outbound_ids == 0)
        assert(#annotations == 1)
        assert(link_calls == 1)
    end)

    -- Same exact range but different notes is not guessed/merged. The local
    -- annotation ID is returned as a one-run outbound suppression guard.
    withStubs(function(UI)
        local reader_ui, annotations = makeReaderUI()
        annotations[1] = {
            local_annotation_id = "local-conflict",
            page = "xp:Same passage:0",
            pos0 = "xp:Same passage:0",
            pos1 = "xp:Same passage:1",
            text = "Same passage",
            note = "local note",
            datetime = "2026-09-25 00:00:00",
            drawer = "lighten",
        }
        local link_calls = 0
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = makeImporter({}, {
                on_link = function() link_calls = link_calls + 1 end,
            }),
            sync_meta = newSyncMeta(),
            get_current_path = function() return "/books/book.epub" end,
            get_reader_ui = function() return reader_ui end,
            worker = {
                run = function()
                    return remoteReport({
                        {
                            id = "remote-conflict", parent_id = "parent-1",
                            content = "Same passage", notes = "remote note",
                            note_present = true,
                        },
                    })
                end,
            },
        }

        local result = assert(ui:prepareForSync("/books/book.epub"))
        assert(result.status == "partial")
        assert(result.imported == 0)
        assert(result.local_collisions == 1)
        assert(result.collision_conflicts == 1)
        assert(result.suppress_current_document == false)
        assert(#result.suppress_outbound_ids == 1)
        assert(result.suppress_outbound_ids[1] == "local-conflict")
        assert(link_calls == 0)
        assert(#annotations == 1)
        assert(ui.sync_meta.data["remote_highlight_baseline:parent-1"] == nil,
            "unresolved exact collision must keep historical guard open")
    end)

    -- An ambiguous remote text only blocks matching local annotations. It
    -- keeps the historical guard open so the suppression cannot disappear
    -- behind the incremental watermark on a later Sync.
    withStubs(function(UI)
        local reader_ui, annotations = makeReaderUI(function(text)
            if text == "Repeated passage" then return "ambiguous" end
        end)
        annotations[1] = {
            local_annotation_id = "local-repeated",
            page = "xp:Repeated passage:local",
            pos0 = "xp:Repeated passage:local",
            pos1 = "xp:Repeated passage:local-end",
            text = "Repeated passage",
            note = nil,
            datetime = "2026-09-25 00:00:00",
            drawer = "lighten",
        }
        local sync_meta = newSyncMeta()
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = makeImporter({}),
            sync_meta = sync_meta,
            get_current_path = function() return "/books/book.epub" end,
            get_reader_ui = function() return reader_ui end,
            worker = {
                run = function()
                    return remoteReport({
                        {
                            id = "remote-repeated", parent_id = "parent-1",
                            content = "Repeated passage", note_present = false,
                        },
                    })
                end,
            },
        }

        local result = assert(ui:prepareForSync("/books/book.epub"))
        assert(result.ambiguous == 1)
        assert(result.unresolved_collision_risk == 1)
        assert(#result.suppress_outbound_ids == 1)
        assert(result.suppress_outbound_ids[1] == "local-repeated")
        assert(sync_meta.data["remote_highlight_baseline:parent-1"] == nil)
        assert(#annotations == 1)
    end)
end
