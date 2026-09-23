-- SPDX-License-Identifier: AGPL-3.0-only

local FirstArticle = require("sync/first_article")

local function newCoordinator(options)
    options = options or {}
    local rows = {}
    local local_states = {}
    local installs = {}
    local metadata = {}

    local coordinator = FirstArticle:new{
        reader = options.reader or {
            listDocuments = function(_, request)
                return {
                    results = {
                        { id = "a", title = "A", author = "Author", category = "article" },
                        { id = "child", title = "Child", category = "article", parent_id = "a" },
                        { id = "pdf", title = "PDF", category = "pdf" },
                    },
                }
            end,
            getDocument = function(_, id)
                return {
                    id = id,
                    title = "Olá / mundo",
                    author = "Autora",
                    category = "article",
                    location = "later",
                    updated_at = "2026-09-22T20:00:00Z",
                    html_content = "<p>Conteúdo 🧠</p>",
                }
            end,
        },
        repository = {
            getById = function(_, id)
                return rows[id]
            end,
            upsertRemote = function(_, document)
                rows[document.id] = rows[document.id] or { reader_id = document.id }
                return rows[document.id]
            end,
            setLocalState = function(_, id, state)
                local_states[id] = state
                rows[id] = rows[id] or { reader_id = id }
                for key, value in pairs(state) do
                    rows[id][key] = value
                end
            end,
        },
        html = {
            build = function(document)
                return "<html>" .. document.html_content .. "</html>"
            end,
        },
        images = options.images,
        raw_source = options.raw_source,
        filenames = options.filenames or {
            build = function(_, id, extension)
                return "article--rw-" .. id .. "." .. (extension or "html")
            end,
            joinUnderRoot = function(root, subdir, filename)
                return root .. "/" .. subdir .. "/" .. filename
            end,
            assetDirectory = function(id)
                return ".rw-assets-" .. id
            end,
        },
        installer = options.installer or {
            install = function(_, content, path)
                installs[#installs + 1] = { content = content, path = path }
                return { path = path }
            end,
        },
        hasher = {
            digest = function(value)
                return "hash-" .. tostring(#value)
            end,
        },
        koreader_documents = {
            writeMetadata = function(_, path, document)
                metadata[#metadata + 1] = { path = path, id = document.id }
                return true
            end,
        },
        download_root = "/root/Readwise",
        now = function() return 123 end,
        file_exists = options.file_exists or function() return false end,
    }

    return coordinator, rows, local_states, installs, metadata
end

return function()
    do
        local captured
        local coordinator = newCoordinator{
            reader = {
                listDocuments = function(_, request)
                    captured = request
                    return {
                        results = {
                            { id = "a", title = "A", author = "Author", category = "article" },
                            { id = "child", title = "Child", category = "article", parent_id = "a" },
                        },
                    }
                end,
            },
        }
        local candidates, err = coordinator:listCandidates(25)
        assert(err == nil)
        assert(#candidates == 1)
        assert(candidates[1].id == "a")
        assert(captured.category == "article")
        assert(captured.limit == 25)
        assert(captured.with_html_content == false)
        assert(captured.with_raw_source_url == false)
    end

    do
        local coordinator, rows, states, installs, metadata = newCoordinator()
        local document, fetch_err = coordinator:fetchDocument("article-1")
        assert(fetch_err == nil)
        local result, install_err = coordinator:installDocument(document)
        assert(install_err == nil)
        assert(result.path == "/root/Readwise/Articles/article--rw-article-1.html")
        assert(#installs == 1)
        assert(installs[1].content:find("Conteúdo 🧠", 1, true))
        assert(states["article-1"].local_format == "html")
        assert(states["article-1"].download_strategy == "reader_html")
        assert(states["article-1"].is_local_present == true)
        assert(states["article-1"].last_materialized_at == 123)
        assert(rows["article-1"].local_path == result.path)
        assert(#metadata == 1)
        assert(metadata[1].id == "article-1")
    end

    do
        local localized_args
        local coordinator, _, states, installs = newCoordinator{
            images = {
                localize = function(_, document, absolute_dir, relative_dir)
                    localized_args = {
                        absolute_dir = absolute_dir,
                        relative_dir = relative_dir,
                    }
                    return '<p>before</p><img src="' .. relative_dir .. '/img-001.png"><p>after</p>', {
                        downloaded = 1,
                        reused = 0,
                        failed = 0,
                        skipped = 0,
                        bytes = 123,
                        new_paths = { absolute_dir .. "/img-001.png" },
                    }
                end,
                cleanup = function()
                    error("successful HTML install must not cleanup images")
                end,
            },
        }
        local result, err = coordinator:installDocument{
            id = "with-images",
            title = "Image article",
            category = "article",
            location = "new",
            updated_at = "u1",
            html_content = '<img src="https://example.com/image.png">',
        }
        assert(err == nil)
        assert(result.image_report.downloaded == 1)
        assert(localized_args.relative_dir == ".rw-assets-with-images")
        assert(localized_args.absolute_dir == "/root/Readwise/Articles/.rw-assets-with-images")
        assert(#installs == 1)
        assert(installs[1].content:find('.rw%-assets%-with%-images/img%-001%.png'))
        assert(states["with-images"].is_local_present == true)
    end

    do
        local raw_calls = {}
        local coordinator, rows, states, installs, metadata = newCoordinator{
            raw_source = {
                download = function(_, document, path)
                    raw_calls[#raw_calls + 1] = { id = document.id, path = path }
                    return {
                        path = path,
                        bytes = 321,
                        format = "pdf",
                        download_strategy = "reader_raw_source",
                    }
                end,
                isFallbackEligible = function() return false end,
            },
        }
        local result, err = coordinator:installDocument{
            id = "pdf-1",
            title = "Original PDF",
            category = "pdf",
            location = "later",
            updated_at = "u2",
            raw_source_url = "https://signed.example/pdf",
            html_content = "<p>fallback</p>",
        }
        assert(err == nil)
        assert(result.raw_source_used == true)
        assert(result.raw_fallback_used == false)
        assert(result.raw_bytes == 321)
        assert(result.path == "/root/Readwise/PDFs/article--rw-pdf-1.pdf")
        assert(#raw_calls == 1)
        assert(#installs == 0)
        assert(states["pdf-1"].local_format == "pdf")
        assert(states["pdf-1"].download_strategy == "reader_raw_source")
        assert(rows["pdf-1"].local_path == result.path)
        assert(#metadata == 1)
    end

    do
        local coordinator, _, states, installs = newCoordinator{
            raw_source = {
                download = function()
                    return nil, {
                        kind = "raw_unavailable",
                        retryable = false,
                        message = "no raw source",
                    }
                end,
                isFallbackEligible = function(_, err)
                    return err and err.kind == "raw_unavailable"
                end,
            },
        }
        local result, err = coordinator:installDocument{
            id = "epub-fallback",
            title = "EPUB fallback",
            category = "epub",
            location = "new",
            updated_at = "u3",
            html_content = "<p>Readable fallback</p>",
        }
        assert(err == nil)
        assert(result.raw_source_used == false)
        assert(result.raw_fallback_used == true)
        assert(result.path == "/root/Readwise/EPUBs/article--rw-epub-fallback.html")
        assert(#installs == 1)
        assert(installs[1].content:find("Readable fallback", 1, true))
        assert(states["epub-fallback"].local_format == "html")
        assert(states["epub-fallback"].download_strategy == "reader_html_fallback")
    end

    do
        local calls = {}
        local filenames = {
            build = function(title, id)
                if title == nil then
                    return "Untitled--rw-" .. id .. ".html"
                end
                return "problematic--rw-" .. id .. ".html"
            end,
            joinUnderRoot = function(root, subdir, filename)
                return root .. "/" .. subdir .. "/" .. filename
            end,
        }
        local installer = {
            install = function(_, content, path)
                calls[#calls + 1] = path
                if #calls == 1 then
                    return nil, {
                        kind = "io",
                        stage = "open",
                        detail = "invalid_name",
                        retryable = true,
                    }
                end
                return { path = path }
            end,
        }
        local coordinator, rows, states = newCoordinator{
            filenames = filenames,
            installer = installer,
        }
        local result, err = coordinator:installDocument{
            id = "bad-name",
            title = "problematic",
            category = "article",
            location = "new",
            updated_at = "u1",
            html_content = "<p>ok</p>",
        }
        assert(err == nil)
        assert(#calls == 2)
        assert(calls[1]:find("problematic", 1, true))
        assert(calls[2]:find("Untitled", 1, true))
        assert(result.path == calls[2])
        assert(states["bad-name"].local_path == calls[2])
        assert(rows["bad-name"].local_path == calls[2])
    end

    do
        local exists = true
        local coordinator, rows, _, installs = newCoordinator{
            file_exists = function(path)
                return exists and path == "/root/existing.html"
            end,
        }
        rows["existing"] = {
            reader_id = "existing",
            local_path = "/root/existing.html",
            is_local_present = true,
        }
        assert(coordinator:getExistingPath("existing") == "/root/existing.html")
        local result = coordinator:installDocument{
            id = "existing",
            category = "article",
            html_content = "<p>new remote content</p>",
        }
        assert(result.path == "/root/existing.html")
        assert(result.existing == true)
        assert(#installs == 0)
    end
end
