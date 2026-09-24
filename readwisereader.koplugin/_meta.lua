-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content with KOReader. Experimental 0.1.33 adds durable offline annotation queueing, reboot recovery, backoff and safe retry reconciliation for Gate 13.]]),
}
