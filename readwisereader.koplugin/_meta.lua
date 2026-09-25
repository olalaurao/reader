-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content and KOReader annotations. Experimental 1.1.0-alpha.3 adds bounded idempotent Reader-to-KOReader historical highlight import for the currently open managed EPUB/HTML, integrated with manual Sync.]]),
}
