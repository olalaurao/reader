-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content and KOReader annotations. v1.2.1 raises historical import batches to 50 highlights for EPUB/HTML and 5 for PDF while preserving conservative pre-Sync deduplication.]]),
}
