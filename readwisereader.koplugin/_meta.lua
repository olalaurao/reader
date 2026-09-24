-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content with KOReader. Experimental 0.1.43 adds durable, idempotent Finished-to-Archive synchronization after the canonical KOReader Finished signal passed physically on the target PW3.]]),
}
