-- SPDX-License-Identifier: AGPL-3.0-only

local Worker = require("sync/content_refresh_probe_worker")

return function()
    local path = os.tmpname()
    local file = assert(io.open(path, "wb"))
    file:write("abcdef")
    file:close()

    local value, err = Worker._readFile(path, 6)
    assert(err == nil)
    assert(value == "abcdef")

    local too_large, size_err = Worker._readFile(path, 5)
    assert(too_large == nil)
    assert(size_err.kind == "too_large")

    os.remove(path)

    local missing, missing_err = Worker._readFile(path, 10)
    assert(missing == nil)
    assert(missing_err.kind == "io")
end
