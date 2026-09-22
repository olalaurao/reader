# Device test ledger

Target device for V1:

- Kindle Paperwhite 3 / 7th generation
- Serial prefix: `G090KB`
- Kindle firmware: `5.16.2.1.1 (4097470002)`
- KOReader: `2025.04`

Do not mark a device gate complete until its result is recorded here and in `STATUS.md`.

## Gate 0 — plugin bootstrap

Status: **PASSED — 2026-09-22**

### Before installing

Back up, at minimum:

- `koreader/settings/`
- `koreader/plugins/`
- `koreader/crash.log` if it already contains useful baseline diagnostics

No token is needed for this test.

### Test

1. Extract `readwisereader.koplugin.zip`.
2. Copy the resulting `readwisereader.koplugin/` directory into `koreader/plugins/`.
3. Confirm these paths exist on the Kindle:
   - `koreader/plugins/readwisereader.koplugin/_meta.lua`
   - `koreader/plugins/readwisereader.koplugin/main.lua`
4. Restart KOReader.
5. Confirm **Readwise Reader** appears in the menu.
6. Tap **Readwise Reader**.
7. Confirm an information dialog says the bootstrap plugin loaded successfully and shows version `0.0.1`.
8. Close KOReader.
9. Remove only `koreader/plugins/readwisereader.koplugin/`.
10. Restart KOReader.
11. Confirm KOReader returns to normal baseline behavior and the Readwise Reader item is gone.

### Return with

- whether steps 5, 7 and 11 passed;
- if any step failed, the exact visible error;
- the relevant sanitized tail of `koreader/crash.log` (do not include credentials; Gate 0 should contain none).

### Run history

#### 2026-09-22 — PASS

Validated on the target PW3 / KOReader 2025.04 using the Gate 0 bootstrap package.

User-reported results:
- menu item **Readwise Reader** appeared: **yes**;
- bootstrap popup opened successfully: **yes**;
- after removing `readwisereader.koplugin/` and restarting, KOReader returned to normal baseline behavior: **yes**.

Conclusion:
- Gate 0 passed.
- The plugin load/menu registration path and uninstall rollback are validated on the target device.
- Phase B config/auth work may begin.
