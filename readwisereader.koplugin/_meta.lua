-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content with KOReader. Experimental 0.1.46 adds Gate 15 Q2 metadata-only revision acknowledgement after physical article safety validation, while changed/unverified/raw content remains pending and local bytes are never replaced.]]),
}
