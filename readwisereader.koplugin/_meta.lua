-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content and KOReader annotations. v1.2.2 makes document sync auditable and recovers filter-eligible documents omitted by the bulk content LIST through safe direct-ID reconciliation.]]),
}
