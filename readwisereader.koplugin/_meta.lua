-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content with KOReader. Experimental 0.1.41 validates annotation text matching on-device with native NFC FFI removed from the matcher, pure-Lua conservative Latin composition, granular durable match stages, bounded parent reads, and no remote writes.]]),
}
