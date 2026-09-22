-- SPDX-License-Identifier: AGPL-3.0-only

local Hash = {}

function Hash.digest(value)
    local md5 = require("ffi/sha2").md5
    local update = md5()
    update(value or "")
    return update()
end

return Hash
