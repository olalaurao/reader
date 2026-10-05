-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content and KOReader annotations. v1.2.3 refreshes KOReader/SimpleUI folder caches after sync so files already present on disk become visible immediately in Readwise folders without restarting KOReader.]]),
}
