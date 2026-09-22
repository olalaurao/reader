# Implementation Status

> This file is the resumability ledger for implementation. Update it after every meaningful work session.  
> Canonical design: `IMPLEMENTATION_SPEC.md`  
> Roadmap/product intent: `PLAN.md`

## Current milestone

**Phase C — storage foundation COMPLETE off-device; ready to integrate before Phase D**

Gate 1 remains passed on the target PW3. Phase B was merged to `main` through PR #2 as `0538b00c8ac4237afd42db9ed6c8dcc0737dffdd`. Phase C C1/C2 is implemented and CI-validated. There is no physical gate between Phase C and Phase D, so Reader metadata work may begin after Phase C is integrated.

## Current branch / commit

- Branch: `phase-c/storage-foundation`
- Phase C base `main`: `0538b00c8ac4237afd42db9ed6c8dcc0737dffdd`
- C1 schema commit: `1ad0c060a0403a17ddaa5d7f72dbb4539c4ae4e6`
- CI dependency fix: `77ee86aa99c730d6bb8f41f9b539aada9890eafe`
- SQLite test compatibility fix / validated C1 tip: `803e9ea1a20fdaba8b0649253ff015278a44bc3d`
- C2 repositories commit: `123d1bb9c0e227f56c0acd7a63bca86883af8912`
- This documentation/status update follows the validated C2 code; inspect the branch tip when resuming.

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

No Phase C evidence required changing `IMPLEMENTATION_SPEC.md`. The implementation follows its SQLite schema/storage boundaries and does not persist temporary raw-source URLs.

## Blockers

No Phase C blocker remains. The next hard stop is **Gate 2**, after Phase D implements a metadata-only full-library scan on the real account/PW3.

Later hard gates remain:
- Reader v3 ↔ Readwise v2 highlight ID mapping;
- safe note-update path;
- safe highlight-delete path;
- exact-content matching edge cases;
- relative image assets on CRengine;
- content replacement vs existing KOReader positions/sidecars.

## Exact next steps

1. Integrate the validated Phase C branch into `main` without rewriting history.
2. Create a Phase D Reader-metadata branch from updated `main`.
3. Implement D1: Reader v3 LIST one page and required-field parsing.
4. Implement D2: cursor pagination, repeated-cursor guard, deduplication and rate-limit handling.
5. Add a metadata-only device action that reports total/pages plus location/category counts and performs no downloads or remote writes.
6. Run CI and package the Gate 2 build.
7. Stop at **Gate 2** for the full-library metadata scan on the target PW3 before Phase E.

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
