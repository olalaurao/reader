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

    assert(Installer._classifyOpenError("Too many open files") == "too_many_open_files")
    assert(Installer._classifyOpenError("File name too long") == "name_too_long")
    assert(Installer._classifyOpenError("Read-only file system") == "read_only")
    assert(Installer._classifyOpenError("Permission denied") == "permission")
    assert(Installer._classifyOpenError("something else") == "other")
end
