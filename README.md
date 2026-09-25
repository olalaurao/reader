# KOReader ↔ Readwise Reader

A KOReader plugin project for using a Kindle as an offline reading client for Readwise Reader, with safe synchronization of Reader-managed documents and KOReader annotations.

## Current status

**V1.0.0 is accepted on the target Kindle Paperwhite 3 / KOReader v2026.07.1.** The complete integrated acceptance flow passed: Reader documents sync to Kindle, reading/annotations work offline, highlights and notes sync back without duplicates, Markdown/`[[wikilinks]]` survive through Readwise to Obsidian, Reader locations/tags project into KOReader/Bookshelf metadata, Finished archives remotely without deleting local reading state, queue/retry/restart recovery is durable, and the final no-op Sync is idempotent.

**v1.1.0-rc.1 adds historical Reader → KOReader highlight/note import for the currently-open managed rolling EPUB/HTML.** It reconciles those remote highlights before outbound annotation creates, uses a durable historical/incremental cache, suppresses unsafe collisions instead of creating duplicates, and preserves notes through KOReader's native sidecar path. The RC is off-device hardened but still requires the single final PW3 acceptance in `docs/DEVICE_TESTS.md` before stable v1.1.0.

PDF/paging historical Reader → KOReader import is deliberately not part of v1.1.0; it remains a separate future locator spike. Existing PDF/EPUB reading and Kindle → Reader annotation sync are unchanged.

The Gate 2 action performs a metadata-only full Reader-library scan with cursor guards, ID deduplication, request pacing, bounded `Retry-After` recovery and cancellable KOReader UI. It reports counts by location/category. **It does not download or change Reader documents and does not perform remote writes.**

## Primary target

- Kindle Paperwhite 3 / 7th generation
- Kindle firmware 5.16.2.1.1
- KOReader v2026.07.1 (`kindlepw2`) — canonical V1 baseline
- KOReader 2025.04 — historical Gates 0–4 baseline
- Bookshelf v5.1.4 — V1 coexistence/metadata integration validated
- Manual sync only for V1

Do not update Kindle firmware/jailbreak for this project. The KOReader update is now a deliberate Gate 4A migration with backup, rollback and regression testing; see `docs/KOREADER_UPGRADE.md`.

## Canonical project documents

- [PLAN.md](PLAN.md) — V1 product scope and roadmap.
- [IMPLEMENTATION_SPEC.md](IMPLEMENTATION_SPEC.md) — canonical implementation architecture, invariants, gates and test requirements.
- [STATUS.md](STATUS.md) — resumable implementation ledger and exact current next steps.
- [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md) — physical test procedures and results.
- [docs/KOREADER_UPGRADE.md](docs/KOREADER_UPGRADE.md) — post-Gate-4 KOReader v2026.07.1 + Bookshelf migration/rollback gate.

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

### v1.1 local highlight cache and rollback

v1.1 schema v3 stores a local SQLite cache of Reader highlight text/notes so normal Sync does not have to rescan the entire Reader highlight corpus every time. This cache is private local data and is not logged.

Before the v2→v3 migration, the plugin checkpoints SQLite WAL when necessary and copies the pre-migration database to:

`koreader/settings/readwisereader.sqlite3.bak`

To downgrade to a v1.0 build after v1.1 has opened the database, exit KOReader, restore the older plugin, and restore that `.bak` file as `readwisereader.sqlite3`. Do not delete Reader documents or KOReader sidecars, and do not run a schema-v2 plugin against the migrated schema-v3 database.

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

The community Readwise Reader plugin is used as an architectural/reference source and is also AGPL-3.0. The current implementation targets KOReader v2026.07.1 on the validated PW3 baseline while retaining the project's gate-driven compatibility and rollback discipline.


## Gate 3 first article — PASSED

Gate 3 attempt 2 on `0.1.1` reached selector construction but the real PW3 log exposed an untitled-item bug: the numeric Lua loop variable `_` shadowed gettext `_`, so `_("Untitled")` failed. `0.1.2` fixes the exact device-log error and adds regression coverage.

After installing the experimental `0.1.2` retest build, enable Wi-Fi outside the plugin and use:

**Tools → More tools → Readwise Reader → Download one article (Gate 3)**

The plugin loads an on-device list of article candidates. Select one ordinary known article. It requests that article's processed Reader HTML, installs it atomically under `/mnt/us/documents/Readwise/Articles/`, writes KOReader custom metadata and opens it.

Gate 3 validates normal KOReader document behavior: rendering, Unicode, reflow/font/margin controls, search, dictionary UI when configured, local highlight/note creation, and persistence of position/annotations after closing and reopening. Image localization is deliberately deferred to Phase G / Gate 5; PDF/EPUB originals are Phase H / Gate 6.

Gate 3 is closed. Follow the Gate 4 procedure in `docs/DEVICE_TESTS.md` for Phase F. **Do not update KOReader until Gate 4 has passed on the known 2025.04 baseline.**
