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

local function makeReaderUI()
    local annotations = {}
    local save_calls, delete_calls = 0, 0
    local reader_ui = {
        rolling = {},
        annotation = { annotations = annotations },
        document = {},
        highlight = {},
    }
    reader_ui.document.findAllText = function(_, text)
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

return function()
    withStubs(function(UI, shown)
        local reader_ui, annotations, calls = makeReaderUI()
        local linked = { ["remote-hl-existing"] = true }
        local link_calls = 0
        local remote_report = {
            parent_highlight_records = 3,
            remote_highlights = {
                {
                    id = "remote-hl-1",
                    parent_id = "parent-1",
                    content = "Passage one",
                    notes = "Reader note",
                    note_present = true,
                },
                {
                    id = "remote-hl-existing",
                    parent_id = "parent-1",
                    content = "Already linked",
                    note_present = false,
                },
                {
                    id = "remote-hl-2",
                    parent_id = "parent-1",
                    content = "Passage two",
                    notes = nil,
                    note_present = false,
                },
            },
        }

        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = {
                isRemoteLinked = function(_, id)
                    return linked[id] and { local_annotation_id = "known-" .. id } or nil
                end,
                linkPersisted = function(_, path, remote, local_item)
                    link_calls = link_calls + 1
                    assert(path == "/books/book.epub")
                    assert(local_item.text == remote.content)
                    linked[remote.id] = true
                    return { status = "linked", local_annotation_id = "ko-" .. remote.id }
                end,
            },
            get_current_path = function() return "/books/book.epub" end,
            get_reader_ui = function() return reader_ui end,
            worker = {
                run = function(_, path)
                    assert(path == "/books/book.epub")
                    return remote_report
                end,
            },
        }

        ui:run()
        assert(#annotations == 2)
        assert(annotations[1].text == "Passage one")
        assert(annotations[1].note == "Reader note")
        assert(annotations[2].text == "Passage two")
        local save_calls, delete_calls = calls()
        assert(save_calls == 2)
        assert(delete_calls == 0)
        assert(link_calls == 2)
        local text = shown[#shown].text
        assert(text:find("Imported local highlights: 2", 1, true))
        assert(text:find("Imported notes preserved: 1", 1, true))
        assert(text:find("Remote highlights already linked/skipped: 1", 1, true))
        assert(text:find("Remote writes: none", 1, true))

        ui:run()
        assert(#annotations == 2, "repeat import must be idempotent")
        assert(link_calls == 2, "repeat import must not relink known remote IDs")
        text = shown[#shown].text
        assert(text:find("Imported local highlights: 0", 1, true))
        assert(text:find("Remote highlights already linked/skipped: 3", 1, true))
    end)

    withStubs(function(UI, shown)
        local reader_ui, annotations, calls = makeReaderUI()
        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = {
                isRemoteLinked = function() return nil end,
                linkPersisted = function()
                    return nil, { kind = "db" }
                end,
            },
            get_current_path = function() return "/books/book.epub" end,
            get_reader_ui = function() return reader_ui end,
            worker = {
                run = function()
                    return {
                        parent_highlight_records = 1,
                        remote_highlights = {
                            {
                                id = "remote-hl-1",
                                parent_id = "parent-1",
                                content = "Exact Reader passage",
                                notes = nil,
                                note_present = false,
                            },
                        },
                    }
                end,
            },
        }

        ui:run()
        assert(#annotations == 0)
        local save_calls, delete_calls = calls()
        assert(delete_calls == 1)
        assert(save_calls == 2)
        assert(shown[#shown].text:find("rolled back", 1, true))
    end)

    withStubs(function(UI, shown)
        local reader_ui, annotations = makeReaderUI()
        local linked = {}
        local remotes = {}
        for index = 1, 5 do
            remotes[index] = {
                id = "remote-" .. index,
                parent_id = "parent-1",
                content = "Passage " .. index,
                note_present = false,
            }
        end

        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = {
                isRemoteLinked = function(_, id)
                    return linked[id] and { local_annotation_id = id } or nil
                end,
                linkPersisted = function(_, path, remote)
                    linked[remote.id] = true
                    return { status = "linked", local_annotation_id = remote.id }
                end,
            },
            get_current_path = function() return "/books/book.epub" end,
            get_reader_ui = function() return reader_ui end,
            max_imports = 2,
            max_locator_attempts = 3,
            worker = {
                run = function()
                    return {
                        parent_highlight_records = 5,
                        remote_highlights = remotes,
                    }
                end,
            },
        }

        local result = assert(ui:importAfterSync("/books/book.epub"))
        assert(result.status == "ok")
        assert(result.imported == 2)
        assert(result.deferred_by_limit == 3)
        assert(#annotations == 2)

        result = assert(ui:importAfterSync("/books/book.epub"))
        assert(result.imported == 2)
        assert(result.linked_skipped == 2)
        assert(result.deferred_by_limit == 1)
        assert(#annotations == 4)

        result = assert(ui:importAfterSync("/books/book.epub"))
        assert(result.imported == 1)
        assert(result.linked_skipped == 4)
        assert(result.deferred_by_limit == 0)
        assert(#annotations == 5)

        result = assert(ui:importAfterSync("/books/book.epub"))
        assert(result.imported == 0)
        assert(result.linked_skipped == 5)
        assert(#annotations == 5)
    end)
end
