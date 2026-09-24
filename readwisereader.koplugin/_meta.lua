-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content with KOReader. Experimental 0.1.37 discovers new highlights across all locally-present managed Reader documents, queues them durably first, and requires a read-only Readwise reachability probe before any remote write.]]),
}
