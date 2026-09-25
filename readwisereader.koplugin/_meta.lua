-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content and KOReader annotations. Experimental 1.1.0-alpha.1 adds a read-only Reader-to-KOReader highlight locator probe for managed EPUB/HTML documents.]]),
}
