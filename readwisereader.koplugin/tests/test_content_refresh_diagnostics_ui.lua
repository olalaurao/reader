-- SPDX-License-Identifier: AGPL-3.0-only

local function withStubbedUI(run)
    local names = {
        "ui/content_refresh_diagnostics",
        "ui/widget/infomessage",
        "ui/trapper",
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
    package.preload["ui/trapper"] = function()
        return {
            wrap = function(_, fn) fn() end,
            dismissableRunInSubprocess = function(_, fn)
                local report, err = fn()
                return true, report, err
            end,
        }
    end

    local ok, err = pcall(function()
        run(require("ui/content_refresh_diagnostics"), shown)
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
                    return { reader_id = "doc-1", is_managed = true }
                end,
            },
            status = {
                scan = function()
                    return {
                        sidecar_present = true,
                        percent_finished = 0.42,
                        annotation_count = 2,
                        last_xpointer_present = true,
                        last_page_present = false,
                        partial_md5_checksum_present = true,
                        has_reading_state = true,
                    }
                end,
            },
            worker = {
                run = function(_, options)
                    assert(options.local_path == "/book.html")
                    assert(options.reading_state.annotation_count == 2)
                    return {
                        category = "article",
                        local_format = "html",
                        download_strategy = "reader_html",
                        local_present = true,
                        sidecar_present = true,
                        percent_finished = 0.42,
                        annotation_count = 2,
                        last_xpointer_present = true,
                        last_page_present = false,
                        partial_md5_checksum_present = true,
                        has_reading_state = true,
                        db_remote_updated_at = "u2",
                        materialized_remote_updated_at = "u1",
                        refresh_pending = true,
                        refresh_remote_updated_at = "u2",
                        remote_updated_at = "u2",
                        remote_revision_state = "newer_than_materialized",
                        remote_probe = "passed",
                        comparison = "different",
                        local_bytes = 1000,
                        remote_html_bytes = 900,
                        decision = "defer_changed_text_reading_state",
                        replacement_allowed = false,
                        remote_writes = 0,
                        local_writes = 0,
                    }
                end,
            },
            get_current_path = function() return "/book.html" end,
        }
        ui:run()
        assert(#shown == 1)
        local text = shown[1].text
        assert(text:find("Refresh pending: yes", 1, true))
        assert(text:find("Sidecar annotations: 2", 1, true))
        assert(text:find("Reading state at risk: yes", 1, true))
        assert(text:find("Visible-text comparison: different", 1, true))
        assert(text:find("V1 refresh decision: defer_changed_text_reading_state", 1, true))
        assert(text:find("Automatic replacement allowed: no", 1, true))
        assert(text:find("Remote writes: none", 1, true))
        assert(text:find("Local writes: none", 1, true))
    end)

    withStubbedUI(function(UI, shown)
        local ui = UI:new{
            documents = { getByLocalPath = function() return nil end },
            status = {},
            worker = {},
            get_current_path = function() return "/other.html" end,
        }
        ui:run()
        assert(shown[1].text:find("not managed", 1, true))
    end)
end
