# Implementation Status

> This file is the resumability ledger for implementation. Update it after every meaningful work session.  
> Canonical design: `IMPLEMENTATION_SPEC.md`  
> Roadmap/product intent: `PLAN.md`

## Current milestone

**Phase A — repository/bootstrap, Gate 0 ready for physical device validation**

Phase A implementation work that does not require the Kindle is complete. Do **not** begin Phase B until Gate 0 passes on the target PW3.

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

- No numbered device gate is complete yet.
- Phase A/A1 repository/bootstrap implementation is complete enough to enter Gate 0.
- **Gate 0 remains OPEN and must not be marked complete before the PW3 physical test passes.**

## Physical tests pending

### Gate 0 — required next

On the target PW3 / KOReader 2025.04:

1. Back up `koreader/settings/` and `koreader/plugins/`.
2. Extract the Gate 0 ZIP.
3. Copy `readwisereader.koplugin/` to `koreader/plugins/`.
4. Restart KOReader.
5. Confirm **Readwise Reader** appears in the menu.
6. Tap it.
7. Confirm the info dialog reports bootstrap version `0.0.1` loaded successfully.
8. Close KOReader.
9. Remove only `koreader/plugins/readwisereader.koplugin/`.
10. Restart KOReader.
11. Confirm baseline behavior returns and the menu item is gone.

Return:
- pass/fail for steps 5, 7 and 11;
- exact visible error if any;
- relevant sanitized `koreader/crash.log` tail if there is a failure.

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

Only one blocker prevents further implementation:

- **Gate 0 requires the physical Kindle PW3 test.**

Per the canonical spec, Phase B authentication/config must not begin until that test passes.

Later hard gates remain:
- Reader v3 ↔ Readwise v2 highlight ID mapping;
- safe note-update path;
- safe highlight-delete path;
- exact-content matching edge cases;
- relative image assets on CRengine;
- content replacement vs existing KOReader positions/sidecars.

## Exact next steps

1. Run physical Gate 0 on the PW3 using the packaged `readwisereader.koplugin.zip`.
2. Record the Gate 0 result in `docs/DEVICE_TESTS.md` and this file.
3. If Gate 0 fails, inspect the sanitized KOReader log and fix **Phase A only** until it passes.
4. If Gate 0 passes, close Phase A and integrate the validated bootstrap branch into `main`.
5. Create the Phase B branch.
6. Implement B1 only: LuaSettings config, masked token entry, replace/clear, zero token logging.
7. Implement B2 auth transport/test connection only after B1.
8. Run Gate 1 physically before advancing to Phase C.

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
