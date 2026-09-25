-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content and KOReader annotations. v1.2.0 adds physically-validated Reader → KOReader historical highlight/note import for managed rolling documents and original PDFs, with conservative pre-Sync deduplication.]]),
}
