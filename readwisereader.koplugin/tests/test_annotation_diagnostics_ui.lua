-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubbedUI(run)
    local names = {
        "ui/annotation_diagnostics",
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
        return { new = function(_, options) return options end }
    end
    package.preload["ui/uimanager"] = function()
        return { show = function(_, widget) shown[#shown + 1] = widget end }
    end

    local ok, err = pcall(function()
        run(require("ui/annotation_diagnostics"), shown)
    end)

    for _, name in ipairs(names) do
        package.loaded[name] = saved_loaded[name]
        package.preload[name] = saved_preload[name]
    end
    if not ok then error(err) end
end

return function()
    withStubbedUI(function(AnnotationDiagnosticsUI, shown)
        local ui = AnnotationDiagnosticsUI:new{
            scanner = { scanPath = function() error("must not scan") end },
            get_current_path = function() return nil end,
        }
        ui:scanCurrent()
        assert(#shown == 1)
        assert(shown[1].text:find("Open a Readwise-managed document", 1, true))
    end)

    withStubbedUI(function(AnnotationDiagnosticsUI, shown)
        local scanned_path
        local ui = AnnotationDiagnosticsUI:new{
            scanner = {
                scanPath = function(_, path)
                    scanned_path = path
                    return {
                        authoritative = true,
                        status = "ok",
                        highlights = 1,
                        notes = 1,
                        new = 1,
                        changed = 0,
                        unchanged = 0,
                        deleted = 0,
                        malformed = 0,
                        sample = {
                            local_annotation_id = "ko-abc123",
                            text = "selected exact text",
                            note = "gate7 [[Foucault]]\n\n#pesquisar 🧠",
                        },
                    }
                end,
            },
            get_current_path = function() return "/Readwise/test.epub" end,
        }
        ui:scanCurrent()
        assert(scanned_path == "/Readwise/test.epub")
        assert(#shown == 1)
        assert(shown[1].text:find("Local ID: ko-abc123", 1, true))
        assert(shown[1].text:find("selected exact text", 1, true))
        assert(shown[1].text:find("gate7 [[Foucault]]", 1, true))
        assert(shown[1].text:find("#pesquisar 🧠", 1, true))
    end)

    withStubbedUI(function(AnnotationDiagnosticsUI, shown)
        local ui = AnnotationDiagnosticsUI:new{
            scanner = {
                scanPath = function()
                    return {
                        authoritative = false,
                        status = "annotations_missing",
                    }
                end,
            },
            get_current_path = function() return "/Readwise/test.epub" end,
        }
        ui:scanCurrent()
        assert(#shown == 1)
        assert(shown[1].text:find("No deletion state was inferred", 1, true))
    end)
end
