# Implementation Status

> This file is the resumability ledger for implementation. Update it after every meaningful work session.  
> Canonical design: `IMPLEMENTATION_SPEC.md`  
> Roadmap/product intent: `PLAN.md`

## Current milestone

**Phase B — config/auth implemented off-device; Gate 1 ready for physical PW3 validation**

Gate 0 passed on the target PW3 on 2026-09-22. Phase A was merged into `main`. Phase B B1/B2 is now implemented and CI-validated. **Do not begin Phase C until Gate 1 passes on the target PW3.**

## Current branch / commit

- Branch: `phase-b/config-auth-gate1`
- Phase B base `main`: `e050f21246706ee25c79f011ba1cfdc389c827bd`
- B1 code commit: `2b9d5ebb1ab72ad6729f474a20f7b869fc964130`
- B2 validated code commit: `6e776d8c903b846ff5f89b0aa06a4bf88394d7f9`
- This documentation/status update follows the validated code commit; inspect the branch tip when resuming.

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
- **Gate 1: OPEN — physical PW3 test required next.**

## Physical tests pending

### Gate 1 — required next

Use the exact matrix in `docs/DEVICE_TESTS.md`.

Minimum required real-device evidence:
- token field is masked;
- saved token persists without being displayed;
- valid token succeeds;
- deliberately fake token is rejected cleanly;
- Wi-Fi-off path reports offline and does not turn Wi-Fi on;
- token can be cleared without exposure.

Do not send the real token in chat or Git.

## Bugs / failures found

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

No evidence found during Phase B requires changing `IMPLEMENTATION_SPEC.md`.

## Blockers

The only blocker to Phase C is **Gate 1 physical validation on the target PW3**.

Later hard gates remain:
- Reader v3 ↔ Readwise v2 highlight ID mapping;
- safe note-update path;
- safe highlight-delete path;
- exact-content matching edge cases;
- relative image assets on CRengine;
- content replacement vs existing KOReader positions/sidecars.

## Exact next steps

1. Install the Gate 1 `0.0.2` package on the target PW3.
2. Run G1.1–G1.5 from `docs/DEVICE_TESTS.md`; never share the real token.
3. Record the physical results in `docs/DEVICE_TESTS.md` and `STATUS.md`.
4. If Gate 1 fails, fix **Phase B only**, repackage and retest.
5. If Gate 1 passes, merge the validated Phase B branch into `main`.
6. Create the Phase C storage branch from updated `main`.
7. Implement C1 SQLite/schema/migrations/unit tests.
8. Implement C2 repositories/sync_meta only after C1 is sound.
9. Do not make remote content writes in Phase C.

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
