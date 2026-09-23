-- SPDX-License-Identifier: AGPL-3.0-only

local Identity = {}

function Identity.markerFor(local_annotation_id)
    return "KOReader Readwise Reader:" .. tostring(local_annotation_id)
end

function Identity.createQueueKey(local_annotation_id)
    return "create_highlight:" .. tostring(local_annotation_id)
end

return Identity
