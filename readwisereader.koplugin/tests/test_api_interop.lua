-- SPDX-License-Identifier: AGPL-3.0-only

local ApiInterop = require("sync/api_interop")

local function newMeta()
    local data = {}
    return {
        data = data,
        get = function(_, key) return data[key] end,
        set = function(_, key, value) data[key] = value end,
        setMany = function(_, values)
            for key, value in pairs(values) do data[key] = value end
        end,
        delete = function(_, key) data[key] = nil end,
    }
end

return function()
    do
        local meta = newMeta()
        local remote = {
            note = ApiInterop.INITIAL_NOTE,
            tags = { ApiInterop.TAG },
            child_deleted = false,
            parent_deleted = false,
        }
        local reader = {
            saveDocument = function(_, payload)
                assert(payload.html:find(ApiInterop.PHRASE, 1, true))
                return { id = "parent-1", status = 201 }
            end,
            getDocument = function(_, id, with_html)
                if id == "parent-1" then
                    if remote.parent_deleted then
                        return nil, { kind = "not_found", retryable = false }
                    end
                    return {
                        id = id,
                        category = "article",
                        html_content = with_html and ("<p>" .. ApiInterop.PHRASE .. "</p>") or nil,
                    }
                end
                if id == "child-1" then
                    if remote.child_deleted then
                        return nil, { kind = "not_found", retryable = false }
                    end
                    return {
                        id = id,
                        category = "highlight",
                        parent_id = "parent-1",
                        notes = remote.note,
                        tags = remote.tags,
                        highlight_offset = 12,
                        highlight_location = "dom-a,dom-b",
                    }
                end
                return nil, { kind = "not_found", retryable = false }
            end,
            createHighlight = function(_, parent_id, content, note, tags)
                assert(parent_id == "parent-1")
                assert(content == ApiInterop.PHRASE)
                assert(note == ApiInterop.INITIAL_NOTE)
                assert(tags[1] == ApiInterop.TAG)
                return { id = "child-1", status = 201 }
            end,
            updateDocument = function(_, id, patch)
                assert(id == "child-1")
                remote.note = patch.notes
                remote.tags = patch.tags
                return { id = id, status = 200 }
            end,
            deleteDocument = function(_, id)
                if id == "child-1" then remote.child_deleted = true end
                if id == "parent-1" then remote.parent_deleted = true end
                return true
            end,
        }
        local readwise = {
            listHighlights = function()
                return {
                    results = {
                        {
                            id = 77,
                            external_id = "child-1",
                            book_id = 88,
                            text = ApiInterop.PHRASE,
                            note = remote.note,
                            color = "yellow",
                        },
                    },
                }
            end,
            exportUpdated = function()
                error("direct external_id mapping should avoid export fallback")
            end,
            updateHighlight = function(_, id, patch)
                assert(id == 77)
                assert(patch.note == ApiInterop.V2_NOTE)
                assert(patch.color == "green")
                remote.note = patch.note
                return {
                    id = id,
                    note = patch.note,
                    color = patch.color,
                    external_id = "child-1",
                }
            end,
            getHighlight = function()
                if remote.child_deleted then
                    return nil, { kind = "client", status = 404, retryable = false }
                end
                return { id = 77, external_id = "child-1" }
            end,
            deleteHighlight = function()
                error("v2 delete should not be needed when v3 delete propagates")
            end,
        }
        local interop = ApiInterop:new{
            reader = reader,
            readwise = readwise,
            meta = meta,
            sleep = function() end,
            utc_now = function() return "2026-09-23T15:00:00Z" end,
            stamp = function() return "123456" end,
        }

        local created = assert(interop:create())
        assert(created.v3_parent_matches == true)
        assert(created.v3_note_matches == true)
        assert(created.v3_tag_matches == true)
        assert(created.highlight_offset_present == true)
        assert(meta.data[ApiInterop.KEYS.stage] == "created")

        local probed = assert(interop:probeAndUpdateV3())
        assert(probed.v2_id == 77)
        assert(probed.mapping_method == "highlight.external_id")
        assert(probed.v2_external_id_matches_reader_child == true)
        assert(probed.v3_note_update_verified == true)
        assert(probed.v3_tag_update_verified == true)
        assert(remote.note == ApiInterop.V3_NOTE)
        assert(meta.data[ApiInterop.KEYS.v2_id] == "77")

        local v2 = assert(interop:updateViaV2())
        assert(v2.v2_note_update_response_matches == true)
        assert(v2.v2_color_update_response_matches == true)
        assert(v2.v3_saw_v2_note_update == true)
        assert(remote.note == ApiInterop.V2_NOTE)

        local deleted = assert(interop:deleteAndCleanup())
        assert(deleted.v3_delete_success == true)
        assert(deleted.v3_missing_after_delete == true)
        assert(deleted.v2_missing_after_v3_delete == true)
        assert(deleted.v2_delete_used == false)
        assert(deleted.parent_cleanup_success == true)
        assert(remote.parent_deleted == true)
        assert(meta.data[ApiInterop.KEYS.stage] == nil)
    end

    do
        local meta = newMeta()
        meta:setMany{
            [ApiInterop.KEYS.stage] = "created",
            [ApiInterop.KEYS.started_at] = "2026-09-23T15:00:00Z",
            [ApiInterop.KEYS.parent_id] = "parent-1",
            [ApiInterop.KEYS.highlight_id] = "child-1",
        }
        local reader = {
            getDocument = function(_, id)
                return {
                    id = id,
                    category = "highlight",
                    parent_id = "parent-1",
                    notes = ApiInterop.INITIAL_NOTE,
                    tags = { ApiInterop.TAG },
                }
            end,
            updateDocument = function()
                error("ambiguous mapping must block before update")
            end,
        }
        local readwise = {
            listHighlights = function() return { results = {} } end,
            exportUpdated = function()
                return {
                    results = {
                        {
                            source = "reader",
                            external_id = "parent-1",
                            user_book_id = 88,
                            highlights = {
                                {
                                    id = 77,
                                    external_id = nil,
                                    text = ApiInterop.PHRASE,
                                    note = ApiInterop.INITIAL_NOTE,
                                },
                            },
                        },
                    },
                }
            end,
        }
        local interop = ApiInterop:new{
            reader = reader,
            readwise = readwise,
            meta = meta,
            sleep = function() end,
        }
        local result, err = interop:probeAndUpdateV3()
        assert(result == nil)
        assert(err.kind == "gate8_mapping_ambiguous")
        assert(meta:get(ApiInterop.KEYS.v2_id) == nil)
    end

    do
        local meta = newMeta()
        meta:setMany{
            [ApiInterop.KEYS.stage] = "created",
            [ApiInterop.KEYS.started_at] = "2026-09-23T15:00:00Z",
            [ApiInterop.KEYS.parent_id] = "parent-1",
            [ApiInterop.KEYS.highlight_id] = "child-1",
            [ApiInterop.KEYS.v2_id] = "77",
        }
        local v2_deleted = false
        local parent_deleted = false
        local interop = ApiInterop:new{
            reader = {
                deleteDocument = function(_, id)
                    if id == "parent-1" then parent_deleted = true end
                    return true
                end,
                getDocument = function()
                    return nil, { kind = "not_found", retryable = false }
                end,
            },
            readwise = {
                getHighlight = function()
                    return { id = 77, external_id = "child-1", is_deleted = false }
                end,
                deleteHighlight = function()
                    v2_deleted = true
                    return true
                end,
            },
            meta = meta,
            sleep = function() end,
        }
        local report = assert(interop:deleteAndCleanup())
        assert(report.v2_still_visible_after_v3_delete == true)
        assert(report.v2_delete_used == true)
        assert(report.v2_delete_success == true)
        assert(v2_deleted == true)
        assert(parent_deleted == true)
    end

    do
        local meta = newMeta()
        meta:setMany{
            [ApiInterop.KEYS.stage] = "parent_created",
            [ApiInterop.KEYS.started_at] = "2026-09-23T15:00:00Z",
            [ApiInterop.KEYS.parent_id] = "parent-only",
        }
        local deleted_parent
        local interop = ApiInterop:new{
            reader = {
                deleteDocument = function(_, id)
                    deleted_parent = id
                    return true
                end,
            },
            readwise = {
                deleteHighlight = function()
                    error("no v2 highlight exists for parent-only recovery")
                end,
            },
            meta = meta,
            sleep = function() end,
        }
        local report = assert(interop:cleanup())
        assert(report.parent_cleanup == true)
        assert(report.highlight_cleanup == true)
        assert(report.v2_cleanup == true)
        assert(report.cleared == true)
        assert(deleted_parent == "parent-only")
        assert(meta:get(ApiInterop.KEYS.parent_id) == nil)
    end

end
