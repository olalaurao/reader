# Device test ledger

Target device for V1:

- Kindle Paperwhite 3 / 7th generation
- Serial prefix: `G090KB`
- Kindle firmware: `5.16.2.1.1 (4097470002)`
- KOReader: `2025.04`

Do not mark a device gate complete until its result is recorded here and in `STATUS.md`.

## Gate 0 — plugin bootstrap

Status: **PASSED — 2026-09-22**

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

## Gate 1 — local token + authentication

Status: **PASSED — 2026-09-22**

Build under test:
- plugin version: `0.0.2`;
- implementation commit: `6e776d8c903b846ff5f89b0aa06a4bf88394d7f9`;
- branch: `phase-b/config-auth-gate1`.

### Run history

#### 2026-09-22 — PASS

Validated on the target PW3 / KOReader 2025.04 using the Gate 1 `0.0.2` package.

User-reported results:
- access-token field was password-masked: **yes**;
- valid real token connected successfully: **yes**;
- an invalid/incorrect token was rejected cleanly by Readwise: **yes**;
- Wi-Fi-off path was detected as offline: **yes**;
- the plugin did not turn Wi-Fi on: **yes**;
- **Access token → Clear** changed the account state to not configured: **yes**;
- no credential was shared in chat or committed to the repository.

The real token was ultimately entered locally on the Kindle by editing `koreader/settings/readwisereader.lua` over USB because manual entry on the e-ink keyboard was impractical. This does not change the storage model: the token remains local plaintext in KOReader LuaSettings.

Conclusion:
- Gate 1 passed.
- HTTPS/authentication, invalid-token handling, offline detection, no-Wi-Fi-control behavior and credential clearing are validated on the target device.
- Phase C may begin.

### Safety before testing

1. Back up `koreader/settings/` and `koreader/plugins/`.
2. Do **not** paste the real Readwise token into chat, GitHub, logs or screenshots.
3. Enter the token only into the password-masked field on the Kindle.
4. Wi-Fi must be enabled/disabled by the user outside the plugin. The plugin must not toggle it.
5. Remember that the saved token is local plaintext in `koreader/settings/readwisereader.lua`.

### Install

1. Extract the Gate 1 `readwisereader.koplugin.zip`.
2. Copy `readwisereader.koplugin/` to `koreader/plugins/`, replacing the prior test copy if present.
3. Restart KOReader.
4. Open **Tools → More tools → Readwise Reader → Settings → Account**.

### G1.1 — token UI / persistence

1. Open **Access token**.
2. Confirm the input is password-masked.
3. Paste the real Readwise token and tap **Save**.
4. Confirm the menu reports **Access token: configured** and never displays the token value.
5. Leave and reopen the Readwise Reader menu; confirm it still reports configured.

Expected:
- token persists locally;
- token value is not echoed in the menu.

### G1.2 — valid token

1. Enable Wi-Fi outside the plugin and wait until the Kindle is online.
2. Open **Readwise Reader → Settings → Account → Test connection**.

Expected message:

`Connected to Readwise successfully.`

This validates the real PW3 HTTPS/auth path and the documented 204 success response.

### G1.3 — invalid token

1. Open **Access token** and replace the real token temporarily with a deliberately fake value such as `invalid-gate1-token`.
2. Save it.
3. With Wi-Fi still on, run **Test connection**.

Expected:
- a message saying Readwise rejected the access token;
- no crash;
- no token shown in the error.

Then restore the real token locally on the Kindle.

### G1.4 — offline behavior / no Wi-Fi control

1. Turn Wi-Fi **off outside the plugin**.
2. Run **Test connection**.

Expected:
- a no-internet/network message;
- the plugin does **not** turn Wi-Fi on;
- no crash.

### G1.5 — clear / replace

1. Open **Access token → Clear**.
2. Confirm the menu changes to **Access token: not set**.
3. Run **Test connection**.

Expected:
- message that no access token is configured;
- no network request should be needed.

4. Re-enter the real token locally if continuing development.

### Timeout/TLS classification

The transport has automated tests for timeout and TLS classification. Do not deliberately damage certificates or network configuration merely to force these cases on the Kindle. If a genuine timeout/TLS error occurs during Gate 1, record the exact user-facing message and a sanitized log tail.

### Rollback / credential cleanup

Removing only:

`koreader/plugins/readwisereader.koplugin/`

disables the plugin but does **not** erase its saved token.

To remove the credential, either use **Access token → Clear** before uninstalling or, with KOReader closed, also remove:

`koreader/settings/readwisereader.lua`

### Return with

Do not send the token. Return only:

- password field masked: yes/no;
- valid token → connected successfully: yes/no;
- fake token → rejected cleanly: yes/no;
- Wi-Fi off → offline message: yes/no;
- plugin did not turn Wi-Fi on: yes/no;
- clear → menu says not set: yes/no;
- any exact visible error that differed from the expected behavior;
- if there was a crash/failure, a relevant **sanitized** `koreader/crash.log` tail with credentials removed.

Gate 1 is closed; the target-device results are recorded above.


## Gate 2 — full Reader metadata scan

Status: **PASSED — 2026-09-22**

Build under retest:
- plugin version: `0.0.4`;
- UI fix commit: `c4074d4746f77ebf28bfcee29046d97a900ff9ec`;
- validated test tip before this ledger update: `7001fd0a16959dc85ee9c64d0764ca1e7cc7312f`;
- branch: `phase-d/reader-metadata-gate2`.

Purpose:
- traverse the real Reader library using metadata-only LIST requests;
- validate full cursor pagination, performance and memory behavior on the target PW3;
- verify there is no cursor loop, crash, visible duplicate processing or uncontrolled rate-limit behavior;
- prove this build remains read-only with respect to Reader content.

### Gate 2 run history

#### 2026-09-22 — attempt 1: PARTIAL PASS

Build: `0.0.3`.

- Full real-account traversal succeeded: **25 API pages / 1329 top-level documents**.
- Duplicate records ignored: 0; child records ignored: 1122.
- No pagination loop or final rate-limit failure.
- No documents downloaded or changed.
- Failure: the scan UI was blocking because the subprocess call lacked the required outer `Trapper:wrap()`.

#### 2026-09-22 — attempt 2: PASS

Build: `0.0.4`.

- scan/cancel surface visibly rendered (lower-left placement was cosmetic);
- cancellation worked;
- KOReader remained responsive;
- subsequent full scan completed;
- Wi-Fi state was unchanged;
- no document was downloaded or altered.

Conclusion: **Gate 2 PASSED.**

### Safety before testing

1. Back up `koreader/settings/` and `koreader/plugins/`.
2. Do not send the Readwise token, private document titles/content or signed URLs in chat/log excerpts.
3. Keep the existing token only on the Kindle.
4. Turn Wi-Fi on/off outside the plugin. The plugin must not control it.
5. This build is expected to make Reader LIST requests only. It must not download or modify documents.

### Install

1. Extract the Gate 2 `readwisereader.koplugin.zip`.
2. Replace `koreader/plugins/readwisereader.koplugin/` with the extracted folder.
3. Leave `koreader/settings/readwisereader.lua` in place if the valid token is already configured.
4. Restart KOReader.

### G2.1 — 0.0.4 visible/cancellation smoke test

1. Enable Wi-Fi outside the plugin and confirm the Kindle is online.
2. Open **Tools → More tools → Readwise Reader → Scan Reader metadata (Gate 2)**.
3. Confirm a visible message appears containing **Scanning Reader library metadata…** and **Tap to cancel**.
4. Tap the scan surface while it is running.
5. Confirm control returns to KOReader and a cancellation result/message appears.
6. Confirm no document was downloaded or changed.

### G2.2 — 0.0.4 full metadata-only scan

1. Start **Scan Reader metadata (Gate 2)** again.
2. Confirm the visible scan/cancel surface appears.
3. This time let it run to completion.

Expected final report contains:
- **Top-level documents**;
- **API pages**;
- **Duplicate records ignored**;
- **Child records ignored**;
- **Locations** counts;
- **Categories** counts;
- explicit confirmation that no documents were downloaded or changed.

Pass conditions:
- scan reaches the final report;
- KOReader does not crash or become permanently unresponsive;
- no cursor-loop/pagination error;
- no final rate-limit failure;
- duplicate API records, if any, are counted/ignored rather than emitted twice;
- child Reader records/highlights are not counted as top-level reading documents;
- plugin does not toggle Wi-Fi;
- no local Reader document is downloaded/created/changed by this scan.

Note: LIST requests are intentionally paced at least 3.1 seconds apart. Large libraries can therefore take longer; this is deliberate to stay below the documented Reader LIST rate limit.

### Previous 0.0.3 cancellation procedure (superseded by G2.1 above)

After one successful full scan:

1. Start **Scan Reader metadata (Gate 2)** again.
2. While the scan message is visible, tap to cancel.

Expected:
- scan closes/cancels cleanly;
- KOReader remains usable;
- no document is downloaded or changed;
- a later full scan can still run normally.

Cancellation is useful evidence for PW3 responsiveness but does not replace the successful full scan in G2.1.

### Return with

Do not send token or private titles/content. Return:

`scan completou: sim/não / travou: sim/não / wifi não foi alterado: sim/não / nenhum arquivo foi baixado ou alterado: sim/não / cancelamento funcionou: sim/não / páginas: N / documentos: N / duplicatas ignoradas: N / child records ignorados: N / locations: ... / categories: ...`

If the scan fails, also send:
- the exact visible error;
- whether it happened before any page/result or after some time;
- a relevant **sanitized** `koreader/crash.log` tail only if there was a crash, with credentials/private content removed.

For the 0.0.4 retest, return only:

`progresso apareceu: sim/não / cancelamento funcionou: sim/não / scan completo depois funcionou: sim/não / ficou travado: sim/não / wifi não foi alterado: sim/não / nenhum arquivo foi baixado ou alterado: sim/não`

The detailed counts from attempt 1 are already recorded; resend them only if the new full scan differs materially or errors.

Gate 2 is closed: **PASSED on 2026-09-22**.


## Gate 3 — first readable article

Status: **PASSED — 2026-09-22**

Build under test:
- plugin version: `0.1.2` (retest build);
- branch: `phase-e/first-article-gate3`;
- E1 primitives: `655e70e76f87343bd2580d563ef6d90d75294b40`;
- E1/E2 integrated code: `26610d04e4c3e8b0414ff40a39d244763c7328ca`;
- final documentation/package tip must be taken from the branch after this ledger update.

Purpose:
- select one known Reader article on-device without sharing its title/content;
- fetch processed `html_content`;
- atomically install a normal local HTML document;
- write KOReader metadata;
- open/read/annotate/reopen it like an ordinary KOReader document.

### Gate 3 run history

#### 2026-09-22 — attempt 1: FAIL before selector

Build: `0.1.0`.

Observed:
- **Loading Reader articles…** appeared with the cancellation text;
- the loading surface disappeared;
- no article selection menu appeared afterward;
- KOReader stayed usable;
- no article was selected or downloaded.

The 0.1.1 retest changes the UI transition so the originating TouchMenu closes first and the selector is shown on the next UI tick using KOReader's `Menu` + `CenterContainer` pattern.

#### 2026-09-22 — attempt 2: FAIL during selector construction

Build: `0.1.1`.

Observed:
- metadata loading surface appeared and completed;
- selector did not render;
- explicit guarded fallback appeared: **The Reader article list could not be displayed. Please retry with the updated Gate 3 build.**
- KOReader stayed usable;
- no article was selected/downloaded.

Interpretation:
- metadata/API path completed far enough to schedule selector construction;
- the protected selector creation/show block raised an on-device KOReader UI error.

Before another fix, retrieve the most recent sanitized `koreader/crash.log` entry containing:
`ReadwiseReader: [UI] article selector failed`

#### 2026-09-22 — 0.1.2 root-cause fix

The uploaded PW3 `crash.log` identified the exact selector failure:
- `attempt to call local '_' (a number value)` in `candidateItems`;
- the article loop index `_` shadowed gettext `_`;
- an untitled Reader candidate triggered `_("Untitled")`, calling the numeric index.

0.1.2 renames that loop index and adds an automated untitled-candidate regression test. Run #50 passed.

#### 2026-09-22 — attempt 3: PASS

Build: `0.1.2`.

The complete Gate 3 checklist passed on target PW3 / KOReader 2025.04:
- article selector appeared;
- article downloaded/opened;
- normal render and Unicode;
- font/margin reflow;
- search;
- dictionary behavior as configured;
- local highlight;
- local note;
- close/reopen retained reading position;
- highlight and note persisted.

Conclusion: **Gate 3 PASSED.**

### Safety / install

1. Back up `koreader/settings/` and `koreader/plugins/`.
2. Do not send the Readwise token, private article title/content or screenshots containing private text unless intentionally sharing them.
3. Replace only `koreader/plugins/readwisereader.koplugin/` with the Gate 3 package.
4. Keep `koreader/settings/readwisereader.lua` to preserve the configured token.
5. Restart KOReader.
6. Enable Wi-Fi outside the plugin. The plugin must not change Wi-Fi state.

### G3.1 — choose/download/open one article

1. Open **Tools → More tools → Readwise Reader → Download one article (Gate 3)**.
2. A cancellable metadata-loading message should appear.
3. When it disappears, a separate on-device article selector should appear. **This is the specific 0.1.2 retest point.**
4. The selector should contain up to 100 top-level Reader article candidates.
5. Select one ordinary article you recognize. Prefer a text article with enough content to test search/reflow and, if convenient, accents or curly punctuation.
6. A cancellable processed-article download message should appear.
7. After successful local installation, KOReader should open the article automatically.

Expected:
- no crash;
- one `.html` file is created below `/mnt/us/documents/Readwise/Articles/`;
- no `.tmp` file remains after success;
- the article opens through the normal KOReader reader UI;
- the plugin does not alter Wi-Fi.

If the same plugin-managed article is selected again later, the existing local copy should be opened instead of being blindly overwritten.

### G3.2 — normal KOReader reading behavior

On the opened article, validate:

1. **Rendering:** article text is readable and not raw/broken HTML.
2. **Unicode:** accents/non-ASCII punctuation visible in the chosen article render correctly.
3. **Reflow:** change font size and margins; text reflows normally.
4. **Search:** search for a word known to be present and confirm a result.
5. **Dictionary:** select/long-press a word and confirm KOReader's dictionary lookup UI works if a dictionary is configured. If no dictionary is installed, report that rather than installing one just for this gate.
6. **Highlight:** create a normal local highlight.
7. **Note:** attach a simple local note to that highlight.
8. Move to a different reading position, then close the document.

### G3.3 — reopen / persistence

1. Reopen the same local article (for example from KOReader history or the `documents/Readwise/Articles/` folder).
2. Confirm reading position/progress was retained.
3. Confirm the local highlight remains.
4. Confirm the local note remains.
5. Optional but useful: turn Wi-Fi off outside the plugin and confirm the downloaded article still opens/reads locally.

Pass conditions:
- normal render/reflow/search behavior;
- Unicode survives;
- local highlight/note work;
- reopen preserves progress/highlight/note;
- no plugin crash;
- no unintended Wi-Fi control.

Image localization/caching is **not** a Gate 3 criterion; it is Phase G / Gate 5. PDF/EPUB originals are Phase H / Gate 6.

### Return with

Do not send the article title/content. Return only:

`baixou e abriu: sim/não / renderizou normal: sim/não / unicode ok: sim/não / reflow fonte/margem: sim/não / busca: sim/não / dicionário: sim/não/não configurado / highlight: sim/não / nota: sim/não / reabriu na posição: sim/não / highlight+nota persistiram: sim/não / wifi não foi alterado: sim/não`

If anything fails, also return the exact visible error and, only if needed, a sanitized `koreader/crash.log` excerpt with token/private content removed.

Gate 3 is closed: **PASSED on 2026-09-22**. Phase F may begin after Phase E is merged.


## Gate 4 — document sync engine

Status: **PENDING — run on KOReader 2025.04 before the planned KOReader upgrade**

Build target:
- plugin version: `0.1.3`;
- branch: `phase-f/document-sync-gate4`;
- Gate 4 preparation commit: `5fb309774d8d4442b17251d582e475b21688a331`;
- GitHub Actions run: #70 — **SUCCESS**;
- workflow artifact ID: `10723390104`;
- installable ZIP SHA-256: `ab055261fd54f48936e603f342310b5957ca000e717dca15e6e3fd44eca5afe9`.

Purpose:
- validate real multi-document materialization and incremental ownership;
- prove second sync is idempotent;
- prove Reader title/location changes do not create duplicate local documents;
- validate cancellability/recovery and conservative watermark handling.

### Safety / filter setup before the first Gate 4 sync

The real Reader account is large. **Do not accept the first-sync confirmation before reviewing filters.**

1. Back up `koreader/settings/`, `koreader/plugins/` and the existing `/mnt/us/documents/Readwise/` folder/sidecars.
2. Install the `0.1.3` Gate 4 build but keep KOReader at **2025.04**.
3. Open **Readwise Reader → Settings → Documents → Locations**.
4. For the first Gate 4 run, choose a small controlled scope:
   - turn **Inbox OFF**;
   - leave **Later ON** if it contains a manageable set, or use Shortlist if you deliberately prepared a small test set;
   - leave Archive/Feed OFF unless specifically testing them.
5. Under **Types**, keep **Articles ON**. PDF/EPUB/Email/RSS are intentionally disabled until later gates.
6. Confirm the download folder is the expected path under `/mnt/us/documents/`.
7. Keep the token private. Wi-Fi is controlled outside the plugin.

The first sync displays an explicit warning that every supported article matching the current filters will be downloaded.

### G4.1 — first controlled multi-article sync

1. Turn Wi-Fi on outside KOReader.
2. Open **Readwise Reader → Sync now (Gate 4)**.
3. Read the first-sync warning and confirm only after the filters above are correct.
4. Let the sync finish.

Expected:
- visible cancellable sync surface;
- at least two matching test articles are installed if the chosen scope contains them;
- final summary appears;
- `Errors: 0`;
- watermark is updated only after successful parent metadata/Collection finalization;
- files are normal local HTML documents under the configured Readwise folder;
- KOReader remains responsive;
- plugin does not toggle Wi-Fi.

Open at least one newly synced article and confirm it reads normally.

### G4.2 — second sync unchanged

Without changing Reader:

1. run **Sync now (Gate 4)** again;
2. let it complete.

Expected:
- no second copy of an already-managed article;
- no title/filename-based duplicate;
- normally `Downloaded: 0` unless a genuinely new matching Reader item appeared;
- incremental sync completes successfully.

### G4.3 — Reader location move

Choose one already-downloaded test article and change its Reader location between supported locations that remain observable in your test.

Run sync.

Expected:
- same Reader-ID-owned local path remains;
- no new duplicate file;
- Reader location state updates;
- membership moves between the plugin-managed `Readwise: ...` Collections;
- unrelated user Collections are not removed.

### G4.4 — Reader title rename

Rename that same Reader article remotely and sync.

Expected:
- KOReader metadata title updates;
- existing local filename/path may remain unchanged;
- **no second local file** is created;
- existing sidecar/progress/highlights remain attached to the same local file.

Phase F intentionally does not replace the document body merely because Reader `updated_at` changed; content replacement safety is Phase Q.

### G4.5 — cancellation and recovery

1. Open **Full document rescan**.
2. Confirm the warning.
3. While the visible Trapper surface is running, tap to cancel.

Expected:
- KOReader returns responsive;
- already-completed atomic files remain valid;
- no incomplete temp file replaces a valid final file;
- cancelled attempt does not commit a new document watermark.

Then run a normal **Sync now** and confirm it recovers/completes.

### Gate 4 pass report

Do not send token or private titles/content. Return only:

`múltiplos artigos: sim/não / segundo sync sem duplicar: sim/não / mover location sem duplicar: sim/não / renomear sem duplicar: sim/não / cancelamento funcionou: sim/não / recuperou depois: sim/não / wifi não foi alterado: sim/não`

If any item is `não`, also send:
- the exact visible error/message;
- which G4 step failed;
- a relevant **sanitized** `koreader/crash.log` excerpt only if needed.

**Do not update KOReader yet if Gate 4 fails.** Fix/retest Phase F on 2025.04 first.

---

## Gate 4A — KOReader v2026.07.1 + Bookshelf migration

Status: **BLOCKED until Gate 4 passes**

Canonical detailed runbook: `docs/KOREADER_UPGRADE.md`.

Order is mandatory:

1. Gate 4 passes on KOReader 2025.04.
2. Record/merge the exact known-good Phase F build.
3. Back up KOReader/settings/plugins/Readwise DB + document sidecars.
4. Upgrade **KOReader only** to official `v2026.07.1`, using `koreader-kindlepw2-v2026.07.1.zip` on this PW3/firmware.
5. **Gate 4A-1:** re-run Readwise Reader compatibility tests with Bookshelf absent/disabled.
6. Only after 4A-1 passes, install Bookshelf `v5.1.4` with built-in Cover browser enabled.
7. **Gate 4A-2:** validate both plugins together across sync/open/close/no-op sync/restart.
8. Only then may Phase G begin.

Do not use `kindlehf` on the current firmware 5.16.2.1.1; KOReader documents that target for firmware >= 5.16.3. Do not update Kindle firmware/jailbreak for this project.
