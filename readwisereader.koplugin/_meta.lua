-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content and KOReader annotations. v1.2.0-alpha.4 fixes the shared importer format gate so the one-item sidecar-only Reader-to-KOReader PDF highlight flow can reach its validated PDF path.]]),
}
