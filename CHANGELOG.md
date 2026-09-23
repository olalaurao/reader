# Changelog
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
