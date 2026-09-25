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

return function()
    withStubs(function(UI, shown)
        local annotations = {}
        local save_calls, delete_calls, link_calls = 0, 0, 0
        local reader_ui = {
            rolling = {},
            annotation = { annotations = annotations },
            document = {
                findAllText = function(_, text)
                    assert(text == "Exact Reader passage")
                    return { { start = "xp-start", ["end"] = "xp-end" } }
                end,
                getTextFromXPointers = function(_, start, finish)
                    assert(start == "xp-start")
                    assert(finish == "xp-end")
                    return "Exact Reader passage"
                end,
            },
            highlight = {},
        }
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
            annotations[1] = item
            return 1
        end
        reader_ui.highlight.deleteHighlight = function(_, index)
            delete_calls = delete_calls + 1
            table.remove(annotations, index)
        end
        reader_ui.saveSettings = function()
            save_calls = save_calls + 1
        end

        local importer = {
            isRemoteLinked = function() return nil end,
            linkPersisted = function(_, path, remote, local_item)
                link_calls = link_calls + 1
                assert(path == "/books/book.epub")
                assert(remote.id == "remote-hl-1")
                assert(remote.parent_id == "parent-1")
                assert(local_item.note == "Reader note")
                return { status = "linked", local_annotation_id = "ko-1" }
            end,
        }

        local ui = UI:new{
            config = { hasAccessToken = function() return true end },
            importer = importer,
            get_current_path = function() return "/books/book.epub" end,
            get_reader_ui = function() return reader_ui end,
            worker = {
                run = function(_, path)
                    assert(path == "/books/book.epub")
                    return {
                        parent_highlight_records = 70,
                        remote_highlights = {
                            {
                                id = "remote-hl-1",
                                parent_id = "parent-1",
                                content = "Exact Reader passage",
                                notes = "Reader note",
                                note_present = true,
                            },
                        },
                    }
                end,
            },
        }

        ui:run()
        assert(#annotations == 1)
        assert(annotations[1].text == "Exact Reader passage")
        assert(annotations[1].note == "Reader note")
        assert(save_calls == 1)
        assert(delete_calls == 0)
        assert(link_calls == 1)
        local text = shown[#shown].text
        assert(text:find("Imported local highlights: 1", 1, true))
        assert(text:find("Imported note present: yes", 1, true))
        assert(text:find("Remote identity linked durably: yes", 1, true))
        assert(text:find("Sidecar persistence verified: yes", 1, true))
        assert(text:find("Remote writes: none", 1, true))
    end)

    withStubs(function(UI, shown)
        local annotations = {}
        local save_calls, delete_calls = 0, 0
        local reader_ui = {
            rolling = {},
            annotation = { annotations = annotations },
            document = {
                findAllText = function()
                    return { { start = "xp-start", ["end"] = "xp-end" } }
                end,
                getTextFromXPointers = function()
                    return "Exact Reader passage"
                end,
            },
            highlight = {},
        }
        reader_ui.highlight.saveHighlight = function(self)
            annotations[1] = {
                page = self.selected_text.pos0,
                pos0 = self.selected_text.pos0,
                pos1 = self.selected_text.pos1,
                text = self.selected_text.text,
                note = self.selected_text.note,
                datetime = "2026-09-25 00:00:00",
                drawer = "lighten",
            }
            return 1
        end
        reader_ui.highlight.deleteHighlight = function(_, index)
            delete_calls = delete_calls + 1
            table.remove(annotations, index)
        end
        reader_ui.saveSettings = function()
            save_calls = save_calls + 1
        end

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
        assert(delete_calls == 1)
        assert(save_calls == 2)
        assert(shown[#shown].text:find("rolled back", 1, true))
    end)
end
