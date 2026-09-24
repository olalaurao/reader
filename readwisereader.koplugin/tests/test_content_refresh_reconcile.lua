-- SPDX-License-Identifier: AGPL-3.0-only

local Reconcile = require("sync/content_refresh_reconcile")

local function newHarness(options)
    options = options or {}
    local rows = {}
    for _, row in ipairs(options.rows or {}) do
        rows[#rows + 1] = row
    end

    local cleared = {}
    local repository = {
        listContentRefreshPending = function()
            return rows
        end,
        clearContentRefreshPending = function(_, id)
            cleared[#cleared + 1] = id
            for _, row in ipairs(rows) do
                if row.reader_id == id then
                    row.content_refresh_pending = false
                    row.content_refresh_remote_updated_at = nil
                end
            end
        end,
        countContentRefreshPending = function()
            local count = 0
            for _, row in ipairs(rows) do
                if row.content_refresh_pending == true then count = count + 1 end
            end
            return count
        end,
    }

    local gets = {}
    local reader = {
        getDocument = function(_, id, with_html, with_raw, max_bytes)
            gets[#gets + 1] = {
                id = id,
                with_html = with_html,
                with_raw = with_raw,
                max_bytes = max_bytes,
            }
            local value = options.remote and options.remote[id]
            if type(value) == "function" then return value() end
            if value and value.error then return nil, value.error end
            return value
        end,
    }

    local files = options.files or {}
    local reconciler = Reconcile:new{
        documents = repository,
        reader = reader,
        file_exists = function(path)
            return files[path] ~= nil
        end,
        read_file = function(path)
            return files[path], files[path] and nil or "io"
        end,
        max_article_checks = options.max_article_checks or 5,
        local_max_bytes = 1024 * 1024,
        remote_max_bytes = 1024 * 1024,
    }

    return reconciler, rows, cleared, gets
end

return function()
    do
        local reconciler, rows, cleared, gets = newHarness{
            rows = {
                {
                    reader_id = "article-1",
                    category = "article",
                    local_format = "html",
                    local_path = "/a.html",
                    is_local_present = true,
                    content_refresh_pending = true,
                    content_refresh_remote_updated_at = "u2",
                },
            },
            files = {
                ["/a.html"] = "<html><body><p>Hello world</p></body></html>",
            },
            remote = {
                ["article-1"] = {
                    id = "article-1",
                    updated_at = "u2",
                    html_content = "<article><p>Hello   world</p></article>",
                },
            },
        }
        local report = reconciler:run()
        assert(report.pending_seen == 1)
        assert(report.article_checked == 1)
        assert(report.metadata_only_acknowledged == 1)
        assert(report.changed_retained == 0)
        assert(report.pending_after == 0)
        assert(#cleared == 1 and cleared[1] == "article-1")
        assert(rows[1].content_refresh_pending == false)
        assert(#gets == 1 and gets[1].with_html == true)

        -- Once the exact metadata-only revision is acknowledged, a later
        -- unchanged Sync must do no refresh work and issue no second GET.
        local second_report = reconciler:run()
        assert(second_report.pending_seen == 0)
        assert(second_report.article_checked == 0)
        assert(second_report.metadata_only_acknowledged == 0)
        assert(second_report.changed_retained == 0)
        assert(second_report.pending_after == 0)
        assert(#cleared == 1)
        assert(#gets == 1)
    end

    do
        local reconciler, _, cleared = newHarness{
            rows = {
                {
                    reader_id = "article-2",
                    category = "article",
                    local_format = "html",
                    local_path = "/b.html",
                    is_local_present = true,
                    content_refresh_pending = true,
                    content_refresh_remote_updated_at = "u2",
                },
            },
            files = { ["/b.html"] = "<p>Old text</p>" },
            remote = {
                ["article-2"] = {
                    id = "article-2",
                    updated_at = "u2",
                    html_content = "<p>Changed text</p>",
                },
            },
        }
        local report = reconciler:run()
        assert(report.changed_retained == 1)
        assert(report.metadata_only_acknowledged == 0)
        assert(report.pending_after == 1)
        assert(#cleared == 0)
    end

    do
        local reconciler, _, cleared, gets = newHarness{
            rows = {
                {
                    reader_id = "pdf-1",
                    category = "pdf",
                    local_format = "pdf",
                    local_path = "/a.pdf",
                    is_local_present = true,
                    content_refresh_pending = true,
                    content_refresh_remote_updated_at = "u2",
                },
                {
                    reader_id = "epub-1",
                    category = "epub",
                    local_format = "epub",
                    local_path = "/a.epub",
                    is_local_present = true,
                    content_refresh_pending = true,
                    content_refresh_remote_updated_at = "u2",
                },
            },
            files = {
                ["/a.pdf"] = "pdf",
                ["/a.epub"] = "epub",
            },
            remote = {},
        }
        local report = reconciler:run()
        assert(report.raw_retained == 2)
        assert(report.pending_after == 2)
        assert(#cleared == 0)
        assert(#gets == 0, "raw revisions must not fetch replacement content")

        local second_report = reconciler:run()
        assert(second_report.raw_retained == 2)
        assert(second_report.pending_after == 2)
        assert(#cleared == 0)
        assert(#gets == 0,
            "repeated Sync must keep raw revisions pending without replacement GETs")
    end

    do
        local reconciler, _, cleared, gets = newHarness{
            rows = {
                {
                    reader_id = "article-missing-local",
                    category = "article",
                    local_format = "html",
                    local_path = "/missing.html",
                    is_local_present = true,
                    content_refresh_pending = true,
                    content_refresh_remote_updated_at = "u2",
                },
            },
            files = {},
            remote = {
                ["article-missing-local"] = {
                    id = "article-missing-local",
                    updated_at = "u2",
                    html_content = "<p>Remote text</p>",
                },
            },
        }
        local report = reconciler:run()
        assert(report.local_missing == 1)
        assert(report.article_checked == 0)
        assert(report.metadata_only_acknowledged == 0)
        assert(report.pending_after == 1)
        assert(#cleared == 0)
        assert(#gets == 0,
            "missing local bytes must retain pending without a remote comparison")
    end

    do
        local reconciler, _, cleared = newHarness{
            rows = {
                {
                    reader_id = "article-race",
                    category = "article",
                    local_format = "html",
                    local_path = "/race.html",
                    is_local_present = true,
                    content_refresh_pending = true,
                    content_refresh_remote_updated_at = "u2",
                },
            },
            files = { ["/race.html"] = "<p>Same</p>" },
            remote = {
                ["article-race"] = {
                    id = "article-race",
                    updated_at = "u3",
                    html_content = "<p>Same</p>",
                },
            },
        }
        local report = reconciler:run()
        assert(report.revision_races == 1)
        assert(report.unverified_retained == 1)
        assert(report.pending_after == 1)
        assert(#cleared == 0,
            "stale pending evidence must never acknowledge a newer remote revision")
    end

    do
        local reconciler, _, cleared = newHarness{
            rows = {
                {
                    reader_id = "article-err",
                    category = "article",
                    local_format = "html",
                    local_path = "/err.html",
                    is_local_present = true,
                    content_refresh_pending = true,
                    content_refresh_remote_updated_at = "u2",
                },
            },
            files = { ["/err.html"] = "<p>Same</p>" },
            remote = {
                ["article-err"] = {
                    error = {
                        kind = "timeout",
                        retryable = true,
                    },
                },
            },
        }
        local report = reconciler:run()
        assert(report.remote_errors == 1)
        assert(report.unverified_retained == 1)
        assert(report.pending_after == 1)
        assert(#cleared == 0)
    end

    do
        local rows = {}
        local files = {}
        local remote = {}
        for i = 1, 3 do
            local id = "article-" .. tostring(i)
            local path = "/" .. id .. ".html"
            rows[#rows + 1] = {
                reader_id = id,
                category = "article",
                local_format = "html",
                local_path = path,
                is_local_present = true,
                content_refresh_pending = true,
                content_refresh_remote_updated_at = "u2",
            }
            files[path] = "<p>Same</p>"
            remote[id] = {
                id = id,
                updated_at = "u2",
                html_content = "<p>Same</p>",
            }
        end
        local reconciler, _, cleared, gets = newHarness{
            rows = rows,
            files = files,
            remote = remote,
            max_article_checks = 2,
        }
        local report = reconciler:run()
        assert(report.article_checked == 2)
        assert(report.metadata_only_acknowledged == 2)
        assert(report.unverified_retained == 1)
        assert(report.pending_after == 1)
        assert(#cleared == 2)
        assert(#gets == 2)
    end
end
