-- SPDX-License-Identifier: AGPL-3.0-only

return {
    VERSION = "0.1.46",
    SETTINGS_FILENAME = "readwisereader.lua",
    DEFAULT_DOWNLOAD_ROOT = "/mnt/us/documents/Readwise",
    DEFAULT_SYNC_LOCATIONS = { "new", "later" },
    DEFAULT_SYNC_CATEGORIES = { "article" },
    DEFAULT_DOWNLOAD_IMAGES = true,
    MAX_IMAGE_BYTES = 2 * 1024 * 1024,
    MAX_ARTICLE_IMAGE_BYTES = 8 * 1024 * 1024,
    MAX_IMAGES_PER_ARTICLE = 20,
    MAX_RAW_SOURCE_BYTES = 64 * 1024 * 1024,
    -- Processed Reader HTML is held in Lua memory before CRengine opens it.
    -- Keep a conservative per-document ceiling and cap JSON LIST/get bodies
    -- separately so pathological responses fail before unbounded accumulation.
    MAX_PROCESSED_HTML_BYTES = 8 * 1024 * 1024,
    MAX_READER_DOCUMENT_RESPONSE_BYTES = 10 * 1024 * 1024,
    MAX_READER_CONTENT_PAGE_BYTES = 16 * 1024 * 1024,
    GATE13_PARENT_PROBE_MAX_BYTES = 1 * 1024 * 1024,
    GATE15_LOCAL_HTML_PROBE_MAX_BYTES = 4 * 1024 * 1024,
    GATE15_REMOTE_HTML_PROBE_MAX_BYTES = 4 * 1024 * 1024,
    CONTENT_REFRESH_RECONCILE_MAX_PER_SYNC = 5,
    MIN_RAW_SOURCE_FREE_BYTES = 128 * 1024 * 1024,
    AUTH_URL = "https://readwise.io/api/v2/auth/",
    READER_LIST_URL = "https://readwise.io/api/v3/list/",
    READER_TAG_LIST_URL = "https://readwise.io/api/v3/tags/",
    READER_SAVE_URL = "https://readwise.io/api/v3/save/",
    READER_UPDATE_URL_PREFIX = "https://readwise.io/api/v3/update/",
    READER_DELETE_URL_PREFIX = "https://readwise.io/api/v3/delete/",
    READWISE_HIGHLIGHTS_URL = "https://readwise.io/api/v2/highlights/",
    READWISE_EXPORT_URL = "https://readwise.io/api/v2/export/",
    -- LIST is documented at 20 requests/minute. 3.1s leaves a small safety margin.
    READER_LIST_MIN_INTERVAL_SECONDS = 3.1,
    READER_LIST_MAX_RATE_LIMIT_RETRIES = 2,
    READER_LIST_RATE_LIMIT_BACKOFF_SECONDS = { 5, 15 },
}
