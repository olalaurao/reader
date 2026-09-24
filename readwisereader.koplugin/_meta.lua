-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content with KOReader. Experimental 0.1.38 hardens managed-document backlog discovery against real-device sidecar/query exceptions, preserves per-document progress, and keeps the read-only Readwise reachability gate before any remote write.]]),
}
