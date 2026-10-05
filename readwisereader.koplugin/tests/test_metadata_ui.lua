-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubbedUI(run)
    local names = {
        "ui/metadata",
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
    local state = { shown = {}, buttons = {}, pending = nil }
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
            getById = function() return nil end,
            upsertLocal = function(_, item) return item end,
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
                queueDocumentNote = function() return true end,
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
        local button = factory({}, 1)
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
        assert(menu.item_table[2].text == "Search existing tags…")
        assert(menu.item_table[3].text == "Add new tag…")
        assert(menu.item_table[4].text == "alpha")
        assert(menu.item_table[4].checked_func() == true)
    end)
end
