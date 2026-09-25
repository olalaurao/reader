-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content with KOReader. Experimental 0.1.47 hardens large libraries, low-storage failures, malformed/oversized content, Unicode, rate limits, network recovery, restart persistence, rollback compatibility and log redaction for Gate 16.]]),
}
