-- SPDX-License-Identifier: AGPL-3.0-only

return {
    VERSION = "0.1.12",
    SETTINGS_FILENAME = "readwisereader.lua",
    DEFAULT_DOWNLOAD_ROOT = "/mnt/us/documents/Readwise",
    DEFAULT_SYNC_LOCATIONS = { "new", "later" },
    DEFAULT_SYNC_CATEGORIES = { "article" },
    AUTH_URL = "https://readwise.io/api/v2/auth/",
    READER_LIST_URL = "https://readwise.io/api/v3/list/",
    -- LIST is documented at 20 requests/minute. 3.1s leaves a small safety margin.
    READER_LIST_MIN_INTERVAL_SECONDS = 3.1,
    READER_LIST_MAX_RATE_LIMIT_RETRIES = 2,
    READER_LIST_RATE_LIMIT_BACKOFF_SECONDS = { 5, 15 },
}
