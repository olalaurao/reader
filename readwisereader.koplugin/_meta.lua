-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content and KOReader annotations. v1.1.0-rc.1 adds bounded, pre-Sync Reader-to-KOReader historical highlight import for the currently open managed rolling EPUB/HTML with duplicate-safe reconciliation.]]),
}
