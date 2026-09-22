# KOReader ↔ Readwise Reader

A KOReader plugin project for using a Kindle as an offline reading client for Readwise Reader, with safe synchronization of Reader-managed documents and KOReader annotations.

## Current status

Implementation is in **Phase A — repository/bootstrap**. The current build is only the Gate 0 plugin shell: it must first prove that a minimal external plugin loads correctly on the target Kindle/KOReader combination before network/authentication work begins.

No Readwise token is required for Gate 0, and this bootstrap build does not perform any network calls.

## Primary target

- Kindle Paperwhite 3 / 7th generation
- Kindle firmware 5.16.2.1.1
- KOReader 2025.04
- Manual sync only for V1

Do not update Kindle firmware or KOReader merely to test this project.

## Canonical project documents

- [PLAN.md](PLAN.md) — V1 product scope and roadmap.
- [IMPLEMENTATION_SPEC.md](IMPLEMENTATION_SPEC.md) — canonical implementation architecture, invariants, gates and test requirements.
- [STATUS.md](STATUS.md) — resumable implementation ledger and exact current next steps.

If code and the implementation spec diverge, either the code must be fixed or the spec must be deliberately updated in the same work and the reason recorded in `STATUS.md`.

## Gate 0 installation test

Before installing an experimental build, back up the relevant KOReader data, especially `koreader/settings/` and `koreader/plugins/`.

1. Build or obtain `readwisereader.koplugin.zip`.
2. Extract it so the Kindle contains `koreader/plugins/readwisereader.koplugin/_meta.lua` and `main.lua`.
3. Restart KOReader.
4. Confirm **Readwise Reader** appears in the KOReader menu.
5. Open it and confirm the bootstrap information dialog appears.
6. Close KOReader, remove `koreader/plugins/readwisereader.koplugin/`, restart KOReader, and confirm normal baseline behavior returns.

Do not enter or commit an access token during Gate 0.

## Development checks

With Lua 5.1 (or a compatible `luac`) and `zip` installed:

```sh
./scripts/dev-check.sh
./scripts/package.sh
```

The package script writes:

```text
dist/readwisereader.koplugin.zip
```

The ZIP root expands to the required `readwisereader.koplugin/` directory.

## Safety rules

- Never commit Readwise tokens, signed source URLs, private Reader content or user sidecars.
- Never use `My Clippings.txt` as the annotation source of truth.
- Preserve KOReader sidecars, progress, highlights and notes.
- No destructive remote behavior is enabled by default.
- Do not advance past a device/API gate until the required test has actually passed.

## License and provenance

This repository is licensed under AGPL-3.0. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

The community Readwise Reader plugin is used as an architectural/reference source and is also AGPL-3.0. Phase A's minimal shell is intentionally small and follows the KOReader v2025.04 plugin loader/hello-plugin pattern rather than copying the legacy monolithic implementation.
