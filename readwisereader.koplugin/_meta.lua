-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content with KOReader. Experimental 0.1.27 fixes Gate 12 note updates for safely-linked legacy highlights while keeping remote deletion strict.]]),
}
