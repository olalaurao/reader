# Changelog
- Phase O hotfix 0.1.34 makes Kindle Airplane Mode authoritative for offline queueing. KOReader 2026.07.1 `NetworkMgr:isOnline()` only checks DNS reachability and the Kindle backend can restore Wi-Fi independently, so build 0.1.33 could still run the online path after the user enabled Airplane Mode. 0.1.34 reads the native `com.lab126.cmd airplaneMode` flag on Kindle, refreshes radio/connectivity state, and forces ordinary Sync now into local-queue-only mode whenever Airplane Mode is active.
- Phase O experimental 0.1.33 hardens outbound annotation creation for offline/reboot/retry scenarios. Ordinary Sync now can queue local annotations with Wi-Fi off; durable create intents survive restart; retryable preflight failures use `retry_wait`/`available_after`; 429/auth can retry only after safe reconciliation; timeout/5xx/stale in-flight outcomes are never blindly re-POSTed; and queue processing can resume independently of the original in-memory document session.
- Phase N hotfix 0.1.32 replaces unreliable Reader `source/saved_using` as the destructive delete authority with stronger cross-API identity: exact durable Reader child id + expected parent/category + exact Readwise v2 highlight whose `external_id` equals that Reader child id. DELETE success is not persisted until the Reader child is confirmed gone.
- Phase N hotfix 0.1.31 makes note update success end-to-end: after a Readwise v2 PATCH, the plugin polls the linked Reader v3 child before advancing the durable baseline. If v2 already has the desired note but Reader is stale, it performs a verified Reader v3 repair PATCH. This also repairs the premature-success state created by 0.1.30.
- Phase N hotfix 0.1.30 fixes false note conflicts caused by invisible representation differences between KOReader sidecars and Readwise (CRLF/LF and surrounding/trailing whitespace). Normalization is used only for comparison; the exact local note text remains the payload written to Readwise.
- Phase N hotfix 0.1.29 moves production note conflict detection/update to the deterministic Readwise v2 representation already proven in Gate 8: Reader child id is matched exactly to v2 `external_id`, the current remote note is read from v2, and note PATCH uses that exact v2 highlight. Reader v3 remains the parent/child identity check; remote deletion remains unchanged and strict.
- Phase N hotfix 0.1.28 fixes the remaining Gate 12 note-update blocker observed on the target PW3. Reader may return a linked highlight child without the expected saved_using/source marker even though its durable child ID, original parent ID and highlight category all match. Non-destructive note updates now accept that durable identity and can retry an item previously left blocked by the 0.1.27 identity check. Remote DELETE remains strict and still requires the exact per-annotation ownership marker.
- Phase N hotfix 0.1.27 fixes a Gate 12 regression for highlights created by pre-Gate-10 builds. Those older linked Reader children used the generic `saved_using = "KOReader Readwise Reader"`; note updates now accept that legacy ownership marker only when durable child ID + parent ID + highlight category also match. Destructive DELETE remains restricted to the newer exact per-annotation marker.
- Phase N experimental 0.1.26 adds linked highlight-note updates during **Sync now**, with three-way conflict detection against the last-synced note. If local and Reader notes both diverged, the plugin records a conflict and overwrites neither side.
- Highlight deletion propagation is now available under **Settings → Highlights**, remains OFF by default, requires an explicit destructive-action confirmation, and deletes only a durable linked Reader child whose id, parent, category and KOReader source marker all match. Local deletion with propagation OFF leaves Reader unchanged.
- Phase L experimental 0.1.25 connects current-document KOReader highlights to normal **Sync now** using Reader v3 parent-linked creation, literal note transport, durable remote child IDs, and a SQLite create queue.
- Highlight create uses a stable per-annotation `saved_using` marker. A timeout/crash or any previously-attempted create is blocked and reconciled by exact Reader `source` + parent identity before any retry; the plugin never blindly repeats an ambiguous POST. Gate 10 remains pending physical validation.
- Phase K experimental 0.1.24 adds a **read-only Gate 9 text-matching diagnostic** for the newest local highlight in the current managed Reader document. Matching now operates on Reader-visible text rather than raw HTML, decodes common/numeric entities, ignores non-visible script/style/comment content, handles inline-tag splits, Unicode NFC, whitespace/NBSP, soft hyphens and conservative straight/curly quote + dash equivalence, and rejects repeated ambiguous matches.
- The previously staged 0.1.23 remote-upload action is intentionally **not exposed in the menu** until Gate 9 passes; no Gate 9 diagnostic action creates, updates or deletes a remote annotation.
- Phase J experimental 0.1.22 adds a staged, disposable annotation API interoperability spike: Reader v3 child create/LIST/PATCH/DELETE, deterministic Reader↔Readwise v2 external-ID mapping probe, v2 note/color PATCH, cross-API delete observation, and recovery cleanup that only targets persisted Gate 8 disposable IDs.
- Refreshed the annotation architecture for the current Reader API contract: Reader v3 now explicitly documents `notes` and `tags` PATCH support on highlight children, so Gate 8 tests v3 note update directly instead of assuming v2 is mandatory.

- Phase I experimental 0.1.21 adds a read-only KOReader sidecar annotation adapter using `DocSettings`, deterministic SHA-256 local annotation IDs, literal note/text preservation, add/edit/delete detection and safe non-authoritative handling for missing files/sidecars.
- Added **Scan current annotations (Gate 7)** so one already-managed open document can prove exact text/note/locator identity on-device without scanning the full library or writing anything remotely.

- Phase H experimental 0.1.20 adds original Reader PDF/EPUB materialization through ephemeral `raw_source_url` links: bounded streaming to temp files, PDF/ZIP magic validation, atomic install, 64 MiB per-file cap, 128 MiB free-space reserve, original-format-first behavior and processed-HTML fallback only for safe non-transient raw-source failures.
- Added PDF/EPUB document-type toggles (still off by default), raw-format outcome counters, and a targeted **Test PDF / EPUB (Gate 6)** picker so the physical gate can validate one real PDF and EPUB without triggering a whole-library raw-format backfill.

- Phase G started with experimental 0.1.17: added an on-device CRengine spike for document-relative local image assets plus an intentionally missing asset to validate graceful failure on the PW3 before production image downloading is implemented.
- Experimental 0.1.18 implements bounded offline article image caching with relative local assets, a 2 MiB per-image cap, 8 MiB per-article image budget, 20-attempt limit, duplicate URL reuse within an article, and non-fatal placeholders for unavailable/unsupported/over-limit images.
- Added a `Download article images` document setting (default on), image outcome counters in sync summaries, and a bounded HTTP sink so oversized image responses are aborted before being fully accumulated in memory.

All notable project changes are recorded here.

## [Unreleased]

### Added

- Canonical V1 plan, implementation specification and resumable status ledger.
- AGPL-3.0 licensing and upstream provenance notice.
- Repository/bootstrap documentation and Gate 0 device validation.
- Local Readwise access-token configuration through KOReader `LuaSettings`.
- Password-masked token entry with replace/clear behavior.
- Readwise auth validation using the documented `GET /api/v2/auth/` contract.
- HTTP error classification for auth, offline/network, timeout, TLS, rate limit, client and server failures.
- Unit tests for configuration, auth request construction, token/log redaction behavior and HTTP error classification.
- SQLite schema v1 for documents, annotation links, durable queue and sync metadata.
- Transactional schema migration foundation with rollback and future migration backup support.
- Storage repositories keyed by stable Reader/local IDs, with queue idempotency and stale in-flight recovery.
- Real-SQLite CI coverage for schema constraints, rollback and storage repository invariants.
- Reader v3 metadata LIST client with validated query encoding and response parsing.
- Full cursor pagination with repeated-cursor/empty-loop guards and ID deduplication.
- Metadata-only Gate 2 full-library scanner with location/category/child/duplicate counts.
- Proactive Reader LIST pacing at 3.1 seconds between requests for the documented 20/minute limit.
- Bounded 429 retry handling that honors `Retry-After` and never advances a failed page cursor.
- Cancellable Gate 2 scanning via KOReader's subprocess trap pattern so long metadata/rate-limit waits remain dismissable.
- Unit coverage for 21-page pacing, cancellation, cursor loops, deduplication and rate-limit recovery.
- Gate 2 device attempt 1 proved a 25-page / 1329-document real-library metadata traversal, but exposed blocking UI in the 0.0.3 build.
- Fixed KOReader 2025.04 cancellation/progress wiring by entering `Trapper:wrap()` before `dismissableRunInSubprocess()`; experimental test build advanced to `0.0.4`.
- Added UI wiring coverage ensuring online scans enter the Trapper coroutine and offline scans never start the subprocess.
- Gate 2 passed on the target PW3 / KOReader 2025.04: real full-library metadata traversal, cancellation/responsiveness, no Wi-Fi control and no document mutation were all validated.
- Phase D merged to `main` through PR #4.
- Experimental `0.1.0` Gate 3 flow: on-device article selection, Reader LIST-by-ID processed HTML fetch, safe stable filenames, minimal UTF-8 HTML materialization, atomic temp/fsync/rename install, SQLite local-document state, KOReader custom metadata and safe ReaderUI opening.
- Unit coverage for Portuguese/emoji filenames, traversal/separator sanitization, UTF-8 byte truncation, body extraction, atomic no-overwrite installation, managed-file reuse and KOReader metadata/open wiring.
- Gate 3 attempt 1 on the PW3 exposed a silent selector UI transition failure after metadata loading.
- Experimental `0.1.1` fixes the selector transition by closing the originating TouchMenu, scheduling the selector after Trapper completion, and using KOReader's Menu + CenterContainer pattern; adds a dedicated UI flow unit test and user-visible fallbacks for selector/install/open failures.
- PW3 `crash.log` then identified the remaining selector failure: an untitled candidate caused Lua loop variable `_` to shadow gettext `_` (`attempt to call local '_' (a number value)`).
- Experimental `0.1.2` fixes the shadowing and adds an untitled-candidate regression test.
- Gate 3 passed on the target PW3 / KOReader 2025.04: selected article download/open, rendering, Unicode, reflow, search, highlight/note creation and close/reopen persistence were validated.
- Phase E merged to `main`; experimental `0.1.3` Phase F document sync implemented.
- Added configurable document root and Reader location/category filters.
- Added Reader-ID-owned full-first/incremental-later article sync with a canonical scan-start watermark and 5-minute overlap query bound.
- Added metadata/location updates without title-based duplicate files, plus idempotent managed Readwise Collections that preserve unrelated user collections.
- Added cancellable `Sync now`, sync status, first-sync confirmation and explicit full document rescan.
- Existing remote-changed local content is deferred safely instead of destructively replaced; content refresh remains Phase Q.
- Trapper child work is limited to network/atomic-file/SQLite operations; KOReader metadata and Collection settings are finalized in the parent process.
- Added transactional final watermark commit only after parent post-processing succeeds.
- Added post-processing/watermark failure tests, no-op second-sync/rename/location tests and rooted path-escape coverage.
- Added Phase F.5 / Gate 4A: after Gate 4 on KOReader 2025.04, migrate deliberately to official KOReader v2026.07.1 (`kindlepw2`) and then validate Bookshelf v5.1.4 before Phase G.
- Gate 4A-1 passed on the target PW3; KOReader v2026.07.1 is now the canonical physical baseline.
- Gate 4A-2 base coexistence with Bookshelf v5.1.4 passed after a controlled cleanup/recovery retest; Readwise articles open from Bookshelf, progress survives, close returns cleanly, and consecutive syncs remain idempotent.
- Reader location Collections were validated inside Bookshelf, including Reader-side moves and preservation of unrelated user Collections.
- Experimental 0.1.12 projects Reader document tags into KOReader custom `keywords`, which Bookshelf consumes as genres.
- Added a projection-version marker so existing managed articles get a one-time metadata-only Reader LIST backfill for tags without replaying the expensive HTML/content rescan.
- Empty Reader tag sets explicitly clear KOReader custom keywords, preventing fallback to stale embedded genres.
- Fixed 0.1.12 Reader-tag projection after device testing showed Bookshelf Genres empty: Reader Document LIST uses an object/map of tag records with nested `name` values, now normalized to canonical tag-name arrays.
- Optimized the one-time tag projection repair by querying only `category=article` and rewriting metadata only for tagged documents, while preserving normal incremental sync semantics.

## [0.0.2] - 2026-09-22

Config/auth build validated on the target PW3. Gate 1 passed for masked credential handling, valid and invalid authentication, offline detection without Wi-Fi control, and credential clearing. It does not sync Reader library content or annotations yet.

## [0.0.1] - 2026-09-22

Bootstrap plugin shell validated by Gate 0 on the target PW3 / KOReader 2025.04.
