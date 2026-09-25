-- SPDX-License-Identifier: AGPL-3.0-only

local Installer = require("content/installer")

local function fakeDeps(existing)
    local files = existing or {}
    local dirs = {}
    local syncs = {}
    local function newFile(path)
        local buffer = ""
        local closed = false
        return {
            write = function(_, content)
                if closed then return nil, "closed" end
                buffer = buffer .. content
                files[path] = buffer
                return true
            end,
            close = function()
                closed = true
                return true
            end,
            _path = path,
        }
    end

    return {
        files = files,
        dirs = dirs,
        syncs = syncs,
        deps = {
            make_path = function(path)
                dirs[path] = true
                return true
            end,
            open_file = function(path)
                files[path] = ""
                return newFile(path)
            end,
            rename = function(from, to)
                if files[from] == nil then return nil, "missing temp" end
                files[to] = files[from]
                files[from] = nil
                return true
            end,
            remove = function(path)
                files[path] = nil
                return true
            end,
            attributes = function(path, attr)
                if attr == "mode" then
                    return files[path] ~= nil and "file" or nil
                elseif attr == "size" then
                    return files[path] and #files[path] or nil
                end
            end,
            fsync_opened_file = function(file)
                syncs[#syncs + 1] = "file:" .. file._path
            end,
            fsync_directory = function(path)
                syncs[#syncs + 1] = "dir:" .. path
            end,
        },
    }
end

return function()
    do
        local fake = fakeDeps()
        local installer = Installer:new{ deps = fake.deps }
        local result, err = installer:install("<html>ok</html>", "/root/Articles/doc.html")
        assert(err == nil)
        assert(result.path == "/root/Articles/doc.html")
        assert(fake.files["/root/Articles/doc.html"] == "<html>ok</html>")
        assert(fake.files["/root/Articles/doc.html.tmp"] == nil)
        assert(fake.dirs["/root/Articles"])
        assert(#fake.syncs == 2)
    end

    do
        local fake = fakeDeps({ ["/root/Articles/doc.html"] = "keep me" })
        local installer = Installer:new{ deps = fake.deps }
        local result, err = installer:install("new", "/root/Articles/doc.html")
        assert(result == nil)
        assert(err.kind == "exists")
        assert(fake.files["/root/Articles/doc.html"] == "keep me")
    end

    do
        local fake = fakeDeps()
        local installer = Installer:new{ deps = fake.deps }
        local validated = false
        local result, err = installer:installStream(
            "/root/Books/doc.pdf",
            function(sink)
                assert(sink("%PDF-1.7\n") == 1)
                assert(sink("body") == 1)
                return { status = 200, headers = { ["Content-Type"] = "application/pdf" } }
            end,
            function(temp_path, bytes, response)
                validated = true
                assert(temp_path == "/root/Books/doc.pdf.tmp")
                assert(bytes == #"%PDF-1.7\nbody")
                assert(response.status == 200)
                return true
            end
        )
        assert(err == nil)
        assert(result.path == "/root/Books/doc.pdf")
        assert(result.bytes == #"%PDF-1.7\nbody")
        assert(fake.files["/root/Books/doc.pdf"] == "%PDF-1.7\nbody")
        assert(fake.files["/root/Books/doc.pdf.tmp"] == nil)
        assert(validated == true)
    end

    do
        local fake = fakeDeps()
        local installer = Installer:new{ deps = fake.deps }
        local result, err = installer:installStream(
            "/root/Books/bad.pdf",
            function(sink)
                assert(sink("not a pdf") == 1)
                return { status = 200 }
            end,
            function()
                return nil, {
                    kind = "content",
                    stage = "validate",
                    retryable = false,
                    message = "bad format",
                }
            end
        )
        assert(result == nil)
        assert(err.kind == "content")
        assert(fake.files["/root/Books/bad.pdf"] == nil)
        assert(fake.files["/root/Books/bad.pdf.tmp"] == nil)
    end

    do
        local fake = fakeDeps()
        fake.deps.open_file = function()
            return nil, "No space left on device"
        end
        local installer = Installer:new{ deps = fake.deps }
        local result, err = installer:install("new", "/root/Articles/doc.html")
        assert(result == nil)
        assert(err.kind == "io")
        assert(err.retryable == true)
        assert(err.stage == "open")
        assert(err.detail == "no_space")
    end

    do
        -- Processed HTML writes can hit ENOSPC after the temporary file has
        -- already opened. Preserve the error class, remove the temp file and
        -- never expose a partial final document.
        local fake = fakeDeps()
        fake.deps.open_file = function(path)
            fake.files[path] = ""
            return {
                write = function()
                    return nil, "No space left on device"
                end,
                close = function() return true end,
                _path = path,
            }
        end
        local installer = Installer:new{ deps = fake.deps }
        local result, err = installer:install(
            "<html><body>partial</body></html>",
            "/root/Articles/full.html"
        )
        assert(result == nil)
        assert(err.kind == "io")
        assert(err.stage == "write")
        assert(err.detail == "no_space")
        assert(err.retryable == true)
        assert(fake.files["/root/Articles/full.html"] == nil)
        assert(fake.files["/root/Articles/full.html.tmp"] == nil)
    end

    do
        -- Storage can disappear between a successful preflight/open and the
        -- actual streamed write. ENOSPC must remain retryable, remove the temp
        -- file and never expose a partial final document.
        local fake = fakeDeps()
        fake.deps.open_file = function(path)
            fake.files[path] = ""
            return {
                write = function()
                    return nil, "No space left on device"
                end,
                close = function() return true end,
                _path = path,
            }
        end
        local installer = Installer:new{ deps = fake.deps }
        local result, err = installer:installStream(
            "/root/Books/full.pdf",
            function(sink)
                local ok, write_err = sink("%PDF-1.7\npartial")
                if not ok then
                    return nil, {
                        kind = "io",
                        stage = "write",
                        retryable = true,
                        message = tostring(write_err),
                    }
                end
                return { status = 200 }
            end
        )
        assert(result == nil)
        assert(err.kind == "io")
        assert(err.stage == "write")
        assert(err.detail == "no_space")
        assert(fake.files["/root/Books/full.pdf"] == nil)
        assert(fake.files["/root/Books/full.pdf.tmp"] == nil)
    end

    assert(Installer._classifyOpenError("Too many open files") == "too_many_open_files")
    assert(Installer._classifyOpenError("File name too long") == "name_too_long")
    assert(Installer._classifyOpenError("Read-only file system") == "read_only")
    assert(Installer._classifyOpenError("Permission denied") == "permission")
    assert(Installer._classifyOpenError("something else") == "other")
end
