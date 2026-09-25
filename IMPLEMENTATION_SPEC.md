# KOReader ↔ Readwise Reader — Implementation Specification

> **Canonical execution spec**  
> **Repository:** `olalaurao/reader`  
> **Target V1 device:** Kindle Paperwhite 3 / 7th gen (PW3), firmware 5.16.2.1.1, KUAL. KOReader `v2025.04` is the validated baseline through Gate 4; planned migration target is official `v2026.07.1` at Gate 4A.  
> **Last verified:** 2026-09-23  
> **Companion roadmap:** `PLAN.md`  
> **Progress ledger:** `STATUS.md`
>
> This file is the implementation source of truth. If code and this spec disagree, either the code is wrong or this file must be deliberately updated in the same change with the reason documented in `STATUS.md`.

---

# 0. Mission

Build a KOReader plugin that makes the Kindle a practical offline reading client for Readwise Reader.

Primary user workflow:

```text
Phone / desktop
    ↓
Save and organize content in Readwise Reader
    ↓
Kindle → Readwise Reader → Sync now
    ↓
Documents are downloaded locally
    ↓
Read normally in KOReader, including offline
    ↓
Highlight and add notes, including literal Markdown such as:
    [[Foucault]]
    [[Biopolitics]]
    #research
    ↓
Kindle → Sync now
    ↓
New highlights/notes are attached to the original Reader document
    ↓
Readwise exports new annotations to Obsidian
```

The plugin is **not** intended to reproduce the Reader UI. Reader is the capture/organization layer; KOReader is the reading/annotation layer.

---

# 1. Product requirements

## 1.1 P0 — must ship in V1

### Reader → Kindle

- Authenticate using a Readwise access token.
- Test authentication independently of a full sync.
- List the Reader library with full cursor pagination.
- Perform an initial sync.
- Perform incremental subsequent syncs.
- Download supported content to a dedicated local directory.
- Open downloaded files as normal KOReader documents.
- Continue reading downloaded files offline.
- Preserve local KOReader sidecars and reading progress.
- Handle Reader location/category changes without duplicating local documents.
- Project Reader organization changes onto the same KOReader-managed file:
  - `new` -> `Readwise: Inbox`;
  - `later` -> `Readwise: Later`;
  - `shortlist` -> `Readwise: Shortlist`;
  - `feed` -> `Readwise: Feed`;
  - `archive` -> `Readwise: Archive`.
- Preserve unrelated user Collections while moving a managed file between plugin-managed Reader-location Collections.
- Project Reader metadata updates (at minimum title, author, summary/site and tags) into KOReader custom metadata without changing Reader-ID ownership or creating a second local file.
- Store Reader tags in a KOReader/Bookshelf-compatible metadata field, preferably `keywords`; do not create one Collection per tag.
- After a Reader-side location/tag/metadata change, the next successful sync must make the corresponding KOReader/Bookshelf representation reflect the new remote state.
- Archive Reader documents when the corresponding local document is marked finished, if enabled.
- Never delete a local file merely because a remote item is archived unless a future explicit deletion policy is enabled.

### Formats

- Article → readable local document.
- Email/newsletter → readable local document.
- RSS → readable local document.
- PDF → original PDF when `raw_source_url` is available and valid; safe fallback otherwise.
- EPUB → original EPUB when `raw_source_url` is available and valid; safe fallback otherwise.
- Tweet/video/other textual categories → readable HTML/text representation when Reader provides usable content.
- Unicode, Portuguese accents, curly quotes, emoji and non-ASCII text must survive round-trip.

### Kindle → Reader

- Discover annotations belonging to Reader-managed local documents.
- Create a new Reader highlight attached to its original Reader document.
- Include the KOReader note at highlight creation time.
- Preserve note text literally, including `[[wikilinks]]`, Markdown, hashtags, emoji and line breaks.
- Avoid creating the same remote highlight twice.
- Queue unsent writes when offline or after retryable failure.
- Resume pending writes after restart.
- Never silently discard an annotation that could not be synchronized.

### Safety

- Token must never enter Git.
- Token must never be printed in logs.
- Signed temporary source URLs must not be logged.
- Destructive remote actions are disabled by default.
- Failed downloads must not replace valid local documents.
- A crash or power loss during sync must leave recoverable state.

## 1.2 P1 — implement if the API spike proves safe before V1 freeze

- Update an already-created remote highlight note when the KOReader note changes.
- Delete a remote highlight when a locally-created/synced annotation is intentionally deleted and the user explicitly enabled deletion propagation.
- Highlight color synchronization is intentionally out of V1: the target PW3 is monochrome and the current Reader workflow does not expose a useful multi-color requirement for this project.
- Optional "sync only tag `koreader`".
- Optional maximum download size.

## 1.3 Explicit non-goals for V1

- Import Reader highlights into exact KOReader positions.
- Reader ↔ KOReader reading-position synchronization.
- Full bidirectional conflict-free annotation editing.
- Feed discovery/search UI on the Kindle.
- Background automatic sync.
- Full Reader tag-management UI.
- Automatic local deletion of archived items.
- Firmware/jailbreak management.
- Supporting every KOReader version before the target device works.
- Styling parity with Reader.
- Automatically updating existing Obsidian exports after a Readwise note edit.

---

# 2. Known external facts and constraints

These were verified against current documentation on 2026-09-22 and must be rechecked if APIs behave differently during implementation.

## 2.1 Reader API v3

Base: `https://readwise.io/api/v3`

Authentication header:

```http
Authorization: Token <TOKEN>
```

Auth validation:

```http
GET https://readwise.io/api/v2/auth/
Expected success: 204
```

### LIST

```http
GET /api/v3/list/
```

Important query params:

- `id`
- `updatedAfter` ISO 8601
- `location`
- `category`
- repeated `tag`, up to documented limit
- `limit` 1..100
- `pageCursor`
- `withHtmlContent=true|false`
- `withRawSourceUrl=true|false`

Important result fields:

- `id`
- `url`
- `source_url`
- `title`
- `author`
- `source`
- `category`
- `location`
- `tags`
- `site_name`
- `word_count`
- `reading_time`
- `created_at`
- `updated_at`
- `notes`
- `summary`
- `image_url`
- `parent_id`
- `reading_progress`
- `first_opened_at`
- `last_opened_at`
- `saved_at`
- `last_moved_at`
- optionally `html_content`
- optionally `raw_source_url`

Highlights and notes in Reader are themselves documents and can have `parent_id`.

LIST rate limit is documented as 20 requests/minute/token.

### Create highlight attached to a Reader document

```http
POST /api/v3/save/
Content-Type: application/json
```

Payload:

```json
{
  "parent_id": "<reader-document-id>",
  "content": "<exact substring from parent document content>",
  "notes": "<literal note>",
  "saved_using": "koreader-readwise-reader"
}
```

When `parent_id` is supplied, the request creates a highlight. The `content` must be copied character-for-character from the parent content; if it cannot be found, the API returns 400 and creates nothing.

Document/highlight create rate limit is documented as 50/minute/token.

Successful response contains a Reader-style string document ID. **Do not assume this is the same identifier used by Readwise API v2.**

### Document update

```http
PATCH /api/v3/update/<document_id>/
```

Useful for document fields such as `location`. Current Reader documentation explicitly permits `notes` and `tags` updates on highlight children. Gate 8 physically verified this on the target account. Production note updates should therefore prefer Reader v3 for the known Reader child ID.

### Bulk update

```http
PATCH /api/v3/bulk_update/
```

Up to 50 document updates. A `207` response can contain mixed success/failure. This is useful for batching archive operations after the manual path is proven.

### Delete

```http
DELETE /api/v3/delete/<document_id>/
```

Documented success: 204. The endpoint is generic at the documentation level, but whether it safely deletes a highlight document created through `parent_id` must be verified in the annotation API spike before relying on it.

### Raw source

`raw_source_url` is a temporary direct source URL, empty for non-distributable documents and documented as valid for one hour.

Rules:

- consume it immediately;
- never store it as durable identity;
- never log it;
- never assume availability;
- request a fresh one if download is retried after expiration.

Official docs:
- https://readwise.io/reader_api

## 2.2 Readwise API v2

Base: `https://readwise.io/api/v2`

The v2 API has numeric highlight IDs and supports:
- highlight list/detail;
- highlight update:
  `PATCH /api/v2/highlights/<id>/`
- highlight delete:
  `DELETE /api/v2/highlights/<id>/`

Update supports fields including `text`, `note`, `location`, `url`, `color`.

**Gate 8 result:** the disposable physical spike established a deterministic Reader-child ↔ Readwise-v2 mapping path. Production code may use v2 only after that deterministic mapping is proven for the specific stored child; text/note heuristics are forbidden.

Official docs:
- https://readwise.io/api_deets

## 2.3 Obsidian export behavior

Current official docs state:
- new highlights are appended on later exports;
- edits to a highlight/note/tag that was already exported do not automatically rewrite the existing Obsidian note;
- refreshing/re-exporting an already exported document may require deleting the generated note and explicitly refreshing the item.

Therefore our product contract is:

- preserve `[[wikilinks]]` exactly in Readwise notes;
- ensure **new** annotations reach Readwise correctly;
- do not claim that edits to an annotation already exported to Obsidian will automatically update the Obsidian file.

Official docs:
- https://docs.readwise.io/readwise/docs/exporting-highlights/obsidian
- https://docs.readwise.io/readwise/docs/exporting-highlights

---

# 3. Target KOReader facts — staged baseline

Development through **Phase F / Gate 4** was pinned to `v2025.04` as the known before/after baseline.

**Gate 4A-1 passed physically on the target PW3 after upgrading to official KOReader `v2026.07.1`.** Therefore `v2026.07.1` is now the canonical physical V1 target and every later KOReader-internal spike must use that tag first. KOReader `v2025.04` remains only the historical Gate 0–4 compatibility baseline.

Gate 4A-2 passed physically on the target PW3 with Bookshelf `v5.1.4`; Phase G and later phases are now unblocked on the KOReader `v2026.07.1` baseline.

References:
- historical Gate 0–4 baseline: https://github.com/koreader/koreader/tree/v2025.04
- canonical V1 baseline: https://github.com/koreader/koreader/tree/v2026.07.1
- migration/rollback runbook: `docs/KOREADER_UPGRADE.md`

## 3.1 Plugin bootstrap

The built-in hello plugin demonstrates the target pattern:

```lua
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Plugin = WidgetContainer:extend{
    name = "readwisereader",
    is_doc_only = false,
}

function Plugin:init()
    self.ui.menu:registerToMainMenu(self)
end

function Plugin:addToMainMenu(menu_items)
    ...
end

return Plugin
```

Use public/stable KOReader patterns when possible; avoid monkey-patching reader internals.

## 3.2 Annotation storage

KOReader 2025.04 `ReaderAnnotation` persists:

```lua
doc_settings:saveSetting("annotations", annotations)
```

An annotation includes:

```text
datetime          creation time, intended not to change
datetime_updated
drawer
color
text              highlighted text
text_edited
note              user's note
chapter
pageno
pageref
page              XPointer for rolling documents or page number for paging documents
pos0
pos1
pboxes
ext
```

Therefore:

- use the sidecar `annotations` table as the primary source;
- do not use Kindle `My Clippings.txt` as the source of truth;
- do not identify highlights by title;
- do not depend on parsing human-facing clipping strings.

## 3.3 Sidecars

Use KOReader `DocSettings` abstractions instead of hardcoding one sidecar path because sidecar storage can vary.

Updating document content must not casually delete/recreate the sidecar.

## 3.4 SQLite availability

KOReader 2025.04 includes `lua-ljsqlite3/init` and built-in plugins use SQLite databases.

Use SQLite for sync state and queue. Use `LuaSettings` only for small user configuration/credentials.

## 3.5 KOReader 2026.07.1 + Bookshelf compatibility migration

Research refreshed on 2026-09-22:

- latest official stable KOReader release: `v2026.07.1`;
- for PW2 and newer, KOReader exposes the optimized `kindlepw2` target; the `kindlehf` target requires firmware >= 5.16.3, so this PW3 on firmware 5.16.2.1.1 must use the `kindlepw2` release package for Gate 4A;
- current Bookshelf release: `v5.1.4`;
- Bookshelf requires KOReader's built-in **Cover browser** plugin;
- current Bookshelf `_meta.lua` does not declare a formal minimum KOReader version, so support for `2025.04` must not be assumed merely because the plugin can be copied there;
- Bookshelf release history contains explicit compatibility fixes for older KOReader releases, which is evidence of maintained backward compatibility but not a guarantee for this exact old baseline;
- an upstream KOReader issue reported an updater-labelled `2026.07.02` build where several plugins failed to load. Gate 4A therefore pins the published official `v2026.07.1` release, not a nightly/development build.

Source comparison between KOReader `v2025.04` and `v2026.07.1` confirms that the internal APIs currently used by this plugin are still present: `Trapper:dismissableRunInSubprocess`, `ReadCollection`, `DocSettings:flushCustomMetadata`, `ReaderUI:showReader`, `NetworkMgr:isOnline`, `LuaSettings`, `DataStorage:getSettingsDir()` and `ReaderAnnotation` persistence via the `annotations` sidecar setting.

The plugin loader changed materially: newer KOReader normalizes plugin identity from the `.koplugin` directory and treats `_meta.lua` `name` as deprecated for enabled plugins. Keep `name = "readwisereader"` in `_meta.lua` while the 2025.04 compatibility path exists, because older loaders still use it in disabled-plugin flows; newer KOReader tolerates it with a warning.

API presence is not behavioral proof. **Physical regression testing is mandatory before `v2026.07.1` becomes canonical.** See `docs/KOREADER_UPGRADE.md`.

---

# 4. Repository shape

Target repository structure:

```text
/
├── README.md
├── PLAN.md
├── IMPLEMENTATION_SPEC.md
├── STATUS.md
├── LICENSE
├── CHANGELOG.md
├── .gitignore
├── .github/
│   └── workflows/
│       └── test.yml
├── scripts/
│   ├── package.sh
│   └── dev-check.sh
└── readwisereader.koplugin/
    ├── _meta.lua
    ├── main.lua
    ├── config.lua
    ├── constants.lua
    ├── api/
    │   ├── http.lua
    │   ├── reader.lua
    │   └── readwise.lua
    ├── storage/
    │   ├── db.lua
    │   ├── migrations.lua
    │   ├── documents.lua
    │   ├── annotations.lua
    │   └── queue.lua
    ├── content/
    │   ├── downloader.lua
    │   ├── html.lua
    │   ├── images.lua
    │   ├── filenames.lua
    │   └── textmatch.lua
    ├── koreader/
    │   ├── annotations.lua
    │   ├── metadata.lua
    │   ├── collections.lua
    │   ├── documents.lua
    │   └── status.lua
    ├── sync/
    │   ├── coordinator.lua
    │   ├── documents.lua
    │   ├── annotations.lua
    │   └── archive.lua
    ├── ui/
    │   ├── menu.lua
    │   ├── settings.lua
    │   ├── progress.lua
    │   └── diagnostics.lua
    └── tests/
        ├── fixtures/
        └── ...
```

Do not create empty abstraction files merely to match this tree. Introduce modules when their responsibility exists.

---

# 5. Architectural boundaries

## 5.1 `main.lua`

Responsibilities only:

- plugin declaration;
- initialize config/database;
- register dispatcher/menu;
- create top-level dependencies;
- invoke coordinator;
- handle plugin lifecycle.

It must **not**:
- construct raw HTTP requests;
- parse Reader payloads;
- manipulate SQLite directly;
- implement text matching;
- scan sidecars inline.

Goal: keep `main.lua` small enough to understand at a glance.

## 5.2 `config.lua`

Backed by `LuaSettings`.

Settings:

```text
access_token
download_directory
sync_locations
sync_categories
sync_only_tag
download_images
max_image_bytes
max_document_bytes
archive_finished
propagate_annotation_deletes   default false
upload_annotations             default true
debug_logging                  default false
```

Credential reality:
- token is stored locally in plaintext because KOReader settings are plaintext;
- do not describe this as encrypted;
- mask it in UI/logging;
- never copy it into SQLite unless technically unavoidable.

## 5.3 `api/http.lua`

Single transport abstraction.

Interface concept:

```lua
response, err = http:request{
    method = "GET",
    url = "...",
    headers = {...},
    body = nil,
    sink_file = nil,
    timeout_class = "api" | "download",
}
```

Normalized response:

```lua
{
    status = 200,
    headers = {},
    body = "...",
}
```

Normalized error:

```lua
{
    kind = "offline" | "timeout" | "tls" | "rate_limit" |
           "auth" | "client" | "server" | "decode" |
           "io" | "cancelled" | "unknown",
    status = nil,
    retryable = true|false,
    retry_after = nil,
    message = "...",
}
```

Requirements:

- use KOReader-provided socket/http/ltn12/socketutil stack;
- restore socket timeout after request even on errors;
- support streaming to file;
- support JSON request/response;
- accept 2xx families correctly; do not hardcode only 200;
- parse `Retry-After`;
- redact sensitive headers/URLs in logs;
- never recursively retry inside low-level HTTP indefinitely.

Retry orchestration belongs above the transport layer.

## 5.4 `api/reader.lua`

Typed-ish wrapper around Reader v3.

Methods:

```text
validateToken()
listDocuments(options)
iterateDocuments(options, callback)
getDocument(id, with_html, with_raw_source)
createHighlight(parent_id, exact_content, note, tags?)
updateDocument(id, patch)
bulkUpdateDocuments(updates)
deleteDocument(id)
listTags()
```

No KOReader UI code in this module.

## 5.5 `api/readwise.lua`

Only for v2 behavior that Reader v3 cannot provide after the interoperability spike.

Potential methods:

```text
listHighlights(filters)
getHighlight(id)
updateHighlight(id, patch)
deleteHighlight(id)
```

Do not make v2 mandatory for basic document download or initial highlight creation.

## 5.6 Storage layer

All database SQL lives under `storage/`.

No sync module should build SQL strings.

Use transactions for multi-step state changes.

## 5.7 KOReader adapter layer

All direct KOReader-specific operations live under `koreader/`:
- sidecars;
- annotation parsing;
- metadata;
- finished status;
- collections;
- file-manager refresh/invalidation.

This keeps API/sync logic testable off-device.

### Reader organization projection contract

The KOReader adapter layer owns the projection from Reader organization fields into local KOReader state.

For every Reader-managed document with a stable local path:

- Reader `location` maps to exactly one plugin-managed `Readwise: ...` Collection;
- a location move removes the path only from other plugin-managed Reader-location Collections, never from unrelated user Collections;
- Reader `title`, `author`, `summary` and `site_name` update custom metadata on the same path;
- Reader `tags` map to custom metadata `keywords` (or the exact equivalent validated against the adopted KOReader/Bookshelf baseline);
- tags do not become Collections by default;
- Reader ID, not filename/title/location, remains the ownership identity.

Incremental behavior is mandatory: if Reader changes any projected organization field, `updatedAfter` must surface the record and the next successful sync must reconcile the KOReader projection. Reconciliation must be idempotent.

Bookshelf is a consumer of the KOReader projection, not a second source of truth. After Gate 4A-2, its cards/filters/shelves should be able to expose:
- Reader location via the managed Collections;
- Reader tags via keywords/genres/tags metadata;
- title/author/progress from the same local document.

Do not implement reverse synchronization of Bookshelf/KOReader tag or Collection edits back to Reader in V1 unless separately specified and gated.

## 5.8 Sync coordinator

`sync/coordinator.lua` owns the high-level sequence and report.

Concept:

```text
preflight
→ process durable pending queue
→ fetch remote document changes
→ materialize/update local documents
→ scan local annotations
→ enqueue outbound annotation changes
→ execute queue again
→ detect finished documents / enqueue archive
→ execute archive queue
→ commit watermarks
→ show summary
```

Watermarks are committed only when their corresponding remote scan completed successfully.

---

# 6. Persistent database design

Database path:

```text
<DataStorage:getSettingsDir()>/readwisereader.sqlite3
```

Use KOReader SQLite binding:

```lua
local SQ3 = require("lua-ljsqlite3/init")
```

Journal mode:
- if `Device:canUseWAL()`, use WAL;
- otherwise TRUNCATE, matching KOReader patterns.

Enable:
- foreign keys;
- sensible busy timeout if supported.

Use `PRAGMA user_version` for schema migration.

## 6.1 `documents`

Proposed schema:

```sql
CREATE TABLE documents (
    reader_id TEXT PRIMARY KEY,
    parent_id TEXT,
    category TEXT,
    location TEXT,
    title TEXT,
    author TEXT,
    site_name TEXT,
    source_url TEXT,
    local_path TEXT UNIQUE,
    local_format TEXT,
    download_strategy TEXT,
    remote_updated_at TEXT,
    remote_saved_at TEXT,
    remote_last_moved_at TEXT,
    local_content_hash TEXT,
    remote_content_fingerprint TEXT,
    raw_source_available INTEGER NOT NULL DEFAULT 0,
    is_managed INTEGER NOT NULL DEFAULT 1,
    is_local_present INTEGER NOT NULL DEFAULT 0,
    last_materialized_at INTEGER,
    last_seen_remote_at INTEGER,
    last_sync_error TEXT
);
```

Do not store temporary `raw_source_url`.

## 6.2 `annotation_links`

```sql
CREATE TABLE annotation_links (
    local_annotation_id TEXT PRIMARY KEY,
    reader_document_id TEXT NOT NULL,
    reader_highlight_document_id TEXT,
    readwise_v2_highlight_id INTEGER,
    created_remote INTEGER NOT NULL DEFAULT 0,
    local_created_at TEXT,
    locator_fingerprint TEXT NOT NULL,
    original_text_hash TEXT,
    last_text_hash TEXT,
    last_note_hash TEXT,
    last_synced_text TEXT,
    last_synced_note TEXT,
    remote_updated_marker TEXT,
    local_deleted_at INTEGER,
    sync_state TEXT NOT NULL DEFAULT 'local_only',
    last_sync_error TEXT,
    FOREIGN KEY(reader_document_id) REFERENCES documents(reader_id)
);
```

Important: never assume the two remote ID columns are interchangeable.

## 6.3 `queue`

```sql
CREATE TABLE queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    idempotency_key TEXT NOT NULL UNIQUE,
    operation TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    local_annotation_id TEXT,
    reader_document_id TEXT,
    reader_highlight_document_id TEXT,
    readwise_v2_highlight_id INTEGER,
    payload_json TEXT NOT NULL,
    payload_hash TEXT NOT NULL,
    status TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    available_after INTEGER,
    last_attempt_at INTEGER,
    last_error_kind TEXT,
    last_error_message TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
```

Statuses:

```text
pending
in_flight
retry_wait
blocked
conflict
done
cancelled
```

Startup rule:
- convert stale `in_flight` rows back to `pending` unless operation reconciliation proves they completed.

## 6.4 `sync_meta`

```sql
CREATE TABLE sync_meta (
    key TEXT PRIMARY KEY,
    value TEXT
);
```

Keys may include:

```text
document_watermark
document_scan_started_at
document_scan_completed_at
annotation_scan_completed_at
last_full_scan_at
last_successful_sync_at
plugin_schema_version
```

## 6.5 Optional `remote_annotation_probe`

Only if needed to cache interoperability discoveries. Do not persist experimental junk after architecture stabilizes.

---

# 7. Local annotation identity

KOReader annotations do not expose an application-owned UUID in the v2025.04 schema. We need a deterministic identity that survives note/text edits.

For a Reader-managed document, compute:

```text
local_annotation_id =
SHA256(
  reader_document_id
  + "\n" + annotation.datetime
  + "\n" + canonical_locator(annotation)
)
```

`canonical_locator`:

### Rolling/reflow documents

Use stable serialized:
- `page` XPointer;
- `pos0`;
- `pos1`.

### Paging/PDF

Use:
- page number;
- normalized `pos0`;
- normalized `pos1`;
- if needed, normalized geometry fingerprint.

Serialization must:
- be deterministic;
- sort table keys;
- avoid locale-dependent number formatting;
- not include mutable note/text fields.

Fallback if `datetime` is absent:
- hash locator + first-seen text hash;
- mark identity quality `degraded`;
- never allow automatic destructive delete for degraded IDs.

Collision handling:
- detect a second live annotation resolving to an existing ID but with a different locator fingerprint;
- generate a deterministic suffix;
- log a warning;
- disable destructive propagation for that pair.

---

# 8. Managed-document identity

A document is managed only when it has a row in `documents` and the local path resolves to that row.

Do not infer ownership solely from:
- directory;
- filename prefix;
- title;
- author.

For resilience after DB loss, filenames may include a short Reader ID, but that is recovery metadata, not the normal source of truth.

Suggested filename:

```text
<sanitized-title>--rw-<reader-id-short>.<ext>
```

If renamed by user:
- DB link remains canonical while local path exists;
- a later recovery tool may search short IDs;
- do not automatically duplicate unless path truly vanished.

---

# 9. Filename/path rules

`content/filenames.lua` must:

- strip/control NUL and control characters;
- replace `/` and path separators;
- remove `..` path traversal semantics;
- normalize excessive whitespace;
- trim trailing dots/spaces where relevant;
- cap title component by bytes, not only codepoints, with UTF-8-safe truncation;
- preserve extension;
- append stable ID suffix before extension;
- handle collision deterministically.

Do not trust remote title, author, MIME filename or `Content-Disposition`.

All final paths must be checked to remain under the configured download root.

---

# 10. Download directory layout

Default proposal:

```text
/mnt/us/documents/Readwise/
├── Articles/
├── Email/
├── RSS/
├── PDF/
├── EPUB/
└── Other/
```

Assets:

```text
/mnt/us/documents/Readwise/.assets/<reader_id>/
```

Temporary downloads:

```text
/mnt/us/documents/Readwise/.tmp/
```

Do not expose temporary files as readable library documents.

Before finalizing the assets layout, spike whether CRengine on the **post-Gate-4A pinned KOReader target** (expected `v2026.07.1`) resolves relative local image paths robustly. If yes, use external assets to avoid huge base64 HTML. If no, use a capped fallback strategy and document the memory tradeoff.

---

# 11. Document materialization strategy

## 11.1 Common pipeline

```text
remote metadata
→ choose strategy
→ choose safe destination
→ download/build into temp path
→ validate minimum invariants
→ compute hash
→ close all handles
→ atomic rename/swap
→ update DB in transaction
→ update KOReader metadata/collection
```

If replacing an existing document:
- preserve sidecar;
- never delete old content before replacement validates;
- retain backup until new rename succeeds.

## 11.2 HTML categories

For article/email/rss/tweet/video textual fallback:

1. fetch document with `withHtmlContent=true`;
2. reject missing/empty HTML unless a sensible text fallback exists;
3. wrap in minimal UTF-8 HTML shell;
4. preserve semantic content;
5. sanitize only what is needed for local rendering/security;
6. optionally localize images;
7. store metadata externally through KOReader APIs, not by bloating the body.

Do not re-scrape `source_url` unless Reader content is unavailable and a future explicit fallback is added. Reader's processed content is the canonical input for V1.

## 11.3 PDF/EPUB

1. request `withRawSourceUrl=true`;
2. if non-empty, stream original to temp file;
3. validate:
   - HTTP success;
   - nonzero size;
   - size under configured limit if enabled;
   - basic magic/extension sanity where practical;
4. atomically install;
5. if no raw source:
   - use HTML processed content if meaningful;
   - mark `download_strategy=html_fallback`;
   - never lie by naming HTML `.pdf` or `.epub`.

## 11.4 Updated remote documents

Do not automatically replace an existing local file until the "content replacement + sidecar position stability" spike has been completed for that format.

Phase Q evidence/constraints:
- Reader's public Document UPDATE endpoint does **not** accept `html`/body content;
- Reader's parsing FAQ says a normally-saved article is preserved as originally parsed and manual refresh is delete + re-save, which also destroys its Reader highlight/note context;
- Reader's 2026-09-18 changelog nevertheless documents server-side **reparsed documents**, so an existing Reader ID can still surface new body content through service-side repair;
- therefore same-ID content change is a real case but is not deterministically triggerable through the public UPDATE API for a routine device gate.

V1 conservative policy:
- **never automatically replace any already-existing local document in Phase Q until format-specific target-device stability is proven**;
- a Reader revision change on an existing local document is persisted durably as content-refresh-pending before metadata state can hide it;
- metadata/location/tag projection may continue;
- article/HTML candidates may be fetched **read-only** and compared by normalized visible text;
- same visible text means metadata/non-text revision: keep the local file; after physical validation a later build may acknowledge/clear that pending marker without replacing bytes;
- different visible text means keep the current local file and retain refresh pending;
- original PDF/EPUB revisions remain pending/deferred without downloading/replacing the current raw file;
- unknown/unavailable comparison remains pending;
- sidecar is never replaced by this policy.

For existing pre-schema-v2 local files, do not invent a materialized revision during migration. Their materialized revision baseline remains unknown until a future remote revision/read-only comparison provides evidence.

References:
- Reader API: https://readwise.io/reader_api
- Reader parsing FAQ: https://docs.readwise.io/reader/docs/faqs/parsing
- Reader changelog (reparsed documents, 2026-09-18): https://docs.readwise.io/changelog

---

# 12. Image policy

Defaults for PW3:
- images enabled;
- per-image and total-document caps conservative;
- failure of one image does not fail article;
- do not decode large images in Lua unless necessary;
- stream downloads to disk.

Image URL handling:
- allow HTTP(S) only;
- handle redirects with finite limit;
- normalize URL corruption only with narrowly tested rules;
- cache by content hash or deterministic URL hash;
- do not log query strings that may contain secrets.

A document with no images must remain fully readable.

---

# 13. Free-space policy

Before a large raw-source download:
- query free space using a KOReader-supported/system-safe method;
- reserve a safety margin;
- if `Content-Length` exists, check before download;
- during stream, abort if configured max bytes exceeded.

Never fill the filesystem to zero.

Error shown:

```text
Not enough free space to download this document.
The existing local copy was kept.
```

No automatic deletion to make space in V1.

---

# 14. Reader library fetch algorithm

## 14.1 Initial sync

Prefer a metadata-first pass without `withHtmlContent` or `withRawSourceUrl` for the whole library.

Reason:
- smaller responses;
- lower memory;
- decide filters before fetching bodies.

Algorithm:

```text
cursor = nil
repeat
  GET list(limit=100, pageCursor=cursor)
  validate response
  for each result:
      if parent_id != nil:
          ignore as top-level reading document for materialization
      else:
          upsert remote metadata candidate
  cursor = nextPageCursor
until cursor == nil
```

Detect:
- repeated cursor;
- malformed response;
- impossible empty-loop scenarios.

Then materialize only documents selected by configured filters.

## 14.2 Incremental sync

At start:
- `scan_started_at = current UTC timestamp`;
- derive `updatedAfter` from last successful watermark minus overlap.

Overlap default proposal: 5 minutes.

Reason:
- clock/boundary safety;
- idempotent DB upserts make overlap cheap.

Only after **all pages** succeed:
- set watermark to `scan_started_at`, not wall clock at end.

If page N fails:
- do not advance watermark.

## 14.3 Periodic reconciliation

Incremental feeds can miss local anomalies or deletions/moves not represented as expected.

Perform a full metadata reconciliation periodically, e.g. manually exposed "Full rescan" first; automatic cadence can be added after performance testing.

V1 UI should include:
- `Sync now`
- diagnostics-only `Full rescan`

---

# 15. Remote filtering

Filtering order:

1. ignore child documents for library materialization (`parent_id != nil`);
2. location filter;
3. category filter;
4. optional required tag;
5. download size policy;
6. local state.

Do not assume all accounts have Shortlist enabled.

Known locations from LIST docs include:
- `new`
- `later`
- `shortlist`
- `archive`
- `feed`

Update endpoint documents `new/later/archive/feed`; treat `shortlist` carefully when writing. Do not attempt to move to shortlist unless current API behavior is explicitly verified.

---

# 16. KOReader metadata and collections

Use:
- `DocSettings`;
- cache invalidation events used by KOReader;
- `ReadCollection` only when available.

Metadata fields:
- title;
- author;
- keywords/tags;
- description/summary;
- site name as series only if that remains useful in device testing.

Collections:
- `Readwise: Inbox` for location `new`;
- `Readwise: Later`;
- `Readwise: Shortlist`;
- `Readwise: Feed`;
- Archive normally not synced unless user explicitly includes it.

Collection updates must be idempotent.

Do not delete arbitrary user collections.

---

# 17. Reading/finished status

Determine finished status using KOReader's canonical summary/status representation on the **post-Gate-4A pinned KOReader target**. Do not parse visible strings.

Archive action:

```json
{"location":"archive"}
```

Prefer individual PATCH until proven; bulk update may be used later.

State machine:
- local finished detected;
- enqueue archive operation;
- remote success;
- update local document row location to archive;
- keep local file.

Do not repeatedly enqueue archive once remote state is known archived.

---

# 18. Annotation scan

Only scan annotations for Reader-managed documents.

Preferred sources:
- currently open document: `self.ui.annotation.annotations` when appropriate;
- closed documents: read the canonical sidecar `annotations` through `DocSettings`/KOReader APIs.

Do not parse:
- `My Clippings.txt`;
- rendered bookmark strings;
- titles to infer document mapping.

For each annotation:
- ignore pure page bookmarks;
- require highlight text for remote highlight creation;
- compute stable `local_annotation_id`;
- compute text/note hashes;
- compare with `annotation_links`.

New local annotation:
- create/update DB row `local_only`;
- enqueue `create_highlight`.

Changed local note:
- if remote mapping for update is proven, enqueue `update_highlight_note`;
- otherwise mark `remote_update_unsupported` and keep local data intact.

Missing formerly linked local annotation:
- mark `local_deleted_at`;
- do not enqueue destructive delete unless enabled and identity is high confidence.

---

# 19. Exact-content matching for Reader highlight creation

Reader requires exact parent content.

Input:
- KOReader annotation text;
- Reader document HTML content.

Need a robust but conservative matching pipeline.

## 19.1 Extract Reader visible text map

Do **not** simply strip tags with a regex if that changes entity decoding/whitespace unpredictably.

Implement or reuse a small HTML-to-text/token mapping sufficient to produce:
- normalized search representation;
- mapping back to exact source-visible text span expected by Reader.

First spike the API's interpretation:
- whether `content` expects decoded visible text versus raw HTML substring;
- how HTML entities, NBSP, line breaks, soft hyphens are handled.

## 19.2 Candidate stages

1. exact text occurrence;
2. Unicode NFC normalization;
3. whitespace equivalence:
   - spaces;
   - tabs;
   - line breaks;
   - NBSP;
4. conservative punctuation equivalence:
   - straight/curly quotes;
   - common hyphen/dash forms;
   - soft hyphen removal;
5. unique candidate recovery.

Never:
- fuzzy Levenshtein-match a materially different sentence;
- silently choose among multiple equally valid occurrences.

## 19.3 Ambiguous repeated quote

If identical quote appears multiple times:
- the API itself only accepts content, not KOReader position;
- if the Reader endpoint chooses a deterministic occurrence, test and document it;
- if ambiguity affects placement or order and cannot be resolved, create only if behavior is harmless and user-visible;
- otherwise leave unsynced with reason `ambiguous_text_match`.

## 19.4 Failure state

Keep:
- local annotation;
- note;
- locator;
- hashes;
- error class.

UI summary:
```text
1 highlight could not be matched to the Reader text.
Nothing was deleted.
```

---

# 20. Creating remote highlights

Queue operation `create_highlight`.

Preconditions:
- document has Reader ID;
- exact content resolved;
- operation is not already represented by a confirmed remote link.

Payload generated at execution time where possible, so a fresh source body can be used for matching.

On success:
- persist returned Reader highlight document ID;
- set `created_remote=1`;
- store sent text/note hashes;
- mark queue done in same DB transaction.

## 20.1 Timeout-after-create problem

A POST can succeed remotely while the client times out before receiving the ID.

Therefore retrying blindly can duplicate.

Required reconciliation strategy before retrying ambiguous create:

1. record operation payload fingerprint;
2. query Reader child documents updated in the relevant time window and/or v2 highlights after interoperability is understood;
3. look for a high-confidence match:
   - parent document;
   - exact text;
   - exact note;
   - creation time window;
   - source marker if available;
4. if unique, link it instead of POSTing again;
5. if ambiguous, mark `blocked_reconciliation` and do not duplicate automatically.

This is a hard requirement for production V1.

---

# 21. Annotation API interoperability spike — hard gate

Before implementing edit/delete propagation, create a disposable Reader document and perform these experiments manually through code/tests:

## H1 — create

- Create highlight via Reader v3 `save` with `parent_id`.
- Record returned Reader highlight document ID.

Expected:
- visible under original Reader document.

## H2 — v3 listing

- LIST by returned ID if supported.
- LIST recent child docs.
- Capture actual child object fields.
- Determine whether note is represented directly or through a child note document.

## H3 — v2 visibility

- Query Readwise v2 highlights created/updated after spike start.
- Identify the same highlight.
- Record numeric v2 ID.
- Determine if v2 `external_id`, URL, book/source metadata or another field exposes a deterministic mapping.

## H4 — update note

Public Reader docs rechecked on 2026-09-23 now explicitly state that a highlight accepts `notes` and `tags` through Document UPDATE. This changed the documented contract from the older assumption captured when this spec was first written.

Test, in safe order:
1. documented Reader v3 PATCH `notes` + `tags` using the returned Reader highlight child ID;
2. verify Reader UI and v3 LIST reflect the change;
3. after H3 establishes a deterministic numeric v2 mapping, PATCH the same disposable highlight through documented Readwise v2 `note`;
4. verify Reader UI and v3 LIST reflect the v2 change.

Production architecture must follow the observed Gate 8 result. Do not keep v2 mandatory for note edits merely because the older spec assumed v3 could not update highlight notes.

## H5 — delete

Test:
1. v3 DELETE with Reader highlight document ID;
2. verify disappearance from Reader and v2;
3. if needed, v2 DELETE with numeric ID.

## H6 — tags/color

Only if easy:
- test Reader tags on create;
- test v2 color update;
- decide whether V1 exposes either.

### Required artifact

Record observed behavior in:

```text
docs/API_INTEROP.md
```

Include date and sanitized request/response shapes.

No edit/delete implementation may proceed before this file exists.

---

# 22. Updating an annotation note

Only enabled if H4 produces a reliable remote mapping.

Trigger:
- linked annotation exists;
- local `note_hash != last_note_hash`.

Conflict check:
- if we can fetch remote update timestamp/value and it changed since our last known version while local also changed:
  - mark conflict;
  - do not overwrite.

Otherwise:
- PATCH Reader v3 `notes` on the confirmed Reader highlight child ID;
- verify success and re-read the same child when practical;
- update hashes/state only after confirmed remote success.

Gate 8 physically proved that Reader v3 highlight note updates are supported and propagate correctly. Readwise v2 is therefore **not mandatory for normal note edits**. Use the deterministic Reader-child ↔ v2 mapping only when a later feature specifically needs a v2-only capability.

If update support later proves unreliable for a specific record:
- keep the local edit intact and report it as unsynced/blocked;
- do **not** implement delete-and-recreate silently, because that can duplicate Obsidian exports and reorder highlights.

---

# 23. Deleting a remote annotation

Default setting:

```text
propagate_annotation_deletes = false
```

Eligibility when enabled:
- plugin has a confirmed remote link;
- local identity is high confidence;
- annotation was originally created/linked by this plugin;
- remote record has not diverged unexpectedly.

Then:
- use the API path proven by H5;
- require confirmed 204/expected success;
- preserve tombstone locally long enough to prevent recreation.

Never treat:
- missing sidecar;
- missing local file;
- failed disk mount;
- parser error

as proof the user intended remote deletion.

---

# 24. Notes, Markdown and Obsidian

Plugin behavior:
- never interpret `[[...]]`;
- never normalize brackets;
- never convert note to HTML;
- never trim meaningful internal/newline whitespace;
- preserve UTF-8 exactly.

Test note:

```text
Relacionar com [[Foucault]] e [[Biopolítica]].

#pesquisar
🧠
```

End-to-end test:
1. create note in KOReader;
2. sync to Reader;
3. inspect Reader;
4. trigger official Readwise → Obsidian export;
5. inspect generated Markdown;
6. verify Obsidian recognizes intended links with the user's current export template.

Document limitation:
- if the same annotation was already exported and later edited, official Readwise docs say that edit is not automatically rewritten in the existing Obsidian note; refresh/re-export is separate from our plugin.

---

# 25. Queue semantics

Operations:

```text
create_highlight
update_highlight_note
delete_highlight
archive_document
```

Potential future:
- mark_seen;
- update_tags.

## 25.1 Idempotency key

Examples:

```text
create_highlight:<local_annotation_id>:<payload_hash>
update_highlight_note:<local_annotation_id>:<note_hash>
archive_document:<reader_document_id>:archive
```

The DB unique constraint prevents duplicate queued work.

## 25.2 Retry classes

Retry:
- offline;
- timeout;
- DNS/transient TLS;
- HTTP 408;
- HTTP 429 honoring `Retry-After`;
- HTTP 5xx.

Do not auto-retry forever:
- auth 401/403;
- validation 400;
- not found when identity is suspect;
- conflict/ambiguous reconciliation.

Backoff example:
- attempt 1: immediate/manual cycle;
- then 5s, 15s, 60s within one active sync only if UX allows;
- after bounded attempts, persist for next manual sync.

Do not sleep 60 seconds while freezing the UI if a better "defer until next sync" path is available.

---

# 26. Sync transaction/watermark rules

A sync is not one giant DB transaction because network and downloads are long-running.

Use small transactions around durable state transitions.

Never:
- hold SQLite transaction open during network download;
- advance document watermark before pagination completes;
- mark queue item done before remote success is persisted.

Suggested sequence for a queue item:

```text
DB: pending → in_flight, commit
network operation
if success:
    DB transaction:
      update entity link/state
      queue → done
    commit
else:
    DB:
      queue → retry_wait/blocked/conflict
      store sanitized error
    commit
```

On startup, reconcile stale `in_flight`.

---

# 27. Preflight

Before sync:

1. config initialized;
2. database open/migrated;
3. download root exists/is writable;
4. token exists;
5. no migration failure;
6. recover stale queue state;
7. treat local KOReader/Kindle network state only as advisory on the target PW3; do not let it authorize remote writes;
8. scan/persist local annotation intents before any remote request;
9. inside the cancellable worker, use the existing read-only Readwise auth GET as the authoritative remote reachability/auth probe before any queue processing or remote mutation;
10. compute free-space snapshot;
11. create sync report object.

If the read-only remote probe fails:
- keep local annotations and queued work durable;
- perform no remote write;
- do not advance the document watermark;
- distinguish network-class failure from auth/rate-limit/server unavailability in diagnostics;
- do not show a fatal crash;
- report that work remains queued and Wi-Fi/auth/service availability must be restored outside the plugin.

---

# 28. No Wi-Fi control

The plugin must not call Wi-Fi enable/disable flows in V1.

It may use KOReader NetworkMgr to:
- inspect current connectivity;
- react to current state.

Reason:
- target PW3/firmware combination has historically had Wi-Fi/KOReader quirks;
- user can enable Wi-Fi before sync;
- network control is outside the core product.

---

# 29. UI specification

Top-level:

```text
Readwise Reader
├── Sync now
├── Sync status
├── Open Readwise folder
├── Full rescan
└── Settings
```

Settings:

```text
Account
├── Access token
└── Test connection

Documents
├── Download folder
├── Locations
├── Categories
├── Download images
├── Maximum image size
├── Maximum document size
└── Sync only tag (optional)

Annotations
├── Upload highlights        [ON]
├── Upload notes             [ON]
└── Propagate deletions      [OFF]

Finished documents
└── Archive in Reader        [ON/OFF]

Diagnostics
├── Plugin version
├── Database schema version
├── Last successful sync
├── Pending operations
└── Debug logging            [OFF]
```

Token entry:
- mask display after save;
- provide replace/clear;
- no "show token" unless unavoidable.

## 29.1 Progress

Do not update e-ink UI for every tiny item.

Batch/throttle visible progress:

```text
Readwise sync
Fetching library… 2/5 pages
Downloading… 7/18
Uploading annotations… 3/4
```

## 29.2 Completion summary

```text
Readwise sync complete

Documents
  3 downloaded
  1 updated
  12 unchanged
  1 deferred

Annotations
  4 uploaded
  1 pending
  0 deleted

1 warning
```

"Details" can point to diagnostics/log rather than dumping stack traces.

---

# 30. Logging

Prefix all logs:

```text
ReadwiseReader:
```

Examples:

```text
ReadwiseReader: [SYNC] start
ReadwiseReader: [API] list page=2 count=100
ReadwiseReader: [DOC] installed id=...
ReadwiseReader: [DOC] refresh deferred: local annotations
ReadwiseReader: [ANN] created local=... reader_child=...
ReadwiseReader: [ANN] match failed reason=ambiguous
ReadwiseReader: [QUEUE] retry op=... reason=timeout
```

Redaction:
- Authorization header → always `<redacted>`;
- token substrings → always `<redacted>`;
- `raw_source_url` → do not log;
- signed query params → do not log;
- full article/note content → not in normal logs.

Debug mode may log hashes, lengths and IDs, not private body text by default.

---

# 31. Migrations

Use `PRAGMA user_version`.

Each migration:
- numeric ordered version;
- transaction;
- forward-only;
- idempotent where feasible;
- backup DB before risky migration.

If migration fails:
- rollback;
- leave old DB untouched/backup available;
- disable sync;
- show diagnostics instruction.

Never silently delete/recreate DB to fix migration errors.

---

# 32. Database backup/recovery

Before schema migration:
- create `.bak` copy if size permits.

SQLite corruption:
- detect open/integrity failure;
- do not delete automatically;
- offer diagnostics;
- documents themselves remain usable because content is stored separately.

Future recovery tool can reconstruct `documents` partially from filenames/metadata, but this is not required for first implementation.

---

# 33. Cancellation and e-ink performance

PW3 is constrained.

Rules:
- sequential downloads first;
- no unbounded parallel requests;
- no loading all HTML bodies into memory during metadata pass;
- stream raw source to disk;
- release large strings quickly;
- use local scopes and avoid retaining page responses;
- throttle UI redraws.

Use the cancellable progress primitives verified on the currently pinned KOReader baseline; revalidate them during Gate 4A before relying on them in later phases.

Cancel:
- leaves installed docs intact;
- leaves queue/state resumable;
- does not advance unfinished watermark.

---

# 34. Source plugin reuse

Existing community implementation:
- `koreader/contrib/readwisereader.koplugin`
- archived upstream by original owner in 2026 but still useful as reference.

Before copying implementation:
- inspect original license;
- preserve required attribution/license notices;
- record origin in README/LICENSE notices.

Reuse concepts selectively:
- menu integration;
- Reader pagination;
- image handling lessons;
- collection handling;
- metadata events;
- finished/archive detection.

Do **not** blindly port:
- monolithic architecture;
- filename-as-ID coupling;
- generic v2 highlight export that creates a separate Readwise source;
- `My Clippings` parsing as annotation source;
- fixed sleep-based rate limiting;
- remote-archive → local-delete behavior.

---

# 35. Testing strategy

## 35.1 Unit tests — pure Lua

Must cover:

### Filenames
- ASCII;
- Portuguese;
- emoji;
- slash/backslash;
- `../`;
- huge UTF-8 title;
- collisions.

### Cursor pagination
- one page;
- many pages;
- repeated cursor;
- malformed next cursor;
- empty page.

### HTTP classification
- 204 auth;
- 200 JSON;
- 201 create;
- 207 bulk;
- 400;
- 401;
- 403;
- 404;
- 429 with/without Retry-After;
- 500;
- timeout.

### Database
- fresh schema;
- migration;
- rollback;
- queue uniqueness;
- stale in-flight recovery.

### Annotation ID
- note edit does not change ID;
- text edit does not change ID;
- locator change does;
- rolling vs paging deterministic.

### Text matching
- exact;
- line breaks;
- NBSP;
- curly quotes;
- soft hyphen;
- repeated identical phrase;
- no match;
- Unicode normalization.

### Queue
- retryable;
- permanent error;
- timeout-after-create reconciliation path;
- idempotency.

## 35.2 Integration tests with mocked API

Fixtures:
- Reader LIST pages;
- parent + child documents;
- raw source missing;
- raw source expired;
- highlight create;
- rate limits;
- v2 mapping responses after spike.

Never store a real user's Reader document bodies or token in fixtures.

## 35.3 Device tests

Maintain `docs/DEVICE_TESTS.md` with each run:
- plugin commit;
- device;
- firmware;
- KOReader version;
- exact test;
- result;
- relevant sanitized log.

---

# 36. Required device test corpus

Create/supply test items in Reader deliberately:

1. short article;
2. long article;
3. article with many images;
4. Portuguese accents;
5. curly quotes/dashes;
6. same sentence repeated twice;
7. newsletter;
8. RSS item;
9. small text PDF;
10. image-heavy PDF;
11. EPUB;
12. item without raw source if available;
13. document moved between new/later/archive;
14. document whose title changes;
15. document updated after partial local reading.

Annotation cases:
16. highlight only;
17. highlight + plain note;
18. note `[[Foucault]]`;
19. two wikilinks;
20. multiline note;
21. emoji;
22. repeated-highlight text;
23. edit note;
24. delete local highlight;
25. create while offline;
26. crash/restart with queued operation;
27. network drop after POST;
28. sync twice unchanged.

---

# 37. CI

CI should not try to emulate the Kindle GUI.

Initial CI goals:
- syntax/lint;
- unit tests;
- deterministic package structure;
- no obvious secrets;
- build ZIP artifact.

If KOReader's test environment can be reused without excessive maintenance, add it later.

Package output:

```text
readwisereader.koplugin.zip
```

ZIP root must expand to:

```text
readwisereader.koplugin/
  _meta.lua
  main.lua
  ...
```

---

# 38. Versioning

SemVer for plugin releases.

Suggested progression:

```text
0.0.1 bootstrap
0.0.x connectivity/API spikes
0.1.x Reader document sync
0.2.x PDF/EPUB/raw formats
0.3.x annotation create
0.4.x queue + offline + reconciliation
0.5.x note update if proven
0.6.x archive/collections/hardening
0.9.x release candidates on PW3
1.0.0 V1 acceptance passed
```

Database migrations are independent numeric schema versions.

---

# 39. Development branch/commit discipline

Use small commits that leave repository understandable.

Preferred phases:
- branch per milestone/spike;
- squash only if history becomes noise;
- commit message describes one coherent change.

Examples:

```text
chore: bootstrap KOReader plugin skeleton
feat(auth): validate Readwise token
feat(storage): add sqlite state schema
feat(reader): paginate Reader documents
feat(sync): materialize article html
feat(annotations): scan KOReader sidecars
spike(api): document Reader v3/v2 highlight mapping
feat(annotations): create linked Reader highlights
fix(queue): reconcile ambiguous create timeout
```

Never combine:
- schema migration;
- API behavior change;
- unrelated UI redesign

in one opaque commit.

---

# 40. STATUS.md protocol — mandatory while implementing

After every meaningful implementation session update `STATUS.md`.

It must answer:

```text
Current milestone:
Current branch/commit:
What works:
What is in progress:
What failed / learned:
Decisions made:
Tests run:
Device test needed:
Exact next steps:
Known blockers:
```

If work stops because of tool/quota/context limits, `STATUS.md` must be enough for a fresh implementation session to continue without reconstructing decisions from chat history.

Do not mark a gate complete without evidence/test.

---

# 41. Implementation sequence — authoritative

Do not skip ahead because a later feature is more interesting.

## Phase A — repository/bootstrap

### A1
- inspect old plugin license;
- add LICENSE/NOTICE as required;
- add README;
- add .gitignore;
- add skeleton plugin;
- add version constant.

### A2 — Gate 0
- package plugin;
- user copies to `koreader/plugins/`;
- restart KOReader;
- menu appears;
- basic info dialog works;
- removing folder restores baseline.

**Do not implement full API before Gate 0 passes on PW3.**

## Phase B — config/auth

### B1
- LuaSettings config;
- masked token entry;
- clear/replace;
- no token logs.

### B2 — Gate 1
- `GET /api/v2/auth/`;
- success 204;
- invalid token path;
- offline path;
- timeout path.

## Phase C — storage foundation

### C1
- SQLite DB;
- schema;
- migrations;
- DB unit tests.

### C2
- documents repository;
- queue repository;
- annotation-links repository;
- sync_meta.

No remote write yet.

## Phase D — Reader metadata

### D1
- Reader client;
- LIST one page;
- parse required fields.

### D2
- pagination;
- cursor-loop guard;
- rate-limit handling.

### D3 — Gate 2
- metadata-only full library scan on real account;
- report counts without downloading;
- verify memory/performance on PW3.

## Phase E — first readable document

### E1
- select one known article;
- fetch `html_content`;
- safe filename;
- build minimal HTML;
- atomic install.

### E2
- write metadata;
- open in KOReader.

### E3 — Gate 3
Verify on PW3:
- renders;
- Unicode;
- reflow;
- font/margin controls;
- search;
- dictionary;
- highlight;
- note;
- reopen retains progress.

## Phase F — document sync engine

### F1
- configurable root;
- locations/categories;
- DB ownership;
- incremental watermark.

### F2
- update metadata/location;
- no duplicate on title rename;
- collections.

### F3
- cancellation;
- summaries;
- full rescan.

### F4 — Gate 4
- multiple articles;
- second sync unchanged;
- move Reader location;
- rename title;
- no duplicates.

## Phase F.5 — KOReader baseline migration + Bookshelf coexistence

**Run only after Gate 4 passes on `v2025.04`, and finish it before any Phase G work.**

### F5.1 — freeze + backup
- record the exact Gate 4 plugin commit/package and successful no-op second sync;
- back up KOReader settings/plugins/database and `/mnt/us/documents/Readwise/` including sidecars;
- do not update Kindle firmware, jailbreak or KUAL.

### F5.2 — upgrade KOReader only
- install the published official KOReader `v2026.07.1` **`kindlepw2`** package on this PW3;
- do not use `kindlehf` on firmware 5.16.2.1.1;
- do not use a nightly/development build for this gate;
- leave Bookshelf absent/disabled for the first regression pass.

### Gate 4A-1 — Readwise Reader compatibility
Verify on the real PW3:
- KOReader starts normally;
- plugin loads and can be disabled/re-enabled;
- token/config/database survive;
- existing Reader article, progress, highlight and note survive;
- auth works;
- sync, no-op second sync and full-rescan cancellation still work;
- Reader title/location changes retain the same Reader-ID-owned local document;
- no sensitive data appears in logs.

Only after this passes does `v2026.07.1` become the physical V1 baseline.

### F5.3 — Bookshelf `v5.1.4`
- confirm built-in **Cover browser** is enabled;
- install Bookshelf `v5.1.4`;
- initially keep KOReader's normal File Manager as the startup view;
- verify Readwise Reader menu/sync, new documents, Readwise collections and open/close behavior while Bookshelf is installed;
- only then optionally set `Start with -> Bookshelf`.

### Gate 4A-2 — coexistence — PASSED
Physical PW3 validation passed on KOReader `v2026.07.1` + Bookshelf `v5.1.4`: restart/no-op sync, Reader-managed documents, progress/highlight/note preservation, Reader location -> managed Collections, unrelated Collection preservation and Reader document tags -> Bookshelf Genres all passed. A stale Bookshelf light-metadata cache discovered during incremental tag updates was fixed by invalidating the optional Bookshelf light cache once after successful metadata writes.

Full procedure and rollback: `docs/KOREADER_UPGRADE.md`.

## Phase G — images

### G1 spike
- test relative local assets with CRengine on the post-Gate-4A pinned target (expected `v2026.07.1`).

### G2
- implement chosen asset strategy;
- caps;
- failure tolerance.

### Gate 5 — PASSED
Physical PW3 validation on KOReader v2026.07.1 passed:
- document-relative local image assets render;
- a real Reader article image downloads, persists locally and renders after reopen;
- failed/missing images do not destabilize KOReader;
- surrounding text remains usable when some images fail.

Not every remote image is required to render in V1; graceful degradation is the accepted contract.

## Phase H — raw formats — COMPLETE

### H1 — implemented
- fresh `raw_source_url` requested immediately before raw materialization;
- signed URL is never persisted and query parameters are redacted from HTTP logs;
- bounded HTTP streaming directly to temp file;
- fsync + validation + atomic rename;
- 64 MiB raw-source cap;
- 128 MiB minimum free-space reserve before starting.

Reader's documented `raw_source_url` contract is treated as ephemeral: direct S3 link, empty for non-distributable documents, valid for one hour.

### H2 — implemented
- PDF original preferred when a valid distributable raw source exists;
- PDF magic validation before install.

### H3 — implemented
- EPUB original preferred when a valid distributable raw source exists;
- ZIP magic validation before install.

### H4 — implemented
- processed HTML fallback only after a non-transient raw-source failure for which fallback is safe;
- retryable network/storage failures do not silently switch format;
- if neither raw source nor usable HTML exists, record a stable per-document content skip.

### Gate 6 — PASSED
Physical PW3 validation on KOReader v2026.07.1 passed:
- one real original Reader PDF opens, reads and reopens with progress preserved;
- one real original Reader EPUB opens, reflows and reopens with progress preserved;
- both remain usable as local/offline documents;
- no crash/freeze was observed.

HTML fallback remains valid product behavior but does not substitute for the original-format proof above.

## Phase I — sidecar/annotation adapter — IMPLEMENTED, GATE 7 PENDING

### I1 — implemented
- read the canonical KOReader `annotations` table through `DocSettings`;
- stable SHA-256 local annotation identity based on Reader document ID + creation time + deterministic locator;
- degraded datetime-less fallback reconciled by one unambiguous locator match;
- literal selected text/note hashes for add/edit detection;
- authoritative deletion detection with tombstones;
- missing file/sidecar/parser state never treated as intentional deletion.

### I2 — implemented
- ownership requires an exact managed `documents.local_path` row;
- unrelated documents are rejected;
- page bookmarks are ignored by the highlight adapter;
- unit coverage for rolling/PDF locator identity, note/text edits, locator changes, degraded IDs, add/edit/delete and unsafe missing-state cases;
- targeted on-device current-document diagnostic avoids a full-library scan.

### Gate 7 — PASSED
Physical PW3 validation on KOReader v2026.07.1 passed:
- selected text and the note content actually entered on-device are read exactly from the sidecar;
- locator evidence is populated and identity quality is strong;
- close/reopen preserves the same local annotation ID;
- a second scan recognizes the same annotation as unchanged;
- no crash/freeze observed.

The optional emoji fixture was not entered because the Kindle keyboard has no emoji input; this is not a persistence or identity failure.

## Phase J — annotation API spike — COMPLETE

H1–H6 from section 21 were executed against plugin-created disposable Reader data only.

Implementation:
- Reader v3 create/update/delete wrappers;
- Readwise v2 highlight LIST/DETAIL/PATCH/DELETE + Export probe;
- staged on-device Gate 8 workflow with persistent disposable IDs;
- deterministic mapping requires Reader/v2 external IDs, never title/text-only guessing;
- separate recovery cleanup action;
- no existing user document/highlight is mutated by the spike.

### Deliverable
- `docs/API_INTEROP.md` records the dated sanitized request/response shapes and physical observations.

### Gate 8 — PASSED
Physical validation on the target PW3 / KOReader v2026.07.1 established:
- Reader v3 create returns a child ID and attaches the highlight/note/tag to the intended disposable parent;
- v3 LIST exposes the expected parent/category/note and locator evidence;
- the Reader highlight child maps deterministically to a numeric Readwise v2 highlight ID; text/note heuristics are not accepted;
- Reader v3 PATCH of highlight `notes`/`tags` succeeds and is reflected in Reader;
- Readwise v2 PATCH of the deterministically mapped highlight succeeds and its note change propagates back to the same Reader child;
- Reader v3 DELETE removes the child and the corresponding v2 highlight disappears without needing a v2 delete fallback;
- disposable parent cleanup succeeds;
- color mutation worked as interoperability evidence, but highlight-color synchronization is deliberately out of V1.

Gate 8 is closed. Phase K text matching is unblocked; edit/delete production behavior must still obey the safety/conflict rules in later phases.

## Phase K — text matching — COMPLETE, GATE 9 PASSED

### K1
Implemented:
- fetch the exact managed Reader parent with `withHtmlContent=true`;
- extract Reader-visible text without treating markup, comments, script or style content as selectable text;
- decode the common/numeric entities needed by Reader content;
- recover the exact Reader-visible substring rather than returning the normalized search string;
- staged matching in this order: literal exact → Unicode NFC → whitespace/NBSP + soft-hyphen normalization → conservative straight/curly quote and dash equivalence;
- use KOReader's bundled `ffi/utf8proc` NFC implementation on-device, with a small Latin fallback only for off-device test environments where that KOReader module is absent.

### K2
Implemented:
- every stage requires a unique candidate;
- repeated exact or normalized candidates return `ambiguous` and are never guessed;
- no-match returns `unmatched`;
- the Gate 9 UI is read-only and reports the newest local highlight's local text, match mode/result and recovered Reader-visible text;
- the diagnostic opens its own DB/API dependencies in the subprocess worker and never creates, updates or deletes a remote annotation.

The pre-existing staged Phase L upload code from 0.1.23 remains in the branch for later work but its menu entry is deliberately disabled until Gate 9 passes. It is not part of Gate 9 and must not be exercised as a substitute for this gate.

### Gate 9 — PASSED
Physical validation on the target PW3 / KOReader v2026.07.1 passed all documented cases:
- ordinary unique selection matched safely;
- selection spanning a paragraph/line-break boundary matched safely with the intended Reader-visible passage recovered;
- curly/straight quote or common dash case matched safely under the conservative equivalence rules when needed;
- repeated identical passage was reported ambiguous and not guessed;
- every diagnostic reported `Remote writes: none`;
- no crash/freeze was observed.

Gate 9 is closed. Phase L / Gate 10 remote creation is now unblocked, but must still satisfy timeout reconciliation and deduplication before physical validation.

## Phase L — create highlights — COMPLETE, GATE 10 PASSED

### L1 — production create path
Implemented in build 0.1.25:
- normal **Sync now** receives the currently-open KOReader document path before entering the subprocess;
- only the currently-open managed Reader document is scanned for annotations in this gate build, avoiding a full sidecar sweep across the PW3 library;
- the canonical KOReader sidecar scan updates durable annotation links before any upload attempt;
- Gate 9's unique Reader-visible text matcher supplies the exact parent passage;
- a durable `create_highlight:<local_annotation_id>` queue item is written before the POST;
- Reader v3 creates the highlight with the original Reader document as `parent_id`;
- note text is transported literally, including multiline Markdown and `[[wikilinks]]`;
- the returned Reader child ID is persisted immediately after a confirmed create response;
- a second sync skips any annotation that already has a durable remote child link.

The current-document-only discovery scope is a controlled Phase L/Gate 10 staging surface, not a reduction of the V1 product scope. Broader offline/backlog queue discovery and retry hardening remain Phase O work.

### L2 — ambiguous-create reconciliation
Implemented:
- every create carries a stable unique `saved_using = "KOReader Readwise Reader:<local_annotation_id>"` marker;
- Reader's documented LIST `source` field is used as the reconciliation representation of that marker;
- stale `create_highlight` items left `in_flight` by a crash become `blocked`, never `pending`;
- any create item with a prior attempt is reconciled before any further write;
- reconciliation scans Reader highlight documents and accepts only an exact unique match on both `parent_id` and the per-annotation source marker;
- zero matches stays blocked and performs no POST;
- multiple matches stays blocked and guesses nothing;
- one exact match adopts that Reader child ID and marks the queue succeeded without creating another highlight;
- successful creates perform a verification GET so the Gate 10 physical run can prove that the custom marker is observable as the Reader child's `source`.

Automated tests cover confirmed create + literal note, second-sync deduplication, timeout followed by marker reconciliation, attempted-pending recovery without retry, no-match blocking, ambiguous text with no queue/write, queue stale-create recovery, and current-path propagation through Sync now.

### Gate 10 — PASSED
Physical validation on the target PW3 / KOReader v2026.07.1 passed:
- a unique KOReader highlight was created under the correct original Reader document;
- selected text matched correctly;
- the literal multiline note containing `[[Foucault]]` and `#pesquisar` arrived exactly;
- the normal create path reported no blocked create;
- the per-annotation marker was visible through Reader LIST;
- a second unchanged Sync now created zero new highlights;
- Reader retained only one copy;
- no crash/freeze was observed.

Gate 10 is closed. Phase M / Gate 11 official Readwise → Obsidian export validation is now unblocked.

## Phase M — Obsidian end-to-end — COMPLETE, GATE 11 PASSED

### M1 — official export contract
Current official Readwise documentation was revalidated on 2026-09-23.

Canonical path:
- use the **Readwise Official** community plugin inside the user's real Obsidian vault;
- new highlights can sync automatically or through the command `Readwise Official: Sync your data now`;
- the documented default Highlight template renders attached notes through `{{ highlight_note }}`;
- new highlights from an already-known document are appended to its existing Obsidian page;
- the integration is append-only so it does not overwrite user edits.

This phase does not add a new KOReader build. Gate 10 already proved that the exact local note reaches the correct Reader highlight. Gate 11 isolates the downstream official export only.

### M2 — template/config rule
The first Gate 11 observation must use the user's real current Readwise/Obsidian export configuration without silently changing it.

Minimum compatible configuration:
- the active Highlight template must emit `highlight_note` (the official default does);
- the note must not be wrapped/escaped in a way that turns `[[Foucault]]` into code or plain escaped text.

If the user's current custom template intentionally omits highlight notes, record that as an export-configuration limitation. It is not evidence of a Kindle→Reader plugin failure.

### M3 — append-only limitation
The official integration does not automatically rewrite an Obsidian file when an already-exported highlight is later edited or gains a note/tag. A refresh/re-export workflow is needed for those historical changes.

Therefore:
- Gate 11 validates **initial export** of the Gate 10 test annotation;
- Phase N / Gate 12 can prove Kindle note edits reach Reader, but automatic propagation of those edits into a previously-exported Obsidian block is outside the official export's current append-only behavior;
- this limitation must be documented rather than hidden.

### Gate 11 — PASSED
Using the Gate 10 test highlight whose Reader note is exactly:

`ver [[Foucault]]`
`#pesquisar`

verify in the user's real Obsidian vault:
- the official Readwise sync places the highlight under the correct exported article;
- source Markdown contains the note with literal `[[Foucault]]`;
- `#pesquisar` is preserved;
- Obsidian recognizes `[[Foucault]]` as an internal wikilink under the user's real template/config.

No new Kindle build was required. The user's real export configuration passed all criteria: correct article/highlight, note present, literal `[[Foucault]]`, preserved `#pesquisar`, and a functioning Obsidian internal wikilink. Gate 11 is closed and Phase N / Gate 12 is unblocked.

## Phase N — update/delete annotations — COMPLETE, GATE 12 PASSED

Gate 8 physically proved on the target account/device that the linked Reader v3 highlight child accepted a note PATCH and reflected it in Reader. The current public Reader API page contains wording that is more restrictive for highlight-note updates, so **the physically observed Gate 8 contract remains the project contract and Gate 12 revalidates it in the production path**. Do not generalize beyond this tested linked-highlight workflow.

### N1 — note update + conflict detection
Implemented and physically validated for note update in build 0.1.31 on the currently-open managed Reader document:
- only annotations with a durable `reader_highlight_document_id` and `created_remote=true` are eligible;
- the exact Reader child is fetched before mutation;
- for **note update**, durable child id + original `parent_id` + `category=highlight` are the required identity; exact per-annotation or legacy plugin `source` markers are accepted as additional evidence when Reader returns them, but are not mandatory because physical Gate 12 testing showed Reader LIST can omit/change that marker on a correctly linked child;
- local highlight text changes are blocked rather than mapped into a remote text mutation;
- `last_synced_note` is the three-way merge baseline; note equality for conflict decisions uses a conservative comparison normalization (CRLF/CR→LF, trailing horizontal whitespace per line, outer whitespace) while preserving exact payload text;
- the production conflict read uses the deterministic Readwise v2 representation: exact `Reader child id == v2 external_id`; the resulting numeric v2 highlight id is persisted for future direct detail reads;
- if the remote v2 note already equals the local value, the operation is reconciled without another PATCH;
- if the remote v2 note diverged from `last_synced_note` while local also diverged, state becomes `conflict` and neither side is overwritten;
- if only the local note changed, the exact mapped Readwise v2 highlight is PATCHed with the new note; the returned id/note must match, then the exact linked Reader v3 child is polled until it reflects the note;
- if v2 already has the desired note but Reader v3 remains stale, a Reader v3 repair PATCH is issued to the already-validated child and verified;
- `last_synced_note` / hashes advance and `Notes updated` increments only after Reader v3 visibility is proven;
- the exact v2 response is treated as an intermediate acknowledgement, never as end-to-end success;
- a previously blocked/conflict state is re-evaluated on later Sync now when the local note still differs from the durable `last_synced_note` baseline, so a fixed identity/read path can recover without recreating the highlight;
- the 0.1.30 premature-success state is also recoverable: when local + durable baseline + v2 agree but Reader v3 is stale, the Reader child is repaired without another v2 write;
- a nil-note clear is currently blocked until highlight-note clearing is physically validated.

### N2 — optional delete propagation
Implemented:
- configuration key `propagate_highlight_deletions` defaults to **false**;
- Settings → Highlights → **Propagate highlight deletions** exposes the option;
- enabling requires an explicit warning/confirmation; disabling is immediate;
- when OFF, authoritative sidecar deletion creates/keeps the local tombstone and Reader is untouched;
- when ON, DELETE is allowed only after **cross-API destructive identity** passes: exact durable Reader child id + expected parent + `category=highlight`, plus the exact Readwise v2 highlight whose `external_id` equals that Reader child id; Reader `source/saved_using` is not authoritative because physical production data may omit it;
- Reader DELETE acknowledgement alone is not enough: the exact Reader child is polled and durable remote IDs/created flag are cleared only after the child is confirmed gone; the local tombstone history is preserved;
- a Reader/v2 cross-API identity mismatch, zero mapping, or ambiguity is blocked and never guessed;
- a missing remote target can be reconciled as already deleted.

The current-document scope from Phase L remains in force for Gate 12 to keep destructive operations bounded on the PW3. Phase O owns broader queue/backlog retry hardening.

**Required engineering memory:** before changing annotations again, read `docs/ANNOTATION_SYNC_LESSONS.md`. That document captures the production-only behavior discovered across builds 0.1.26–0.1.31 and supersedes any simpler single-API assumption.

Automated tests cover:
- deterministic Reader-child → Readwise-v2 external-id mapping for note mutation;
- normal note update through the exact mapped v2 highlight and response verification;
- response-loss reconciliation when Reader already has the local note;
- simultaneous local+remote note conflict with no overwrite;
- delete propagation OFF;
- verified delete propagation ON;
- identity mismatch blocking;
- default-off config persistence;
- explicit confirmation before enabling deletion;
- existing storage state transitions and Sync summary counters.

### Gate 12 — PASSED
On the target PW3 / KOReader v2026.07.1:
1. **PASS on build 0.1.31:** linked Kindle note edit reaches Reader exactly, with Reader-visible end-to-end verification/repair before durable success;
2. **PASS on build 0.1.31:** simultaneous local+Reader note edit is reported as conflict and neither side is overwritten;
3. **PASS on build 0.1.31:** with deletion propagation OFF, deleting one linked KOReader test highlight leaves Reader unchanged and records exactly one retained tombstone;
4. enable deletion only after the OFF sync reports exactly one pending local deletion for the clean test article;
5. **PASS on build 0.1.32:** deliberate opt-in deletion removes only the linked target remotely using cross-API identity and post-delete verification;
6. **PASS:** deletion propagation was disabled again after the test.

Physical note-update evidence on build 0.1.31: 2 linked highlights scanned; 1 note updated; 1 reconciled; 0 conflicts; 0 mutation blocks; 2 v2 remote-note reads; 1 v2 note update; 6 Reader verification reads; 1 propagation miss; 2 v3 repair PATCHes; 2 completed repairs; 0 remote errors; user visually confirmed the final Reader note.

Physical conflict evidence on build 0.1.31: one linked highlight scanned; 1 conflict blocked; 0 note updates; 0 v2 note updates; 0 mutation blocks; 0 remote errors; Reader preserved the remote edit and Kindle preserved the local edit.

Physical deletion-OFF evidence on build 0.1.31: 2 fresh highlights were created; one was deleted only on KOReader; the OFF sync reported 1 local deletion detected, 1 retained remotely, 0 remote deletions, 0 mutation blocks, 0 remote errors; the user confirmed both Reader highlights still exist.

Physical deletion-ON close on build 0.1.32: the tombstoned target disappeared remotely, the control highlight remained, deletion propagation was returned OFF, and the follow-up OFF sync showed 0 local deletions, 0 remote deletions, 0 mutation blocks, 0 remote errors. Gate 12 is closed and Phase O / Gate 13 is unblocked.

## Phase O — offline queue hardening — COMPLETE, GATE 13 PASSED

### O1 — offline create / restart / reconnect / backlog discovery
Queue core implemented in 0.1.33. Physical builds 0.1.33 and 0.1.34 proved that target-device local network state cannot safely authorize writes. The 0.1.35 read-only diagnostic then observed, while the user had no internet/native Airplane Mode, that `airplaneMode`, `wirelessEnable` and `wifid enable` were all unavailable while KOReader still reported `isWifiOn/isConnected/isOnline=true`.

Build 0.1.36 changed the pre-write authority contract. Build 0.1.37 closed the earlier current-document-only discovery staging limitation, but its first physical Gate 13A run failed safely before producing a report. Build 0.1.38 hardens that multi-sidecar discovery boundary:
- every manual Sync discovers new create-highlight work across **all locally-present Reader-managed documents**, with the currently open document prioritized;
- a real Lua exception from one document's sidecar scan or queue preparation is isolated to that document and cannot abort the whole worker;
- one malformed annotation normalization inside an otherwise-readable sidecar is counted/skipped rather than aborting that sidecar;
- if the optimized local-managed repository query raises on the device, discovery falls back to the existing managed-document query, then to the current document as a last local-only fallback;
- only locally-present managed rows are loaded for the backlog pass; remote-only rows are excluded before sidecar IO;
- missing files, missing/non-authoritative sidecars and per-document scan failures are skipped safely and never imply deletion;
- authoritative sidecars reconcile `annotation_links` first, then pass those exact adjusted local identities into durable create queueing without reading the same sidecar twice;
- note updates and optional destructive deletes remain bounded to the current document for this gate; Phase O broadens create/backlog discovery, not destructive scope;
- all local discovery and durable create intents happen **before any remote request**;
- KOReader/Kindle local connectivity flags are advisory only;
- the worker performs the already-existing read-only `GET /api/v2/auth/` before queue processing, annotation mutation or document sync;
- only a successful 204 probe permits remote work;
- a network-class probe failure returns `offline / local queue`, performs no remote write, keeps queue items waiting, and advances no watermark;
- auth/rate-limit/server-class probe failures likewise perform no remote writes and report `local queue / remote unavailable`;
- the plugin never enables/disables Wi-Fi;
- queued payload contains the local text/note, parent Reader ID, stable local annotation ID, hashes and marker;
- queue processing remains independent of the original in-memory reader session, so a new KOReader process can resume it after reboot.

### O2 — retry classes
Implemented:
- queue states now implement `retry_wait` and `available_after` from the canonical schema;
- due retry-wait rows promote atomically to pending;
- retryable **preflight GET** failures are safe to defer because no POST has occurred;
- auth rejection before POST preserves attempts=0 and the durable payload for a later credential recovery;
- POST 429 is treated as an explicit rejection but still reconciles before any later retry;
- POST auth rejection likewise reconciles before later retry;
- POST timeout/offline/5xx/unknown outcome is treated as ambiguous and never blindly retried;
- 5xx/timeout with zero reconciliation match stays blocked, preserving the local annotation rather than risking a duplicate;
- exact payload is refreshed only while attempts=0; after an attempt starts the durable payload is immutable.

Automated deterministic coverage:
- offline queue → new uploader/process → reconnect → exactly one create;
- 429 → retry_wait → due → reconcile zero match → exactly one later successful create;
- timeout where remote create actually happened → marker reconciliation → no second POST;
- timeout where no marker exists → blocked/no second POST;
- 5xx where no marker exists → blocked/no second POST;
- auth before POST → payload preserved with attempts=0 → later create after auth recovery;
- ambiguous text → queue blocked/no remote write.

### O3 — stale in-flight
Implemented:
- worker runs stale-in-flight recovery before processing queue;
- stale create rows become `blocked/stale_create_in_flight`, never pending;
- queue processor reconciles a prior-attempt create before any write;
- one exact marker match adopts the remote child;
- zero/ambiguous match never guesses and never blind retries;
- non-create stale operations retain generic pending recovery semantics for later phases.

### Gate 13 — PASSED on build 0.1.41
Automated O2/O3 fault injection and managed-document backlog discovery coverage are complete. The 0.1.35 network-state spike is also complete and invalidated local-state authorization.

Physical 0.1.37 Gate 13A result: **FAIL SAFE / no report**. With Airplane Mode/no internet, ordinary Sync displayed only `Document sync failed safely`. No reboot/reconnect step was attempted. Because 0.1.37 introduced broad local sidecar traversal, 0.1.38 adds per-document exception containment, annotation-normalization containment, repository-query fallback, and worker-stage diagnostics without weakening the pre-write remote gate.

Physical Gate 13A/B evidence on 0.1.38:
- controlled KOReader-offline state passed: 3 durable create items waited, 0 were processed, no remote/document work progressed;
- after a full KOReader restart while still offline, the same queue remained at 3 waiting and the same local highlight/note remained visible;
- therefore offline durability + process-restart persistence are physically proven.

Gate 13C reconnect attempt on 0.1.38: **FAIL SAFE / no report**.
- Wi-Fi was re-enabled outside the plugin;
- ordinary Sync now returned only `Document sync failed safely`;
- the user did not run a second Sync afterward;
- because the generic UI means the KOReader subprocess ended without a usable serialized result, do not assume whether the failure happened before or after a remote create and do not blind retry.

Build 0.1.39 was therefore a **read-only reconnect spike**. Physical result: it again ended without a serialized report, but its durable breadcrumb was `parent_reads`. Because the worker only advances to that stage after queue snapshot, auth and marker scan, the crash boundary is now parent content retrieval and/or text matching.

Build 0.1.40 physically completed the bounded parent probe:
- auth passed;
- queue remained pending=3 / in_flight=0 / blocked=0;
- exact-marker scan passed across 11 pages with **0 active marker matches**;
- all three pending parents returned metadata + HTML successfully;
- parent HTML sizes were only **9,851 / 27,477 / 8,564 bytes**;
- no remote writes occurred.

That evidence rules out the parent LIST/JSON/HTML retrieval boundary for these three queued creates. The only 0.1.39 work removed by 0.1.40 was text matching/normalization.

Implementation review found a plausible hard-exit mechanism in the matcher: it loaded KOReader's native `ffi/utf8proc` and called `normalize_NFC` during normalized matching. Native FFI faults are not recoverable by Lua `pcall`. Build 0.1.41 therefore changes the matcher conservatively:
- exact matching remains first and unchanged;
- whitespace and punctuation normalization semantics remain unchanged;
- native NFC FFI is removed from annotation matching entirely;
- the Unicode fallback composes only the explicitly-supported Latin base+combining sequences in pure Lua;
- unsupported normalization cases fail safely as unmatched rather than invoking native code;
- visible-text extraction batches contiguous ordinary text instead of allocating one Lua table slot per source byte;
- normalized matching does not allocate a source-map subtable for every UTF-8 unit before it knows a stage matched;
- source-span recovery after a unique normalized match uses a second linear pass, keeping the matching semantics while reducing peak allocation;
- the reconnect diagnostic now executes the **real matcher** for each pending item;
- durable stages record `validate`, `visible_text`, `exact`, `unicode`, `whitespace`, `punctuation`, and per-item completion;
- parent reads remain bounded at 1 MiB;
- no queue mutation/promotion and no POST/PATCH/DELETE.

Physical 0.1.41 matcher result: **PASS**.
- diagnostic reached `done_match_probe`;
- queue remained pending=3 / attempts=0 / in_flight=0 / blocked=0;
- marker scan found 0 active exact marker matches;
- all three parent reads succeeded;
- item #1 matched exact;
- items #2/#3 matched via whitespace normalization;
- no remote writes occurred.

The same production matcher is therefore physically cleared for these queued fixtures.

Next physical step:
1. keep 0.1.41 and Wi-Fi ON;
2. do not alter Gate 13 fixtures;
3. run ordinary **Sync now exactly once**;
4. return the full report before any second sync;
5. verify each pending highlight/note appears exactly once under its original Reader document;
6. then run one unchanged second Sync and prove created=0 / waiting=0 / no duplicate.

Gate 13 closes only after no duplicate and no lost annotation are physically proven across offline → reboot → reconnect.

Final physical result: Gate 13 **PASSED**.
- offline queue held 3 creates with zero remote work;
- queue and local highlight/note survived KOReader restart;
- matcher hardening was physically validated;
- reconnect created exactly 3 pending highlights, queue drained to zero, and Reader contained exactly one copy of each with expected notes;
- unchanged second Sync created 0, processed 0, waiting 0, and produced no duplicate.

Phase O is complete.

## Phase P — finished/archive — SIGNAL SPIKE IMPLEMENTED, GATE 14 OPEN

### P0 — canonical finished-signal spike

Official KOReader v2026.07.1 source establishes the candidate contract:
- BookStatusWidget maps **Finished** to status value `complete`;
- ReaderStatus `markBook()` sets `doc_settings.summary.status = "complete"` and updates `summary.modified`;
- BookList maps `complete` to Finished and identifies its source as `doc_settings.summary.status`.

Do not treat source inspection alone as the production proof. Build 0.1.42 adds a local-only diagnostic for one currently-open Reader-managed document:
- persisted sidecar `summary.status`;
- persisted `summary.modified`;
- persisted `percent_finished`;
- BookList status;
- current runtime summary status;
- local DB Reader location.

The diagnostic performs no network request and no local/remote write.

**P0 physical result: PASS on the target PW3 / KOReader v2026.07.1.**

Before KOReader **Book status → Finished**:
- managed Reader document: yes;
- local file: present;
- Reader location in plugin DB: `new`;
- sidecar: present;
- persisted `summary.status = reading`;
- persisted `summary.modified = 2026-09-23`;
- persisted `percent_finished = 0.1538`;
- BookList status: `reading`;
- runtime `summary.status = reading`;
- diagnostic candidate: no;
- plugin remote requests/writes/local writes: none.

After choosing **Finished** and closing the KOReader status UI:
- Reader location in plugin DB remained `new` (the diagnostic made no mutation);
- sidecar remained present;
- persisted `summary.status = complete`;
- persisted `summary.modified = 2026-09-24`;
- persisted `percent_finished` remained **0.1538**;
- BookList status became `complete`;
- runtime `summary.status` became `complete`;
- diagnostic candidate: yes;
- plugin remote requests/writes/local writes: none.

Therefore V1 Finished detection is **exactly `summary.status == "complete"`**. Do not infer Finished from `percent_finished`, end-of-document position, visible labels, or a date alone.

### P1 — IMPLEMENTED in build 0.1.43
- setting `archive_finished` / **Finished documents → Archive in Reader**, default ON as specified by PLAN.md;
- scan only Reader-managed, locally-present documents;
- require an existing local file and canonical sidecar status;
- unknown/missing sidecar status is a safe skip/block, never interpreted as unfinished;
- detect only `summary.status == "complete"`;
- enqueue `archive_document:<reader_id>` durably before any remote reachability/mutation;
- payload contains only the Reader ID, target `location=archive`, and non-sensitive local finished modification marker;
- read-only Reader GET before every archive PATCH/retry;
- if Reader is already archived, adopt that state and perform no PATCH;
- if a prior PATCH timed out/crashed but actually succeeded, next Sync GET-reconciles it and does not issue a duplicate PATCH;
- if local Finished is reverted before a confirmed remote archive and Reader is verified not archived, cancel the intent safely;
- PATCH parent document individually with `{"location":"archive"}`;
- after confirmed remote archive, persist local document-row location `archive` **before** marking the queue item succeeded, making local crash recovery monotonic;
- parent-side postprocess moves the still-local file to the plugin-managed `Readwise: Archive` Collection without removing unrelated user Collections;
- never delete, replace, rename, or rewrite the local document or sidecar as part of archive;
- local progress/highlights/notes are untouched;
- archive setting OFF prevents discovery/processing; durable pending state is not destructively discarded;
- nonretryable client rejection blocks safely;
- auth/retryable/ambiguous outcomes remain durable and are reconciled before a later retry.

No schema migration is required: the existing generic durable queue already supports document operations.

### Gate 14 — PASSED on build 0.1.43
Physical result:
- canonical Finished signal was proven as persisted `summary.status == "complete"`;
- first Sync moved the managed document to Reader Archive;
- local file remained present/openable;
- sidecar, progress, highlights and notes were preserved;
- unchanged second Sync produced no repeated archive side effect and the queue remained empty.

Phase P is complete.

## Phase Q — content refresh safety — GATE 15 PASSED COMPLETE

### Q1 — build 0.1.45 read-only / no-replacement spike

Implementation:
- schema v2 adds:
  - `materialized_remote_updated_at`;
  - `content_refresh_pending`;
  - `content_refresh_remote_updated_at`;
  - `content_refresh_detected_at`;
- migration from v1 deliberately leaves `materialized_remote_updated_at = NULL` for legacy local files rather than falsely claiming the latest metadata revision is what their bytes contain;
- every new materialization records the exact Reader `updated_at` revision that produced its local bytes;
- when metadata discovery sees a newer Reader revision for an existing local file, it durably marks refresh pending **before/while** metadata is advanced;
- later no-op syncs cannot erase the pending signal;
- normal Sync never calls the materializer for an already-existing local file;
- Sync summary exposes durable pending count.

KOReader risk signals exposed read-only:
- sidecar presence;
- `percent_finished`;
- annotation count;
- `last_xpointer` presence for reflowable content;
- `last_page` presence for paged content;
- `partial_md5_checksum` presence;
- aggregate `has_reading_state`.

**Inspect content refresh safety (Gate 15)**:
- current document must be Reader-managed;
- local HTML read capped at 4 MiB;
- Reader HTML response capped at 4 MiB;
- compares normalized **visible text only** by direct Lua string equality; no native hashing/FFI is required and no private text is displayed/logged;
- raw PDF/EPUB source is not downloaded by the diagnostic;
- reports V1 decision;
- automatic replacement is hard-disabled;
- remote writes: none;
- local writes: none.

Decisions in 0.1.45:
- `same_visible_text_keep_local`;
- `defer_changed_text_reading_state`;
- `defer_changed_text_unproven`;
- `defer_raw_keep_local`;
- `defer_unverified_keep_local`;
- `block_local_missing`;
- never `replace`.

### Q1 attempt 1 — 0.1.44 physical FAIL / corrected in 0.1.45

The first physical diagnostic tap exited KOReader back to the launcher before any Gate 15 result was shown.

Root cause:
- Q1 introduced the first database schema migration (v1 → v2);
- KOReader `ffiUtil.copyFile(from, to)` returns **nil on success** and an error string on failure;
- the 0.1.44 pre-migration backup path incorrectly interpreted nil as failure and raised before the SQL migration transaction began;
- the parent menu preflight did not contain that exception.

0.1.45 correction:
- treat nil from KOReader `copyFile` as successful backup;
- treat any non-nil return as backup failure;
- regression-test the exact KOReader copy contract;
- wrap parent-process DB and sidecar preflight calls so future failures show a safe UI message rather than escaping the menu callback;
- remove unnecessary `ffi/sha2` use from the diagnostic and compare normalized text directly;
- content replacement remains disabled.

Because the failure occurs before `Migrations.apply` begins its transaction, the original v1 database should remain unchanged. A successful `.bak` copy may have been created.

### Q1-A article physical result — PASS on 0.1.45

Real PW3 fixture:
- managed local article / HTML / `reader_html`;
- sidecar present;
- `percent_finished = 0.1538`;
- 6 annotations;
- last XPointer present;
- partial file checksum present;
- reading state at risk = yes.

After a Reader **title-only** same-ID revision and one Sync:
- `Content refresh pending review = 1`;
- metadata pages = 1;
- content pages = **0**;
- errors = 0;
- no annotation create/update/delete regression;
- local article still opened;
- progress/position, highlights and notes were unchanged.

Post-revision diagnostic:
- refresh pending = yes;
- pending remote revision equals current Reader revision;
- remote probe passed;
- visible-text comparison = **same**;
- decision = `same_visible_text_keep_local`;
- automatic replacement = no;
- remote writes none;
- local writes none.

This physically authorizes Q2 to acknowledge only the exact pending revision whose fetched visible text is proven equivalent to the current local bytes.

### Q1-B raw fixtures

PDF physical result: **PASS COMPLETE** on the target PW3 / KOReader v2026.07.1 / build 0.1.46.

EPUB physical result: **PASS COMPLETE** on the same target/build.
- existing plugin-managed original EPUB identified and opened;
- diagnostic reported raw EPUB semantics (`category=epub`, `local_format=epub`);
- local file present;
- remote probe passed;
- visible-text comparison was `not_attempted_raw`;
- decision was `defer_raw_keep_local`;
- automatic replacement remained disabled;
- remote/local writes were none.

The same-ID title-only EPUB revision + one Sync + post-Sync preservation/diagnostic validation also passed physically:
- raw EPUB revision remained pending/deferred;
- no replacement content download/install occurred;
- EPUB reopened/reflowed normally;
- sidecar/progress/highlights/notes remained intact;
- post-Sync diagnostic remained `not_attempted_raw` + `defer_raw_keep_local`, pending=yes, replacement disabled, remote/local writes none.

Therefore **Gate 15 is PASSED COMPLETE**. Phase R / Gate 16 is unblocked.
- existing plugin-managed original PDF identified and opened;
- diagnostic reported raw PDF semantics (`category=pdf`, `local_format=pdf`);
- remote probe passed;
- visible-text comparison was `not_attempted_raw`;
- decision was `defer_raw_keep_local`;
- automatic replacement remained disabled;
- remote/local writes were none.
- title-only same-ID Reader revision then produced the required durable raw-pending path;
- normal Sync performed no replacement content download/install;
- local PDF remained usable and sidecar/progress/annotations remained intact;
- post-revision diagnostic still reported `not_attempted_raw` + `defer_raw_keep_local` with replacement disabled.

Raw fixtures:
1. use an already-downloaded original PDF and EPUB when available;
2. create a harmless same-ID Reader metadata revision;
3. Sync;
4. diagnostic must return `defer_raw_keep_local`;
5. local raw file/sidecar remains untouched.

The public API cannot deterministically mutate an existing document's body for this gate. The `different` body branch is therefore covered by deterministic automated fixtures and the production invariant "existing file is never materialized/replaced"; a naturally/server-reparsed document may additionally validate it when available.

### Q2 — IMPLEMENTED in build 0.1.46

Normal Sync now reconciles durable refresh-pending rows after the normal document metadata pass:
- process at most **5 pending HTML articles per Sync** to protect PW3 responsiveness/rate limits;
- read local HTML under the existing 4 MiB cap;
- GET the same Reader document read-only with HTML under the same cap;
- require fetched Reader `updated_at` to equal the exact durable `content_refresh_remote_updated_at`; a revision race is retained pending;
- compare normalized visible text directly in Lua;
- when visible text is `same`:
  - clear only the durable refresh-pending marker;
  - do **not** replace/rewrite local document bytes;
  - do **not** write sidecar/progress/annotations;
  - do **not** issue a remote mutation;
- when visible text is `different`, retain pending;
- when read/compare is unavailable, retain pending;
- raw PDF/EPUB revisions remain pending and are not fetched as replacement bytes;
- local missing files remain pending and are reported;
- Reader read failures are non-destructive and leave the revision pending.

A legacy row may keep `materialized_remote_updated_at = NULL` even after a metadata-only revision is acknowledged. That field means the revision that literally produced the local bytes; Q2 does not falsify it. Future Reader revisions are still detected from the metadata row's `remote_updated_at` and produce a new pending revision.

Sync report adds:
- refresh pending examined;
- refresh articles compared;
- metadata-only revisions acknowledged;
- changed-content revisions retained;
- raw PDF/EPUB revisions retained;
- unverified revisions retained;
- local files missing;
- revision races retained;
- remote read errors;
- final pending count.

Automatic byte replacement remains disabled in V1 unless a later explicit format stability spike changes this spec.

### Q2 physical article result — PASS
On the target PW3 / KOReader v2026.07.1 / build 0.1.46:
- the first Q2 Sync acknowledged the previously-pending title-only article revision without replacing local bytes;
- because the report's acknowledgement lines were cropped, a read-only Gate 15 diagnostic recovered the evidence: refresh pending=no, current Reader revision=DB revision, visible text=same, replacement=no, remote/local writes=none;
- the unchanged second Sync was then confirmed as a no-op for that revision;
- local progress/position, highlights and notes remained intact.

Therefore article Q2 acknowledgement and idempotency are physically passed. The only remaining Gate 15 coverage is Q1-B for already-local original PDF/EPUB revisions.

### Gate 15
No local annotation/progress loss caused by remote content update/revision. Existing local bytes and sidecar must remain intact for every changed/unverified/raw case; metadata-only article revisions may be acknowledged without replacing bytes after Q1 passes.

## Phase R — hardening

- large library;
- low disk;
- malformed document;
- huge document;
- Unicode;
- 429;
- intermittent Wi-Fi;
- force-close;
- reboot;
- migration;
- rollback;
- debug log review for secrets.

### Deterministic/off-device hardening — PASS on 0.1.47 candidate

Before physical RC installation, CI now covers the Phase R order:
- 5,000-document / 50-page Reader traversal with cursor and duplicate guards;
- low-space raw preflight plus ENOSPC cleanup/classification for streamed raw and processed HTML writes;
- malformed-record isolation, including a fully malformed page followed by a valid cursor page;
- bounded Reader JSON/content responses and processed HTML size;
- Unicode filenames and multilingual HTML;
- bounded/cancellable 429 Retry-After behavior;
- partial metadata scan timeout recovery without watermark advance or duplicate materialization;
- file-backed queue persistence across process reopen/reboot semantics, including stale ambiguous create blocking;
- real file-backed v1→v2 migration backup and transaction rollback;
- schema-v2 compatibility with the known-good 0.1.46 rollback build;
- static and runtime token/signed-URL/log redaction tripwires.

No physical Gate 16 pass is implied by these tests.

### Gate 16
Release candidate stable on target PW3.

## Phase S — V1 acceptance

Run the complete acceptance script in section 42.

Tag `v1.0.0` only after all P0 acceptance steps pass or a deliberate scope change is written into this spec and PLAN.md.

---

# 42. V1 acceptance script

On the actual PW3:

1. Start with valid installed plugin and empty pending queue.
2. Save a new article in Reader.
3. Enable Wi-Fi outside KOReader.
4. Sync.
5. Confirm article downloaded once.
6. Open and read.
7. Turn Wi-Fi off.
8. Continue reading.
9. Highlight text.
10. Add:
   `ver [[Foucault]] e [[Biopolítica]]\n\n#pesquisar`
11. Close/reopen document.
12. Confirm annotation remains.
13. Sync while offline.
14. Confirm annotation becomes pending, not lost.
15. Enable Wi-Fi.
16. Sync.
17. Confirm highlight appears under the original Reader document.
18. Confirm note is exact.
19. Sync again.
20. Confirm no duplicate.
21. Export/sync Readwise to Obsidian.
22. Confirm wikilinks behave as expected.
23. If update is part of V1 after API spike, edit note and verify Reader.
24. Simulate one retryable network failure and recover without duplicate.
25. Restart KOReader with a pending queue item; recover it.
26. Mark document finished.
27. Sync.
28. Confirm Reader location becomes archive.
29. Confirm local file remains.
30. Confirm sidecar/progress/annotations remain.
31. Inspect logs: no token, no signed source URL, no full private content leak.
32. Run second no-op sync: zero new documents/highlights.

---

# 43. Definition of done per code change

A change is not done merely because code exists.

For each milestone:
- code implemented;
- unit tests where feasible;
- static/syntax checks pass;
- manual test instructions documented;
- `STATUS.md` updated;
- no secret committed;
- no known regression left undocumented.

For device gates:
- exact device result recorded.

---

# 44. Stop conditions during implementation

Stop advancing to later phases when:

- plugin no longer loads on the currently pinned KOReader baseline;
- database migration is unsafe;
- network operation duplicates data;
- token appears in logs;
- a local file/sidecar is at risk of silent loss;
- exact highlight matching is ambiguous;
- remote ID mapping is assumed rather than demonstrated;
- a destructive operation cannot be linked to a known plugin-managed entity.

Fix or explicitly redesign before continuing.

---

# 45. Default decisions unless later evidence changes them

These choices are intentional so future implementation sessions do not repeatedly reopen settled questions.

1. **Target KOReader `v2025.04` through Gate 4, then deliberately migrate to official `v2026.07.1` at Gate 4A before Phase G.**
2. **Manual sync first; no background sync V1.**
3. **Do not control Wi-Fi.**
4. **SQLite for sync state/queue.**
5. **LuaSettings for small config/token.**
6. **Reader ID is document identity.**
7. **Sidecar `annotations` is annotation source of truth.**
8. **No `My Clippings.txt` dependency.**
9. **No filename/title-based annotation identity.**
10. **Use Reader v3 for library and linked highlight creation.**
11. **Use Readwise v2 only where API spike proves it is required/reliable.**
12. **Deletion propagation off by default.**
13. **Remote archive does not imply local deletion.**
14. **Atomic document replacement.**
15. **Conservative content refresh when local reading state exists.**
16. **No aggressive fuzzy text matching.**
17. **No blind retry after ambiguous highlight POST timeout.**
18. **Preserve notes literally.**
19. **New Obsidian annotations are in scope; automatic rewriting of already-exported edited notes is not.**
20. **Every implementation session updates STATUS.md.**

---

# 46. Open questions — resolve by spikes, not speculation

- Does Reader v3 highlight create return an ID that can be deterministically mapped to Readwise v2?
- Does Reader v3 DELETE on a highlight child behave exactly as desired?
- What child-document shape does a Reader highlight/note expose today?
- How does Reader match repeated identical `content` within one document?
- Does Reader's exact-content requirement compare decoded visible text exactly as documented examples imply for HTML entities/soft hyphens?
- Which KOReader sidecar API is safest for closed-document annotation reads on the post-Gate-4A target (expected `v2026.07.1`)?
- Resolved Gate 14 P0: canonical Finished signal on the target is persisted `doc_settings.summary.status == "complete"`; `percent_finished` is not authoritative.
- Do relative local image files render robustly in CRengine HTML on PW3?
- How much HTML/image content can this PW3 handle comfortably?
- How stable are XPointer positions after replacing an HTML document with changed content?
- Can original EPUB/PDF updates preserve sidecar positions reliably?
- What specific filesystem free-space API is cleanest on Kindle through KOReader?
- Does the user's Readwise → Obsidian template preserve raw `[[...]]` exactly without needing template adjustment?

Each answer must be captured in a documentation or code change; do not rely only on chat memory.

---

# 47. References

Current API/docs:
- Reader API: https://readwise.io/reader_api
- Readwise API: https://readwise.io/api_deets
- Readwise → Obsidian: https://docs.readwise.io/readwise/docs/exporting-highlights/obsidian
- Export refresh behavior: https://docs.readwise.io/readwise/docs/exporting-highlights

KOReader:
- KOReader v2025.04 source: https://github.com/koreader/koreader/tree/v2025.04
- KOReader v2026.07.1 source: https://github.com/koreader/koreader/tree/v2026.07.1
- KOReader v2026.07.1 release: https://github.com/koreader/koreader/releases/tag/v2026.07.1
- Bookshelf v5.1.4 release: https://github.com/AndyHazz/bookshelf.koplugin/releases/tag/v5.1.4
- migration runbook: `docs/KOREADER_UPGRADE.md`
- ReaderAnnotation v2025.04: `frontend/apps/reader/modules/readerannotation.lua`
- DocSettings v2025.04: `frontend/docsettings.lua`
- Hello plugin v2025.04: `plugins/hello.koplugin/main.lua`

Existing Readwise plugin reference:
- https://github.com/koreader/contrib/tree/main/readwisereader.koplugin

---

# 48. Immediate next action

Continue the **0.1.47 Gate 16 PW3 release-candidate smoke** from the physically passed restart-while-offline persistence checkpoint.

Already physically passed:
- plugin/startup + settings/token preservation;
- existing managed article reading state preservation;
- first ordinary Wi-Fi-on Sync;
- unchanged second Sync/no-op idempotency;
- controlled offline local highlight/note -> durable create queue with zero remote writes;
- fresh KOReader restart while still offline -> local annotation + SQLite pending queue persisted, read-only reconnect diagnostic made zero remote writes.

Deterministic exactly-once coverage before reconnect:
- offline queued work survives a reconstructed uploader/restart state;
- reconnect creates the pending highlight once, marks the durable queue succeeded and waiting count reaches zero;
- a later fresh uploader over the same durable state performs zero further creates/reconciliation for that item;
- ambiguous timeout/server outcomes remain reconcile-before-retry and never blind-POST duplicates.

Next checkpoint — **reconnect exactly once**:
1. turn Wi-Fi back ON from KOReader and confirm connectivity is available;
2. do not edit/recreate the Gate 16 highlight/note;
3. run ordinary **Sync now exactly once**;
4. require exactly one create or safe reconcile for the pending fixture;
5. require create queue waiting after Sync = 0 for the fixture;
6. require no duplicate highlight/POST, no fatal errors and no unexpected document replacement;
7. verify in Reader that the exact note/text arrived on the correct parent document once;
8. return the full Sync report and remote verification result;
9. stop before the final restart/log-secret review.

Only after this checkpoint passes:
- restart KOReader one more time;
- reopen the same article and verify progress/highlights/notes persist;
- verify plugin + Bookshelf still load;
- review crash.log locally for token/Authorization/signed URL/private payload leakage.

Gate 16 remains **OPEN** until the exactly-once reconnect and final restart/log review both pass.
