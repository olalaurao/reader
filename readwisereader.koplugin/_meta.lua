-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content and KOReader annotations. v1.2.0-alpha.6 verifies freshly-flushed PDF sidecars by opening the current metadata file directly, avoiding stale .old backup candidates during durable Reader-link proof.]]),
}
