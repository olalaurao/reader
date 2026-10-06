-- SPDX-License-Identifier: AGPL-3.0-only

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Tags = require("metadata/tags")
local _ = require("gettext")
local Screen = Device.screen

local TagPicker = {}

local function trim(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value == "" then return nil end
    return value
end

local function asSet(values)
    local out = {}
    for _, value in ipairs(Tags.normalize(values)) do out[value] = true end
    return out
end

local function asList(set)
    local out = {}
    for value, enabled in pairs(set or {}) do
        if enabled then out[#out + 1] = value end
    end
    return Tags.normalize(out)
end

local function mergeValues(a, b)
    local set = asSet(a)
    for _, value in ipairs(Tags.normalize(b)) do set[value] = true end
    return asList(set)
end

function TagPicker.fetchTagNames(self)
    if not self.config:hasAccessToken() then return {} end
    local names = {}
    Trapper:wrap(function()
        local completed, value = Trapper:dismissableRunInSubprocess(function()
            local result, cursor, seen = {}, nil, {}
            while true do
                local page, page_err = self.reader:listTags{ page_cursor = cursor }
                if not page then return nil, page_err end
                for _, tag in ipairs(page.results or {}) do
                    if type(tag.name) == "string" and tag.name ~= "" and not seen[tag.name] then
                        seen[tag.name] = true
                        result[#result + 1] = tag.name
                    end
                end
                cursor = page.next_page_cursor
                if cursor == nil then break end
            end
            table.sort(result)
            return result
        end, _([[Loading Reader tags...

Tap to cancel. This is a read-only request.]]))
        if completed and type(value) == "table" then names = value end
    end)
    return names
end

function TagPicker.closeActiveMenu(self)
    if self.active_menu then
        UIManager:close(self.active_menu)
        self.active_menu = nil
    end
end

local function showTextInput(self, options)
    local dialog
    dialog = InputDialog:new{
        title = options.title,
        input = options.input or "",
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"), id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self.active_dialog = nil
                    end,
                },
                {
                    text = options.ok_text or _("OK"),
                    is_enter_default = true,
                    callback = function()
                        local value = dialog:getInputText()
                        UIManager:close(dialog)
                        self.active_dialog = nil
                        options.callback(value)
                    end,
                },
            },
        },
    }
    self.active_dialog = dialog
    UIManager:show(dialog)
    if type(dialog.onShowKeyboard) == "function" then dialog:onShowKeyboard() end
end

function TagPicker.show(self, options)
    options = options or {}
    TagPicker.closeActiveMenu(self)

    local selected = options.selected_set or asSet(options.selected)
    local available = mergeValues(options.available, asList(selected))
    local query = trim(options.query)
    local visible = {}
    for _, tag in ipairs(available) do
        if not query or tag:lower():find(query:lower(), 1, true) then
            visible[#visible + 1] = tag
        end
    end

    local container
    local menu
    local items = {
        {
            text = _("Save tags"),
            mandatory = Tags.display(asList(selected)),
            callback = function()
                if container then UIManager:close(container) end
                self.active_menu = nil
                if type(options.on_save) == "function" then
                    options.on_save(asList(selected))
                end
            end,
        },
        {
            text = _("Search existing tags..."),
            callback = function()
                if container then UIManager:close(container) end
                self.active_menu = nil
                showTextInput(self, {
                    title = _("Search Reader tags"),
                    input = query or "",
                    ok_text = _("Filter"),
                    callback = function(value)
                        TagPicker.show(self, {
                            title = options.title,
                            selected_set = selected,
                            available = available,
                            query = value,
                            on_save = options.on_save,
                        })
                    end,
                })
            end,
        },
        {
            text = _("Add new tag..."),
            callback = function()
                if container then UIManager:close(container) end
                self.active_menu = nil
                showTextInput(self, {
                    title = _("New Reader tag"),
                    ok_text = _("Add"),
                    callback = function(value)
                        local tag = trim(value)
                        if not tag then
                            UIManager:show(InfoMessage:new{ text = _("Tag name cannot be empty.") })
                            TagPicker.show(self, {
                                title = options.title,
                                selected_set = selected,
                                available = available,
                                query = query,
                                on_save = options.on_save,
                            })
                            return
                        end
                        selected[tag] = true
                        available = mergeValues(available, { tag })
                        TagPicker.show(self, {
                            title = options.title,
                            selected_set = selected,
                            available = available,
                            query = query,
                            on_save = options.on_save,
                        })
                    end,
                })
            end,
        },
    }

    for _, tag in ipairs(visible) do
        items[#items + 1] = {
            text = tag,
            checked_func = function() return selected[tag] == true end,
            callback = function()
                selected[tag] = not selected[tag]
                if menu and type(menu.updateItems) == "function" then menu:updateItems() end
            end,
        }
    end

    if #visible == 0 then
        items[#items + 1] = {
            text = query and _("No matching Reader tags") or _("No Reader tags cached"),
            enabled = false,
        }
    end

    menu = Menu:new{
        title = options.title or _("Reader tags"),
        item_table = items,
        width = math.floor(Screen:getWidth() * 0.94),
        height = math.floor(Screen:getHeight() * 0.82),
        single_line = false,
        close_callback = function()
            if container then UIManager:close(container) end
            self.active_menu = nil
        end,
    }
    container = CenterContainer:new{ dimen = Screen:getSize(), menu }
    menu.show_parent = container
    self.active_menu = container
    UIManager:show(container)
end

TagPicker._asSet = asSet
TagPicker._asList = asList
TagPicker._mergeValues = mergeValues

return TagPicker
