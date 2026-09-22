# Implementation Status

> This file is the resumability ledger for implementation. Update it after every meaningful work session.  
> Canonical design: `IMPLEMENTATION_SPEC.md`  
> Roadmap/product intent: `PLAN.md`

## Current milestone

**Phase A — repository/bootstrap**

## Current branch / commit

- Branch: `main`
- Last planning commit before this status file: `75d91c8e983c2074a8e23eee6b8b844b46d4a219`
- Implementation has **not started**.

## Target environment

- Kindle Paperwhite 3 / 7th generation
- Serial prefix: `G090KB`
- Firmware: `5.16.2.1.1 (4097470002)`
- Jailbreak/KUAL functional
- KOReader: `2025.04`

## What works

- GitHub repository exists.
- Product/V1 roadmap exists in `PLAN.md`.
- Complete execution architecture/spec exists in `IMPLEMENTATION_SPEC.md`.

## What is in progress

Nothing. Next work begins with Phase A.

## Key decisions already made

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
- Generate stable local annotation identity from Reader document ID + immutable creation datetime + canonical locator.
- Preserve note text literally, including `[[wikilinks]]`.
- Deletion propagation is OFF by default.
- Remote archive does not delete local files in V1.
- Do not blindly retry highlight creation after an ambiguous timeout.
- Existing Obsidian exports are append-oriented; later edits may require Readwise refresh/re-export.

## Research completed

- Verified Reader v3 LIST/create/update/bulk update/delete API behavior documented as of 2026-09-22.
- Verified Reader v3 supports parent-linked highlight creation with exact parent content.
- Verified Readwise v2 supports highlight PATCH/DELETE by numeric highlight ID.
- Verified mapping between v3 Reader child ID and v2 numeric ID is **not yet proven** and is a hard implementation spike.
- Verified KOReader v2025.04 stores annotations in `ReaderAnnotation.annotations` and saves them under sidecar setting `annotations`.
- Verified KOReader v2025.04 bundles SQLite via `lua-ljsqlite3/init`.

## Tests run

None on implementation code yet.

## Device test needed next

**Gate 0**

After the minimal plugin skeleton is committed and packaged:

1. copy `readwisereader.koplugin/` to `koreader/plugins/`;
2. restart KOReader;
3. verify "Readwise Reader" appears in the menu;
4. open a basic info dialog;
5. remove the plugin folder;
6. restart and confirm baseline behavior returns.

## Exact next steps

1. Inspect the existing community plugin's license/origin.
2. Add repository license/attribution as required.
3. Create `.gitignore`.
4. Add minimal README linking PLAN and implementation spec.
5. Scaffold `readwisereader.koplugin/_meta.lua`.
6. Scaffold minimal `main.lua` using KOReader v2025.04 hello-plugin pattern.
7. Add version constant.
8. Add packaging script or release ZIP path.
9. Syntax-check/package.
10. Ask for Gate 0 device test.
11. Record device result here.
12. Only after Gate 0: start Phase B auth/config.

## Known blockers / unknowns

None block Gate 0.

Later hard gates:
- Reader v3 ↔ Readwise v2 highlight ID mapping.
- safe note-update path;
- safe highlight-delete path;
- exact-content matching edge cases;
- relative image assets on CRengine;
- content replacement vs existing KOReader positions/sidecars.

## Session handoff template

At the end of future implementation sessions, replace/update the sections above and record:

```text
Current milestone:
Branch:
HEAD:
Files changed:
Behavior implemented:
Tests passed:
Device tests passed:
Failures:
New decisions:
Spec deviations:
Blockers:
Next 3–10 exact actions:
```

Never rely on chat history alone for project state.
