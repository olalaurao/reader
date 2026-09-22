# Implementation Status

> This file is the resumability ledger for implementation. Update it after every meaningful work session.  
> Canonical design: `IMPLEMENTATION_SPEC.md`  
> Roadmap/product intent: `PLAN.md`

## Current milestone

**Phase A — repository/bootstrap COMPLETE; Gate 0 PASSED on target PW3**

Gate 0 was physically validated on 2026-09-22. The plugin appeared in the KOReader menu, the bootstrap dialog opened, and removing the plugin restored normal baseline behavior. Phase B may now begin after the validated bootstrap branch is integrated into `main`.

## Current branch / commit

- Branch: `phase-a/bootstrap-gate0`
- Validated implementation/code HEAD: `98f7526c8d8c0295ee8b3c4ee64b76701d394c61`
- This STATUS update is the next commit on the same branch; when resuming, inspect the branch tip rather than relying on a self-referential hash in this file.
- Base `main` at session start: `fea2c10f4e6fc1d17f9586960f846608ad4b54d2`

## Target environment

- Kindle Paperwhite 3 / 7th generation
- Serial prefix: `G090KB`
- Firmware: `5.16.2.1.1 (4097470002)`
- Jailbreak/KUAL functional
- KOReader: `2025.04`

## Files changed this session

Added/updated on `phase-a/bootstrap-gate0`:

- `.gitignore`
- `.github/workflows/test.yml`
- `CHANGELOG.md`
- `LICENSE`
- `NOTICE.md`
- `README.md`
- `docs/DEVICE_TESTS.md`
- `readwisereader.koplugin/_meta.lua`
- `readwisereader.koplugin/main.lua`
- `scripts/dev-check.sh`
- `scripts/package.sh`
- `STATUS.md`

## What was implemented

### Licensing / provenance

- Inspected the existing community plugin lineage before copying any code.
- Confirmed AGPL-3.0 licensing.
- Recorded the reference lineage:
  - `Endle/readwisereader`
  - `tomtom800/readwisereader`
  - `koreader/contrib/readwisereader.koplugin`
- Added the complete AGPL-3.0 license and a provenance notice.
- Phase A's minimal shell was written against KOReader v2025.04's plugin loader / hello-plugin pattern rather than copied from the legacy monolithic plugin.

### Minimal KOReader plugin shell

- Added `readwisereader.koplugin/_meta.lua`.
- Added `readwisereader.koplugin/main.lua`.
- Plugin name: `readwisereader`.
- Menu label: **Readwise Reader**.
- Plugin is not document-only.
- Bootstrap version constant: `0.0.1`.
- Menu action opens a minimal `InfoMessage` confirming the bootstrap plugin loaded and is ready for Gate 0.
- No auth, network, database, Reader API or destructive behavior exists yet.

### Packaging / checks

- Added `scripts/dev-check.sh`.
- Added `scripts/package.sh`.
- Package output is `dist/readwisereader.koplugin.zip`.
- ZIP root expands to `readwisereader.koplugin/`.
- Added GitHub Actions workflow to:
  - install Lua 5.1 + zip;
  - run syntax checks;
  - build the installable ZIP;
  - verify package layout;
  - upload the Gate 0 ZIP artifact.
- Added Gate 0 backup/install/rollback instructions to README and `docs/DEVICE_TESTS.md`.

## What works

- Repository/bootstrap documentation exists.
- Minimal plugin package builds deterministically enough for Gate 0.
- CI validates Lua syntax with Lua 5.1.
- CI validates the required package layout.
- No token or Reader credential is needed or handled by this build.
- Rollback is removing only `koreader/plugins/readwisereader.koplugin/` and restarting KOReader.

## Tests executed and results

### Physical Gate 0 — target PW3

Date: 2026-09-22

Result: **PASS**

User-reported checks:
- Readwise Reader menu appeared: **yes**;
- bootstrap popup opened: **yes**;
- removing the plugin restored normal KOReader behavior: **yes**.

This validates install/load/menu registration and rollback on the required target hardware.



### GitHub Actions — authoritative bootstrap CI

Commit: `98f7526c8d8c0295ee8b3c4ee64b76701d394c61`

Run:
- workflow `test`, run #1
- result: **success**
- bootstrap job: **success**

Successful steps:
- checkout;
- install Lua 5.1 and zip;
- `./scripts/dev-check.sh`;
- `./scripts/package.sh`;
- verify `readwisereader.koplugin/_meta.lua` is present in ZIP;
- verify `readwisereader.koplugin/main.lua` is present in ZIP;
- upload Gate 0 artifact.

### Local supplementary checks

- `sh -n scripts/dev-check.sh`: passed.
- `sh -n scripts/package.sh`: passed.
- Lua parse of `_meta.lua` through `loadfile`: passed.
- Lua parse of `main.lua` through `loadfile`: passed.
- Package creation: passed.
- `unzip -t` on generated package: passed.
- Package contains only the expected bootstrap directory/files.

## Gates completed

- **Gate 0: PASSED on 2026-09-22 on the target PW3 / KOReader 2025.04.**
- Phase A/A1 repository/bootstrap implementation: complete.
- Phase A/A2 physical bootstrap/rollback validation: complete.

## Physical tests pending

No Phase A physical test remains.

Next physical gate:
- **Gate 1**, after Phase B implements local token configuration and the auth test flow.
- Gate 1 must validate a real token on the target PW3 without exposing the credential.

## Bugs / failures found

- No implementation bug was found in the bootstrap shell or package CI.
- The implementation environment could not clone GitHub directly because outbound DNS/network is blocked; repository reads/writes were performed through the GitHub connector instead. This is a tooling/environment limitation, not a repository blocker.
- A local attempt to use TeX Live's `texluac -p` as if it were standard `luac -p` was invalid and was discarded. The authoritative Lua 5.1 syntax check is the successful GitHub Actions run.

## Technical decisions made

- Keep the project under AGPL-3.0 to remain compatible with future reuse/adaptation of the existing AGPL community implementation.
- Use a newly written minimal shell for Gate 0 rather than porting legacy behavior prematurely.
- Follow the KOReader v2025.04 plugin loader and `hello.koplugin` registration pattern.
- Do not introduce dispatcher actions, settings, networking or database code before Gate 0.
- Use version `0.0.1` for the bootstrap package.
- Package the plugin with the `readwisereader.koplugin/` directory at ZIP root.
- Treat GitHub Actions Lua 5.1 checks as the authoritative off-device bootstrap syntax gate.

## Spec deviations

None.

No evidence discovered in this session requires changing `IMPLEMENTATION_SPEC.md`.

## Blockers

No Phase A blocker remains. Gate 0 has passed, so Phase B may begin once the bootstrap branch is integrated into `main`.

Later hard gates remain:
- Reader v3 ↔ Readwise v2 highlight ID mapping;
- safe note-update path;
- safe highlight-delete path;
- exact-content matching edge cases;
- relative image assets on CRengine;
- content replacement vs existing KOReader positions/sidecars.

## Exact next steps

1. Integrate `phase-a/bootstrap-gate0` into `main` without rewriting validated history.
2. Create a dedicated Phase B branch from the updated `main`.
3. Implement B1 only: LuaSettings config, masked token entry, replace/clear, zero token logging.
4. Add tests/static checks for token redaction and configuration behavior where feasible.
5. Implement B2 auth transport/test connection using the official `GET /api/v2/auth/` contract only after B1 is sound.
6. Package the Phase B build.
7. Stop at **Gate 1** and run it physically on the PW3 before beginning Phase C.

## Existing architectural decisions still in force

- KOReader 2025.04 is the first compatibility target.
- Manual sync only in V1.
- Plugin does not toggle Wi-Fi.
- Reader is the source for library content; Kindle/KOReader is the primary reading surface.
- Use Reader v3 for library and parent-linked highlight creation.
- Use Readwise v2 only after proving ID interoperability where needed.
- Use SQLite for documents/annotation links/queue/sync watermarks.
- Use LuaSettings for small user config/token.
- Read KOReader's `annotations` sidecar data directly.
- Do not use `My Clippings.txt` as source of truth.
- Preserve note text literally, including `[[wikilinks]]`.
- Deletion propagation is OFF by default.
- Remote archive does not delete local files in V1.
- Do not blindly retry highlight creation after an ambiguous timeout.

Never rely on chat history alone for project state.
