# Implementation Status

> This file is the resumability ledger for implementation. Update it after every meaningful work session.  
> Canonical design: `IMPLEMENTATION_SPEC.md`  
> Roadmap/product intent: `PLAN.md`

## Current milestone

**Phase D — Reader metadata complete; Gate 2 PASSED on target PW3**

Gate 1 remains passed. Phase C was merged into `main` through PR #3 as `6db5a6802c3acd7378989e3776829ec3a4c0bf65`. Gate 2 now passes on the target PW3 / KOReader 2025.04: the full Reader library scan completed, the corrected 0.0.4 scan/cancel surface was visibly rendered and cancellable, the UI stayed responsive, Wi-Fi state was not changed, and no documents were downloaded or modified. Phase D is ready to merge; after merge, Phase E may begin.

## Current branch / commit

- Branch: `phase-d/reader-metadata-gate2`
- Phase D base `main`: `6db5a6802c3acd7378989e3776829ec3a4c0bf65`
- D1 LIST client: `02b749ebe0539b74cbf4cf604b7e9f006ad89c78`
- D1 JSON-test fix / validated D1: `5b560b24b6fc908a70a5a587a6a73c7f1d5fec90`
- D2 pagination/dedupe/cursor guards: `23456463d6de8f9e98d50275e584f7cac2762216`
- D3 metadata-only Gate 2 UI: `d77cda0244fbda8c1d97eb4b8842d90b86d6d5be`
- LIST pacing: `4d8f6dc7405154a599817086ddfb39dda5db325a`
- Cancellation propagation: `859f724e2ae659ff45debef6b579dec84c1e8675`
- Fast deterministic pacing fixtures: `5da20ae06472f02fdaae5b1bf730b2a9dd54db60`
- Retry-After handling: `ea5ac3ff52497e83b3596461d8ec7c5bdac93dd2`
- Final pacing-loop fix / first device-build code tip: `50fe2ad9bbb362b94eebc7d73bc30816e557965d`
- First Gate 2 docs/package tip: `813dcbe901e54920389d9a4e7cf9c03fc8fb30cd`
- Gate 2 UI coroutine fix / 0.0.4: `c4074d4746f77ebf28bfcee29046d97a900ff9ec`
- UI test-fixture fixes: `b474e9622d724ff934dc13d3c65499d0e7ed57da`, `7001fd0a16959dc85ee9c64d0764ca1e7cc7312f`
- Run #35 on `7001fd0a16959dc85ee9c64d0764ca1e7cc7312f`: **SUCCESS**.
- This documentation/status update follows the validated 0.0.4 code; inspect the branch tip when resuming.

## Target environment

- Kindle Paperwhite 3 / 7th generation
- Serial prefix: `G090KB`
- Firmware: `5.16.2.1.1 (4097470002)`
- Jailbreak/KUAL functional
- KOReader: `2025.04`

## Phase A result

- Gate 0: **PASSED** on 2026-09-22.
- Readwise Reader menu appeared.
- Bootstrap popup opened.
- Removing the plugin restored normal KOReader behavior.
- Phase A PR #1 was merged into `main` as `e050f21246706ee25c79f011ba1cfdc389c827bd`.

## Files changed in Phase B

Added/updated on `phase-b/config-auth-gate1`:

- `.github/workflows/test.yml`
- `CHANGELOG.md`
- `README.md`
- `STATUS.md`
- `docs/DEVICE_TESTS.md`
- `readwisereader.koplugin/_meta.lua`
- `readwisereader.koplugin/constants.lua`
- `readwisereader.koplugin/config.lua`
- `readwisereader.koplugin/main.lua`
- `readwisereader.koplugin/api/http.lua`
- `readwisereader.koplugin/api/reader.lua`
- `readwisereader.koplugin/ui/settings.lua`
- `readwisereader.koplugin/tests/run.lua`
- `readwisereader.koplugin/tests/test_config.lua`
- `readwisereader.koplugin/tests/test_http.lua`
- `readwisereader.koplugin/tests/test_reader.lua`
- `scripts/package.sh`


## Phase D result

### D1 — Reader v3 LIST one page

- Added Reader v3 `GET /api/v3/list/` support with `Authorization: Token <TOKEN>`.
- Added deterministic percent-encoded query construction for:
  - `id`;
  - `updatedAfter`;
  - `location`;
  - `category`;
  - repeated `tag`;
  - `limit` (validated 1..100);
  - `pageCursor`;
  - `withHtmlContent`;
  - `withRawSourceUrl`.
- Metadata scans explicitly request neither HTML bodies nor raw-source URLs.
- Added JSON decoding and response-shape validation.
- Documents without a valid Reader ID are rejected as malformed rather than silently accepted.
- The normalized document shape includes the documented metadata needed by later phases.
- No remote-write endpoint was added.

### D2 — complete pagination / safety

- Added sequential cursor pagination with `limit=100`.
- Added repeated-cursor detection.
- Added guard against an empty page that still advertises another cursor.
- Deduplicates records by Reader document ID across pages while recording duplicate count.
- Keeps only IDs in the dedupe set; it does not retain all document bodies/pages in memory.
- Propagates partial scan metrics with failures.
- Added cooperative cancellation checks.
- Added proactive LIST pacing at 3.1 seconds between request starts, slightly below the documented 20 requests/minute ceiling.
- Added bounded 429 recovery:
  - honors numeric `Retry-After` when supplied;
  - otherwise uses bounded 5s/15s fallback delays;
  - retries the same page at most twice;
  - never advances the cursor or dispatches page data before a successful response.
- Sleep/pacing is cancellation-aware.

### D3 — Gate 2 metadata-only UI

- Plugin version advanced to experimental `0.0.4` after the first device scan exposed a UI/cancellation wiring bug.
- Added **Readwise Reader → Scan Reader metadata (Gate 2)**.
- Requires an already-configured token and checks current connectivity only; it does not enable Wi-Fi.
- Runs the scan through `Trapper:wrap()` and then KOReader's `Trapper:dismissableRunInSubprocess`, which is the required KOReader 2025.04 pattern for a visible/dismissable subprocess operation.
- The first 0.0.3 build omitted the outer `Trapper:wrap()`; KOReader therefore fell back to a blocking in-process execution. This is fixed in 0.0.4 and covered by a UI wiring unit test.
- Full-library result reports:
  - top-level Reader documents;
  - API pages;
  - duplicate records ignored;
  - child records ignored;
  - counts by Reader location;
  - counts by category.
- Child records with `parent_id` are counted diagnostically but never treated as top-level reading documents.
- Gate 2 scan does **not**:
  - download or materialize any document;
  - request `html_content`;
  - request `raw_source_url`;
  - write Reader/Readwise state;
  - enqueue annotation/archive operations;
  - toggle Wi-Fi.

### Phase D automated validation

- Run #24 on `5b560b24b6fc908a70a5a587a6a73c7f1d5fec90`: **SUCCESS** — D1 request/query/parser tests.
- Run #25 on `23456463d6de8f9e98d50275e584f7cac2762216`: **SUCCESS** — multi-page pagination, dedupe, repeated cursor, malformed empty-loop, cancellation, 429 propagation.
- Run #26 on `d77cda0244fbda8c1d97eb4b8842d90b86d6d5be`: **SUCCESS** — metadata scanner/UI wiring and package.
- Run #31 on `50fe2ad9bbb362b94eebc7d73bc30816e557965d`: **SUCCESS** — final Phase D code including 21-page pacing simulation, cancellation during pacing, bounded Retry-After recovery, syntax, all unit tests, package and ZIP layout.

## Physical Gate 2 result — attempt 1

Date: 2026-09-22  
Build: `0.0.3` / package based on `813dcbe901e54920389d9a4e7cf9c03fc8fb30cd`  
Result: **PARTIAL PASS — full traversal succeeded; responsiveness/cancellation failed**

Observed on the target PW3 / KOReader 2025.04:
- full metadata scan completed and reached the final report;
- top-level documents: **1329**;
- API pages: **25**;
- duplicate records ignored: **0**;
- child records ignored: **1122**;
- locations:
  - archive: **176**;
  - feed: **40**;
  - later: **51**;
  - new: **1062**;
- categories:
  - article: **843**;
  - epub: **88**;
  - pdf: **31**;
  - podcast: **14**;
  - rss: **40**;
  - video: **313**;
- the final UI explicitly reported: **No documents were downloaded or changed.**
- no cursor-loop, pagination error or final rate-limit failure was observed.

Failure:
- while the scan was running, no progress/cancel widget was visible;
- the KOReader UI appeared blocked/frozen until the scan completed;
- cancellation could therefore not be exercised.

Root cause verified against the pinned KOReader 2025.04 `frontend/ui/trapper.lua`:
- `dismissableRunInSubprocess()` is interactive only when called from a Trapper coroutine;
- when called unwrapped, it deliberately logs a warning and falls back to a blocking in-process run;
- the 0.0.3 Gate 2 menu path was missing the outer `Trapper:wrap()`.

Fix:
- `0.0.4` wraps the online scan as the final menu callback action with `Trapper:wrap()`;
- the subprocess call remains inside that wrapped function;
- added a unit test proving the online path enters `wrap()` before `dismissableRunInSubprocess()` and that the offline path starts no scan;
- run #35 passed.

Gate 2 remains **OPEN** until the 0.0.4 device retest confirms visible progress/cancellation and a successful full scan without the blocking behavior.

## Physical Gate 2 result — attempt 2 / PASS

Date: 2026-09-22  
Build: `0.0.4` / branch `phase-d/reader-metadata-gate2`  
Result: **PASS** on the target PW3 / KOReader 2025.04.

Observed:
- the scan status/cancel surface was visibly rendered on-device; its placement was lower/left rather than centered, which is cosmetic and does not affect Gate 2 criteria;
- tapping the visible scan surface cancelled the scan successfully;
- KOReader remained responsive after cancellation;
- a subsequent full metadata scan completed successfully and displayed the complete summary;
- the scan did not leave KOReader stuck/unresponsive;
- the plugin did not alter Wi-Fi state;
- no Reader document was downloaded, created or changed.

Combined with attempt 1, Gate 2 evidence now covers:
- complete real-account traversal: **25 API pages / 1329 top-level documents**;
- no cursor loop;
- no duplicate API records emitted twice;
- no final rate-limit failure;
- responsive/cancellable device behavior;
- metadata-only/read-only behavior.

Conclusion:
- **Gate 2 PASSED.**
- Phase D can be merged to `main`.
- Phase E is unblocked.

## Phase C result

### C1 — SQLite/schema/migrations

- Added database path `<DataStorage:getSettingsDir()>/readwisereader.sqlite3`.
- Uses KOReader's `lua-ljsqlite3/init` in production.
- Uses WAL when `Device:canUseWAL()` is true and TRUNCATE otherwise.
- Enables foreign keys and a 5-second busy timeout.
- Added schema version 1 with `PRAGMA user_version`.
- Added transactional forward migration with rollback on failure.
- Future nonzero schema migrations require a `.bak` copy before changing the database.
- Added `documents`, `annotation_links`, `queue` and `sync_meta` tables plus indexes defined by the spec.

### C2 — storage repositories

- Added a documents repository keyed strictly by Reader document ID.
- Remote metadata upserts preserve local path/content state.
- Title/location changes update the same row rather than creating duplicates.
- Temporary `raw_source_url` is intentionally not represented in the durable document repository.
- Added annotation-link storage keeping Reader child IDs and Readwise v2 IDs separate.
- Added durable queue insertion by unique idempotency key.
- Duplicate enqueue returns the existing operation without replacing its payload.
- Added startup-style recovery of stale `in_flight` queue rows back to `pending`.
- Added `sync_meta` get/set/delete storage for future watermarks and scan markers.
- No remote write behavior was added.

### Phase C tests

GitHub Actions run #17 on `803e9ea1a20fdaba8b0649253ff015278a44bc3d`: **SUCCESS**

Validated C1 against real SQLite in CI:
- fresh schema and schema version;
- foreign keys;
- queue uniqueness;
- annotation foreign key;
- transaction rollback;
- migration rollback path;
- package/syntax checks.

GitHub Actions run #18 on `123d1bb9c0e227f56c0acd7a63bca86883af8912`: **SUCCESS**

Validated C2:
- document upsert and stable Reader identity across rename/location change;
- preservation of local document state;
- no persistence of temporary raw-source URL input;
- annotation remote-link preservation across later local scans;
- separate Reader v3 child and Readwise v2 ID fields;
- queue idempotency;
- stale in-flight recovery;
- sync_meta lifecycle;
- package/syntax checks.

## What was implemented

### B1 — local configuration / access token

- Added `LuaSettings`-backed config at `<DataStorage:getSettingsDir()>/readwisereader.lua`.
- Token is intentionally local plaintext because KOReader settings are plaintext; it is not described as encrypted.
- Added password-masked token entry.
- Saved token value is never displayed after saving; menu exposes only configured/not-set state.
- Added replace and clear behavior.
- Blank/whitespace-only token is rejected.
- Token is not copied into SQLite or any other state.
- No token logging was introduced.

### B2 — auth transport / Test connection

- Added a small HTTP transport abstraction using KOReader/LuaSocket patterns:
  - `socket.http`;
  - `ltn12`;
  - KOReader `socketutil` timeout helpers.
- Socket timeout is reset after each attempted request, including thrown errors.
- Request logging contains only HTTP method and URL without query parameters; Authorization headers are never logged.
- Normalized error classes implemented for:
  - offline/network;
  - timeout;
  - TLS;
  - rate limit + numeric `Retry-After` when available;
  - auth;
  - other client errors;
  - server errors;
  - unknown errors.
- Added Reader auth wrapper using:
  - `GET https://readwise.io/api/v2/auth/`;
  - `Authorization: Token <TOKEN>`;
  - expected success `204`.
- Added **Settings → Account → Test connection**.
- User-facing results distinguish valid token, rejected token, offline, timeout, TLS, rate limit, server and unknown errors.
- The plugin checks `NetworkMgr:isOnline()` only. It deliberately does **not** use `runWhenOnline`, `beforeWifiAction` or any Wi-Fi enable/disable flow.

### Packaging/tests

- Version advanced to experimental `0.0.2`.
- Lua unit tests now run in CI.
- Installable ZIP excludes development tests.
- Gate 1 device instructions explicitly document token cleanup in addition to plugin rollback.

## What works off-device

- Config set/get/clear behavior.
- Whitespace trimming and empty-token rejection.
- Auth request construction.
- 204 success handling.
- 401/403 auth failure classification.
- 429 + `Retry-After`.
- timeout/offline/TLS/server classification helpers.
- timeout reset even when the HTTP stack throws.
- token/query redaction from normal request logging.
- deterministic package layout without test files.

## Tests executed and results

### B1 GitHub Actions

Commit: `2b9d5ebb1ab72ad6729f474a20f7b869fc964130`  
Workflow run #8: **SUCCESS**

Validated:
- Lua 5.1 syntax;
- config unit tests;
- packaging;
- required ZIP structure;
- development tests excluded from ZIP.

### B2 GitHub Actions

Commit: `6e776d8c903b846ff5f89b0aa06a4bf88394d7f9`  
Workflow run #9: **SUCCESS**

Validated:
- Lua 5.1 syntax for all plugin/test files;
- config tests;
- HTTP transport/error/redaction tests;
- Reader auth wrapper tests;
- packaging;
- required ZIP structure;
- development tests excluded from ZIP.

### External contracts checked before B2

Against current Readwise documentation:
- authentication uses `Authorization: Token <TOKEN>`;
- validation endpoint is `GET /api/v2/auth/`;
- successful validation returns `204`.

Against KOReader v2025.04 source:
- `LuaSettings` supports local settings + flush/backups;
- password fields use `text_type = "password"`;
- `socketutil` provides timeout/table-sink helpers;
- `NetworkMgr:isOnline()` checks online state, while `runWhenOnline()` can enter Wi-Fi connection flows and is therefore intentionally not used.

## Gates completed

- Gate 0: **PASSED**.
- B1 off-device implementation: complete.
- B2 off-device implementation: complete.
- **Gate 1: PASSED — 2026-09-22 on target PW3 / KOReader 2025.04.**

## Physical Gate 1 result

Date: 2026-09-22  
Result: **PASS** on the target PW3 / KOReader 2025.04.

Validated:
- token field masked;
- valid token authenticated successfully;
- incorrect/invalid token rejected cleanly;
- offline state detected with Wi-Fi off;
- plugin did not enable Wi-Fi;
- token clear path worked without exposing the credential.

The real token was entered locally through `koreader/settings/readwisereader.lua` over USB after manual Kindle entry proved impractical. No token value was shared or committed.

Next physical gate: **Gate 2**, after Phase C storage and Phase D Reader metadata implementation.

## Bugs / failures found

- Gate 2 device attempt 1 proved the API traversal itself works on the real account (25 pages / 1329 top-level docs) but exposed a real PW3 UI bug: `dismissableRunInSubprocess()` was invoked without `Trapper:wrap()`, so KOReader 2025.04 fell back to blocking in-process execution. Fixed in 0.0.4.
- Runs #33/#34 failed only in the newly-added UI test fixture while its module-cache reset was being corrected; the production fix already passed syntax. Run #35 passed the corrected fixture and full suite.
- Phase D run #23 exposed a test-injection bug: the injected JSON decoder was shaped like KOReader's JSON module but the test supplied a function. Production parsing design was unchanged; decoder injection was simplified and run #24 passed.
- After D3, review against the current Reader contract found that merely handling 429 was insufficient for a full library: unrestricted pagination could itself exceed the documented 20 LIST requests/minute ceiling. Proactive 3.1s request pacing was added before Gate 2.
- Cancellation was initially not forwarded into the per-page pacing call because the copied option was cleared; this was corrected before device testing.
- A synthetic 21-page pacing test then exposed a sub-millisecond floating-point residue loop in the simulated clock. The pacing guard now ignores <1ms residue; final run #31 passed.
- Phase C run #15 failed before tests because the workflow accidentally contained a literal `\\n` inside the apt command; the workflow was corrected.
- Phase C run #16 reached the storage tests and exposed a test-only `lsqlite3` compatibility bug: `get_values()` already returns an array. The shim was corrected; production schema code did not require a change.
- C1 then passed in run #17 and C2 passed in run #18.
- No B1/B2 implementation failure remains in CI.
- A single oversized Git-data connector request for the B2 commit was blocked by the connector before execution. Repository state was verified unchanged, and the exact work was safely retried as smaller Git object operations.
- Direct container Git/network access remains unavailable; repository operations use the GitHub connector. This is a tooling limitation, not a repository blocker.

## Technical decisions made

- Keep `main.lua` small: dependency construction/menu/lifecycle only.
- Keep token configuration in `config.lua`.
- Keep network transport in `api/http.lua`.
- Keep Readwise/Reader auth contract in `api/reader.lua`.
- Use KOReader's password input support rather than custom masking.
- Never prefill the token dialog with the stored secret.
- Do not expose a "show token" action.
- Persist config immediately on save/clear.
- Use `pcall` around low-level HTTP and reset socket timeout afterward.
- Treat all HTTP 2xx as transport success, while `validateToken()` requires the documented 204 specifically.
- Strip query parameters from request log URLs and never log request headers.
- Do not use KOReader network helpers that may toggle/connect Wi-Fi.

## Spec deviations

None.

Current Reader documentation still matches the Phase D contracts already written in `IMPLEMENTATION_SPEC.md`: cursor pagination, `limit <= 100`, metadata toggles, 20 LIST requests/minute and `Retry-After` behavior. No spec or PLAN change was required.

## Blockers

Gate 2 is passed. There is no remaining Phase D blocker to Phase E.

Later hard gates remain:
- Reader v3 ↔ Readwise v2 highlight ID mapping;
- safe note-update path;
- safe highlight-delete path;
- exact-content matching edge cases;
- relative image assets on CRengine;
- content replacement vs existing KOReader positions/sidecars.

## Exact next steps

1. Run CI on this final Phase D tip.
2. Merge Phase D into `main` through a normal pull request/merge, with no history rewrite.
3. Create Phase E from updated `main`.
4. Implement Phase E E1/E2 only until the Gate 3 package is ready:
   - select one known article without exposing private content in logs/tests;
   - fetch processed `html_content`;
   - safe filename;
   - minimal readable HTML;
   - atomic local install;
   - local metadata/state;
   - open the file through KOReader's validated 2025.04 document-open path.
5. Add automated tests for safe filename/HTML/install/API wiring where feasible.
6. Update `STATUS.md` before stopping.
7. Stop at Gate 3 physical validation; do not begin Phase F before Gate 3 passes.

## Existing architectural decisions still in force

- KOReader 2025.04 is the first compatibility target.
- Manual sync only in V1.
- Plugin does not toggle Wi-Fi.
- Reader is the source for library content; Kindle/KOReader is the primary reading surface.
- Reader v3 is used for library and parent-linked highlight creation.
- Readwise v2 is used only where later interoperability testing proves it required/reliable.
- SQLite will hold documents/annotation links/queue/watermarks.
- LuaSettings holds small user config/token.
- KOReader sidecar `annotations` is the annotation source of truth.
- Never use `My Clippings.txt` as source of truth.
- Preserve note text literally, including `[[wikilinks]]`.
- Deletion propagation is OFF by default.
- Remote archive does not delete local files in V1.
- Never blindly retry highlight creation after an ambiguous timeout.

Never rely on chat history alone for project state.
