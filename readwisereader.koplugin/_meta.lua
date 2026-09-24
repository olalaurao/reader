-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content with KOReader. Experimental 0.1.44 starts Gate 15 with durable content-refresh deferral and a read-only sidecar/content-comparison diagnostic; existing local content is never auto-replaced.]]),
}
