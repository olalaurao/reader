-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content and KOReader annotations. v1.2.0-alpha.8 normalizes generated PDF paging coordinates to KOReader's persisted numeric representation before save and makes rollback reference-safe.]]),
}
