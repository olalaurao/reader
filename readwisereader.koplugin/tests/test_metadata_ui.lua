-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubbedUI(run)
    local names = {
        "ui/metadata",
        "ui/metadata_document",
        "ui/metadata_highlight",
        "ui/metadata_tags",
        "ui/widget/container/centercontainer",
        "device",
        "ui/widget/infomessage",
        "ui/widget/inputdialog",
        "ui/widget/menu",
        "ui/trapper",
        "ui/uimanager",
        "gettext",
    }
    local loaded, preload = {}, {}
    local state = { shown = {}, buttons = {}, pending = nil, links = {} }
    for _, name in ipairs(names) do
        loaded[name] = package.loaded[name]
        preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    package.preload["gettext"] = function() return function(v) return v end end
    package.preload["device"] = function()
        return { screen = {
            getWidth = function() return 600 end,
            getHeight = function() return 800 end,
            getSize = function() return { w = 600, h = 800 } end,
        } }
    end
    package.preload["ui/widget/container/centercontainer"] = function()
        return { new = function(_, value) return value end }
    end
    package.preload["ui/widget/infomessage"] = function()
        return { new = function(_, value) return value end }
    end
    package.preload["ui/widget/inputdialog"] = function()
        return { new = function(_, value)
            function value:getInputText() return value.input or "" end
            function value:onShowKeyboard() end
            return value
        end }
    end
    package.preload["ui/widget/menu"] = function()
        return { new = function(_, value)
            function value:updateItems() state.updated = (state.updated or 0) + 1 end
            return value
        end }
    end
    package.preload["ui/trapper"] = function()
        return {
            wrap = function(_, fn) return fn() end,
            dismissableRunInSubprocess = function(_, fn) return true, fn() end,
        }
    end
    package.preload["ui/uimanager"] = function()
        return {
            show = function(_, widget) state.shown[#state.shown + 1] = widget end,
            close = function() end,
            nextTick = function(_, fn) return fn() end,
        }
    end

    local ok, failure = pcall(function()
        local MetadataUI = require("ui/metadata")
        local annotations = {
            getById = function(_, id) return state.links[id] end,
            upsertLocal = function(_, item)
                local link = {
                    local_annotation_id = item.local_annotation_id,
                    reader_document_id = item.reader_document_id,
                    locator_fingerprint = item.locator_fingerprint,
                    sync_state = item.sync_state,
                }
                state.links[item.local_annotation_id] = link
                return link
            end,
        }
        local ui = MetadataUI:new{
            config = { hasAccessToken = function() return false end },
            reader = {},
            documents = {
                getByLocalPath = function(_, path)
                    if path == "/Readwise/a.epub" then
                        return {
                            reader_id = "doc-1", local_path = path,
                            is_managed = true, remote_tags = { "alpha" }, remote_notes = "old",
                        }
                    end
                end,
                getById = function(_, id)
                    if id == "doc-1" then return { reader_id = id, remote_notes = "remote" } end
                end,
            },
            annotations = annotations,
            annotation_metadata = {
                getById = function() return nil end,
                setPendingTags = function(_, id, baseline, desired)
                    state.pending = { id = id, baseline = baseline, desired = desired }
                end,
                markTagsSynced = function() end,
            },
            remote_highlights = { getByRemoteId = function() end },
            queue = { getByKey = function() end },
            mutations = {
                getPendingDocumentState = function()
                    return { tags = { "alpha" }, note = "queued", tags_pending = false, note_pending = true }
                end,
                queueDocumentNote = function(_, document, note)
                    state.queued_note = { document = document, note = note }
                    return true
                end,
                cancelDocumentEdit = function(_, document, field)
                    state.cancelled = { document = document, field = field }
                    return true
                end,
                queueDocumentTags = function() return true end,
                queueHighlightTags = function() return true end,
            },
            adapter = {
                normalize = function()
                    return {
                        local_annotation_id = "ann-1", locator_fingerprint = "loc",
                        text_hash = "t", note_hash = "n", datetime = "now",
                    }
                end,
            },
            get_current_path = function() return "/Readwise/a.epub" end,
            get_reader_ui = function()
                return {
                    annotation = { annotations = { { drawer = "lighten", text = "x" } } },
                    highlight = {
                        addToHighlightDialog = function(_, key, factory)
                            state.buttons[key] = factory
                        end,
                        onClose = function() end,
                    },
                }
            end,
        }
        run(ui, state)
    end)

    for _, name in ipairs(names) do
        package.loaded[name] = loaded[name]
        package.preload[name] = preload[name]
    end
    if not ok then error(failure) end
end

return function()
    withStubbedUI(function(ui, state)
        local item = ui:getMenuItem()
        assert(item.text == "Reader metadata")
        assert(item.enabled_func() == true)

        assert(ui:registerHighlightButton() == true)
        local factory = assert(state.buttons["08_readwise_tags"])
        local button = factory({ selected_text = {} }, 1)
        assert(button.text == "Reader tags")
        assert(button.show_in_highlight_dialog_func() == true)

        ui:_showTagPicker{
            title = "Reader document tags",
            selected = { "alpha" },
            available = { "alpha", "beta" },
            on_save = function(tags) state.saved = tags end,
        }
        local menu_container = state.shown[#state.shown]
        local menu = menu_container[1]
        assert(menu.item_table[1].text == "Save tags")
        assert(menu.item_table[2].text == "Search existing tags...")
        assert(menu.item_table[3].text == "Add new tag...")
        assert(menu.item_table[4].text == "alpha")
        assert(menu.item_table[4].checked_func() == true)

        ui:editDocumentNote({ reader_id = "doc-1", remote_notes = "remote" }, {
            note = "kindle", note_pending = true, note_status = "blocked",
        })
        local dialog = state.shown[#state.shown]
        assert(dialog.title == "Reader document note - conflict")
        assert(dialog.buttons[1][2].text == "Keep Kindle")
        assert(dialog.buttons[2][1].text == "Use Reader version")
        dialog.buttons[2][1].callback()
        assert(state.cancelled.field == "note")
        assert(state.cancelled.document.reader_id == "doc-1")

        local new_highlight = {
            selected_text = { text = "new" },
            ui = { annotation = { annotations = {} } },
            saveHighlight = function(this)
                state.created_before_tagging = true
                this.ui.annotation.annotations[1] = {
                    drawer = "lighten", text = "new", datetime = "now",
                }
                return 1
            end,
        }
        local new_button = factory(new_highlight, nil)
        new_button.callback()
        assert(state.created_before_tagging == true)
        assert(state.links["ann-1"] ~= nil,
            "new highlight must get a durable local identity before tag intent")
    end)
end
