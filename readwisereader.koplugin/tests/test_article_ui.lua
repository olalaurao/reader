-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubbedArticleUI(run)
    local module_names = {
        "ui/article",
        "ui/widget/container/centercontainer",
        "device",
        "ui/widget/infomessage",
        "ui/widget/menu",
        "ui/network/manager",
        "ui/trapper",
        "ui/uimanager",
        "gettext",
        "logger",
    }
    local saved_loaded = {}
    local saved_preload = {}
    for _, name in ipairs(module_names) do
        saved_loaded[name] = package.loaded[name]
        saved_preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    local state = {
        shown = {},
        closed = {},
        next_ticks = {},
        wrap_calls = 0,
        subprocess_calls = 0,
        menu_options = nil,
        container = nil,
        online = true,
        downloads = {},
    }

    package.preload["gettext"] = function()
        return function(text) return text end
    end
    package.preload["device"] = function()
        return {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
                getSize = function() return { w = 600, h = 800 } end,
            },
        }
    end
    package.preload["ui/widget/infomessage"] = function()
        return {
            new = function(_, options) return options end,
        }
    end
    package.preload["ui/widget/menu"] = function()
        return {
            new = function(_, options)
                state.menu_options = options
                return options
            end,
        }
    end
    package.preload["ui/widget/container/centercontainer"] = function()
        return {
            new = function(_, options)
                state.container = options
                return options
            end,
        }
    end
    package.preload["ui/network/manager"] = function()
        return {
            isOnline = function() return state.online end,
        }
    end
    package.preload["ui/trapper"] = function()
        return {
            wrap = function(_, callback)
                state.wrap_calls = state.wrap_calls + 1
                callback()
                return true
            end,
            dismissableRunInSubprocess = function(_, task)
                state.subprocess_calls = state.subprocess_calls + 1
                return true, task()
            end,
        }
    end
    package.preload["ui/uimanager"] = function()
        return {
            show = function(_, widget)
                state.shown[#state.shown + 1] = widget
            end,
            close = function(_, widget)
                state.closed[#state.closed + 1] = widget
            end,
            nextTick = function(_, callback)
                state.next_ticks[#state.next_ticks + 1] = callback
            end,
        }
    end
    package.preload["logger"] = function()
        return { warn = function() end }
    end

    local ok, err = pcall(function()
        local ArticleUI = require("ui/article")
        run(ArticleUI, state)
    end)

    for _, name in ipairs(module_names) do
        package.loaded[name] = saved_loaded[name]
        package.preload[name] = saved_preload[name]
    end
    if not ok then error(err) end
end

return function()
    withStubbedArticleUI(function(ArticleUI, state)
        local ui = ArticleUI:new{
            config = { hasAccessToken = function() return true end },
            coordinator = {
                listCandidates = function()
                    return {
                        { id = "doc-1", title = "Article one", author = "Author A" },
                        { id = "doc-2", title = "Article two" },
                    }
                end,
                getExistingPath = function() return nil end,
                fetchDocument = function(_, id)
                    state.downloads[#state.downloads + 1] = id
                    return { id = id, category = "article", html_content = "<p>x</p>" }
                end,
                installDocument = function(_, document)
                    return { path = "/Readwise/" .. document.id .. ".html" }
                end,
            },
            koreader_documents = { openDocument = function() end },
        }

        local menu_item = ui:getMenuItem()
        assert(menu_item.keep_menu_open == nil, "origin TouchMenu must be allowed to close")

        ui:chooseArticle()
        assert(state.wrap_calls == 1)
        assert(state.subprocess_calls == 1)
        assert(#state.next_ticks == 1, "selector must be scheduled after Trapper returns")
        assert(state.menu_options == nil, "Menu must not be built inside Trapper flow")

        local show_selector = table.remove(state.next_ticks, 1)
        show_selector()
        assert(state.menu_options ~= nil)
        assert(state.menu_options.title:find("Choose a Reader article", 1, true))
        assert(#state.menu_options.item_table == 2)
        assert(state.container ~= nil)
        assert(state.shown[#state.shown] == state.container)
        assert(ui.candidate_menu == state.container)

        state.menu_options.item_table[1].callback()
        assert(state.closed[#state.closed] == state.container)
        assert(ui.candidate_menu == nil)
        assert(#state.next_ticks == 1, "download must be scheduled after selector closes")

        local start_download = table.remove(state.next_ticks, 1)
        start_download()
        assert(state.downloads[1] == "doc-1")
    end)
end
