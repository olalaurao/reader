-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubbedUI(run)
    local names = {
        "ui/finished_diagnostics",
        "ui/widget/infomessage",
        "ui/uimanager",
        "gettext",
    }
    local saved_loaded, saved_preload = {}, {}
    for _, name in ipairs(names) do
        saved_loaded[name] = package.loaded[name]
        saved_preload[name] = package.preload[name]
        package.loaded[name] = nil
    end

    local shown = {}
    package.preload["gettext"] = function()
        return function(value) return value end
    end
    package.preload["ui/widget/infomessage"] = function()
        return { new = function(_, value) return value end }
    end
    package.preload["ui/uimanager"] = function()
        return { show = function(_, widget) shown[#shown + 1] = widget end }
    end

    local ok, err = pcall(function()
        run(require("ui/finished_diagnostics"), shown)
    end)

    for _, name in ipairs(names) do
        package.loaded[name] = saved_loaded[name]
        package.preload[name] = saved_preload[name]
    end
    if not ok then error(err) end
end

return function()
    withStubbedUI(function(UI, shown)
        local ui = UI:new{
            documents = {
                getByLocalPath = function(_, path)
                    assert(path == "/book.html")
                    return {
                        reader_id = "doc-1",
                        is_managed = true,
                        is_local_present = true,
                        location = "later",
                    }
                end,
            },
            status = {
                scan = function(_, path)
                    assert(path == "/book.html")
                    return {
                        sidecar_present = true,
                        sidecar_status = "complete",
                        sidecar_modified = "2026-09-24",
                        percent_finished = 0.82,
                        booklist_status = "complete",
                        finished = true,
                    }
                end,
            },
            get_current_path = function() return "/book.html" end,
            get_runtime_summary = function()
                return {
                    status = "complete",
                    modified = "2026-09-24",
                }
            end,
        }
        ui:run()
        assert(#shown == 1)
        local text = shown[1].text
        assert(text:find("Managed Reader document: yes", 1, true))
        assert(text:find("Reader location in local DB: later", 1, true))
        assert(text:find("Sidecar summary.status: complete", 1, true))
        assert(text:find("BookList status: complete", 1, true))
        assert(text:find("Runtime summary.status: complete", 1, true))
        assert(text:find("Canonical finished candidate (summary.status=complete): yes", 1, true))
        assert(text:find("Remote requests: none", 1, true))
        assert(text:find("Local writes: none", 1, true))
    end)

    withStubbedUI(function(UI, shown)
        local ui = UI:new{
            documents = { getByLocalPath = function() return nil end },
            status = {},
            get_current_path = function() return "/not-managed.html" end,
        }
        ui:run()
        assert(shown[1].text:find("not managed", 1, true))
    end)

    withStubbedUI(function(UI, shown)
        local ui = UI:new{
            documents = {},
            status = {},
            get_current_path = function() return nil end,
        }
        ui:run()
        assert(shown[1].text:find("Open a managed Reader document", 1, true))
    end)
end
