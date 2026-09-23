-- SPDX-License-Identifier: AGPL-3.0-only

local Installer = {}
Installer.__index = Installer

local function defaultDependencies()
    local ffiUtil = require("ffi/util")
    local lfs = require("libs/libkoreader-lfs")
    local util = require("util")
    return {
        make_path = util.makePath,
        open_file = io.open,
        rename = os.rename,
        remove = os.remove,
        attributes = lfs.attributes,
        fsync_opened_file = ffiUtil.fsyncOpenedFile,
        fsync_directory = ffiUtil.fsyncDirectory,
    }
end

function Installer:new(options)
    options = options or {}
    local deps = options.deps or defaultDependencies()
    return setmetatable({
        deps = deps,
    }, self)
end

local function classifyOpenError(message)
    local text = string.lower(tostring(message or ""))
    if text:find("no space left", 1, true) or text:find("enospc", 1, true) then
        return "no_space"
    elseif text:find("file name too long", 1, true)
        or text:find("filename too long", 1, true)
        or text:find("enametoolong", 1, true) then
        return "name_too_long"
    elseif text:find("too many open files", 1, true) or text:find("emfile", 1, true) then
        return "too_many_open_files"
    elseif text:find("read-only file system", 1, true) or text:find("erofs", 1, true) then
        return "read_only"
    elseif text:find("permission denied", 1, true) or text:find("eacces", 1, true) then
        return "permission"
    elseif text:find("invalid argument", 1, true) or text:find("einval", 1, true) then
        return "invalid_name"
    end
    return "other"
end

local function ioError(stage, message, detail)
    return {
        kind = "io",
        stage = stage,
        detail = detail,
        retryable = true,
        message = message,
    }
end

function Installer:fileExists(path)
    return self.deps.attributes(path, "mode") == "file"
end

function Installer:install(content, final_path)
    assert(type(content) == "string", "content is required")
    assert(type(final_path) == "string" and final_path ~= "", "final_path is required")

    if self:fileExists(final_path) then
        return nil, {
            kind = "exists",
            retryable = false,
            message = "Destination already exists; it was not overwritten.",
        }
    end

    local directory = final_path:match("^(.*)/[^/]+$")
    if not directory or directory == "" then
        return nil, ioError("path", "Destination directory is invalid.")
    end

    local made, make_err = self.deps.make_path(directory)
    if not made then
        return nil, ioError("mkdir", "Could not create the Readwise document directory: " .. tostring(make_err or "unknown error"))
    end

    local temp_path = final_path .. ".tmp"
    if self.deps.attributes(temp_path, "mode") ~= nil then
        self.deps.remove(temp_path)
    end

    local file, open_err = self.deps.open_file(temp_path, "wb")
    if not file then
        return nil, ioError(
            "open",
            "Could not create temporary document.",
            classifyOpenError(open_err)
        )
    end

    local write_ok, write_err = file:write(content)
    if not write_ok then
        pcall(file.close, file)
        self.deps.remove(temp_path)
        return nil, ioError("write", "Could not write temporary document: " .. tostring(write_err or "unknown error"))
    end

    local sync_ok, sync_err = pcall(self.deps.fsync_opened_file, file)
    local close_ok, close_err = pcall(file.close, file)
    if not sync_ok or not close_ok then
        self.deps.remove(temp_path)
        return nil, ioError("flush", "Could not safely flush temporary document: " .. tostring(sync_err or close_err or "unknown error"))
    end

    local size = self.deps.attributes(temp_path, "size")
    if tonumber(size) ~= #content or #content == 0 then
        self.deps.remove(temp_path)
        return nil, ioError("size", "Temporary document failed size validation.")
    end

    local renamed, rename_err = self.deps.rename(temp_path, final_path)
    if not renamed then
        self.deps.remove(temp_path)
        return nil, ioError("rename", "Could not atomically install document: " .. tostring(rename_err or "unknown error"))
    end

    local durable, durability_err = pcall(self.deps.fsync_directory, final_path)
    return {
        path = final_path,
        durability_warning = durable and nil or tostring(durability_err or "directory fsync failed"),
    }
end

Installer._classifyOpenError = classifyOpenError

return Installer
