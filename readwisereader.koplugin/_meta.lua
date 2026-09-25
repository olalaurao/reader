-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content and KOReader annotations. Experimental 1.1.0-alpha.2 adds one-item Reader-to-KOReader highlight import for managed EPUB/HTML after exact XPointer validation.]]),
}
