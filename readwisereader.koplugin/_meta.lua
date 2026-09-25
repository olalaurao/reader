-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content and KOReader annotations. v1.2.0-alpha.7 aligns persisted PDF annotation verification with KOReader's native paging identity (datetime/page/pos0/pos1) and adds staged sidecar diagnostics.]]),
}
