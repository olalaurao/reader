-- SPDX-License-Identifier: AGPL-3.0-only

local _ = require("gettext")

return {
    name = "readwisereader",
    fullname = _("Readwise Reader"),
    description = _([[Synchronize Readwise Reader content with KOReader. Experimental 0.1.39 adds a read-only Gate 13 reconnect diagnostic that snapshots the durable create queue, probes Reader from the subprocess, checks remote markers and parent text matches, and records only a coarse durable stage if the child exits without a result.]]),
}
