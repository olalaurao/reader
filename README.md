# KOReader ↔ Readwise Reader

A KOReader plugin project for using a Kindle as an offline reading client for Readwise Reader, with safe synchronization of Reader-managed documents and KOReader annotations.

## Current status

**Phase A / Gate 0 and Phase B / Gate 1 are complete; Phase C storage is integrated; Phase D Reader metadata is implemented and CI-validated.** Gate 2 has **passed** on the target Kindle Paperwhite 3 / KOReader 2025.04. The real Reader library traversal completed (25 API pages / 1329 top-level documents), and the corrected 0.0.4 scan is visibly rendered, cancellable and responsive without changing Wi-Fi state or downloading/modifying documents. Phase E (first readable article) is next.

The Gate 2 action performs a metadata-only full Reader-library scan with cursor guards, ID deduplication, request pacing, bounded `Retry-After` recovery and cancellable KOReader UI. It reports counts by location/category. **It does not download or change Reader documents and does not perform remote writes.**

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
- [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md) — physical test procedures and results.

If code and the implementation spec diverge, either the code must be fixed or the spec must be deliberately updated in the same work and the reason recorded in `STATUS.md`.

## Gate 1 account test — passed 2026-09-22

Before installing an experimental build, back up the relevant KOReader data, especially `koreader/settings/` and `koreader/plugins/`.

1. Install `readwisereader.koplugin/` under `koreader/plugins/` and restart KOReader.
2. Open **Readwise Reader → Settings → Account → Access token**.
3. Enter the Readwise token **on the Kindle only**. Do not paste it into Git, chat, logs or test fixtures.
4. The entry field is password-masked and the menu only reports whether a token is configured.
5. With Wi-Fi enabled outside the plugin, use **Test connection**.
6. Follow the complete Gate 1 matrix in `docs/DEVICE_TESTS.md`.

The plugin deliberately checks connectivity without enabling or disabling Wi-Fi.

### Credential storage

KOReader's `LuaSettings` files are plaintext. The access token is therefore stored locally, unencrypted, in:

`koreader/settings/readwisereader.lua`

The UI never displays the saved value after saving it, and normal plugin logs never include the Authorization header/token.

To remove the credential, use **Access token → Clear**. Removing only the plugin directory does **not** remove the settings file. For a full manual cleanup, close KOReader and remove both:

- `koreader/plugins/readwisereader.koplugin/`
- `koreader/settings/readwisereader.lua`

## Development checks

With Lua 5.1 (or a compatible `luac`) and `zip` installed:

```sh
./scripts/dev-check.sh
lua5.1 readwisereader.koplugin/tests/run.lua
./scripts/package.sh
```

The package script writes:

```text
dist/readwisereader.koplugin.zip
```

The ZIP root expands to `readwisereader.koplugin/`. Development tests are excluded from the installable ZIP.

## Safety rules

- Never commit Readwise tokens, signed source URLs, private Reader content or user sidecars.
- Never use `My Clippings.txt` as the annotation source of truth.
- Preserve KOReader sidecars, progress, highlights and notes.
- No destructive remote behavior is enabled by default.
- The plugin does not control Wi-Fi in V1.
- Do not advance past a device/API gate until the required test has actually passed.

## License and provenance

This repository is licensed under AGPL-3.0. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

The community Readwise Reader plugin is used as an architectural/reference source and is also AGPL-3.0. The current implementation follows KOReader v2025.04 patterns while replacing the legacy monolithic architecture incrementally behind physical gates.


## Gate 2 metadata scan — pending device validation

After installing the `0.0.4` Gate 2 retest build, enable Wi-Fi outside the plugin and use:

**Tools → More tools → Readwise Reader → Scan Reader metadata (Gate 2)**

The scan is deliberately read-only and paced for the Reader LIST limit. Follow the exact pass/fail procedure in `docs/DEVICE_TESTS.md`. Phase E document download work is blocked until this gate passes on the real PW3.
