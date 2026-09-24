-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content with KOReader. Experimental 0.1.40 narrows the Gate 13 reconnect hard-exit boundary with bounded parent-content reads, metadata-vs-HTML stages, sanitized durable partial snapshots, and no text matching or remote writes.]]),
}
