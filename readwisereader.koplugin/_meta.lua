-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content with KOReader. Experimental 0.1.30 normalizes invisible note whitespace for safe conflict comparison on top of deterministic Readwise v2 mapping.]]),
}
