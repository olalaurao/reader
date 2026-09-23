# Device test ledger

Target device for V1:

- Kindle Paperwhite 3 / 7th generation
- Serial prefix: `G090KB`
- Kindle firmware: `5.16.2.1.1 (4097470002)`
- KOReader historical Gates 0–4 baseline: `2025.04`
- KOReader canonical V1 baseline from Gate 4A-1 onward: `2026.07.1`

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

Status: **PASSED — 2026-09-22/23 on target PW3 / KOReader 2025.04**

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

Use the latest Gate 4 recovery build (0.1.11 or newer). Choose one **already-downloaded** test article and change its Reader location between supported locations that remain enabled in the plugin.

Prefer an explicit round trip so the final state is observable even if an earlier failed attempt already updated SQLite:

1. note the current Reader location and confirm the article exists only once locally;
2. in Reader, move it to another enabled location (for example Inbox -> Later);
3. run `Sync now`;
4. verify `Errors: 0`;
5. open KOReader Collections and verify the same local path is now in the new `Readwise: ...` Collection and is no longer in the old plugin-managed location Collection;
6. verify any unrelated user Collection containing that file is still intact;
7. if the first move was previously attempted on an older build, move it back in Reader and sync again to force a fresh transition.

Expected:
- same Reader-ID-owned local path remains;
- no new duplicate file;
- Reader location state updates;
- membership moves between the plugin-managed `Readwise: Inbox/Later/Shortlist/Feed/Archive` Collections;
- unrelated user Collections are not removed;
- watermark advances only on a clean sync.

Reader is the source of truth for these remote organization fields: a later Reader-side location change must reconcile the KOReader Collection on the next successful sync.

Bookshelf follow-up (Gate 4A-2): these managed Collections must remain visible/usable as Reader location shelves/filters, and Reader tags must be projected separately through metadata/keywords rather than one Collection per tag.

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


### Gate 4 recorded physical result

- multiple-article/full-backfill sync: **PASS**;
- second incremental sync / no duplicate: **PASS**;
- Reader location move without duplicate: **PASS**;
- moved document changed to the corresponding plugin-managed `Readwise: ...` Collection: **PASS**;
- Reader title rename without duplicate: **PASS**;
- reading progress preserved through rename: **PASS**;
- cancellation: **PASS**;
- KOReader remained responsive: **PASS**;
- cancelled rescan did not advance watermark: **PASS**;
- normal sync recovered afterward with `Errors: 0`: **PASS**.

Gate 4 is closed. Do not replay all Gates 0–4 after the KOReader upgrade. Gate 4A-1 is a deliberately smaller regression suite that samples the KOReader-internal contracts most likely to change.

---

## Gate 4A — KOReader v2026.07.1 + Bookshelf migration

Status: **Gate 5 COMPLETE — Phase G PASSED; Phase H / Gate 6 next**

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

### Gate 4A-1 recorded physical result — PASS

Target: PW3 / KOReader 2026.07.1

Validated:
- KOReader starts normally after upgrade;
- Readwise Reader loads and saved token remains usable;
- `Test connection` succeeds;
- existing Reader article opens;
- reading progress, existing highlight and note survive the upgrade;
- two consecutive normal syncs complete without errors or duplicates;
- full-rescan cancellation works and leaves KOReader responsive;
- cancelled rescan does not advance the watermark;
- one Reader-side move/rename preserves Reader-ID ownership/no duplicate;
- after KOReader restart the plugin still loads and settings persist.

**Gate 4A-1 PASSED.** Proceed to Gate 4A-2 / Bookshelf v5.1.4.

### Gate 4A-2 recorded physical results so far

Target: PW3 / KOReader 2026.07.1 + Bookshelf v5.1.4.

Attempt 1:
- Bookshelf loaded and showed Readwise-managed content;
- navigating Home/Recent hard-froze the UI and required a Kindle reboot;
- crash log had no Bookshelf Lua traceback, but showed repeated failures loading Bookshelf bundled fonts.

Recovery/retest:
- after a controlled document/library cleanup, CoverBrowser cache rebuild and recovery of required KUAL/Readwise content, the hard freeze did not reproduce;
- Home works; Series/Genres are slower on the PW3 but remain usable.

Base coexistence: **PASS**
- Readwise article opens from Bookshelf;
- reading progress is preserved;
- closing returns to Bookshelf without crash;
- normal Readwise sync succeeds with Bookshelf installed;
- second no-op sync creates no duplicate.

Reader-location Collections: **PASS**
- managed `Readwise: Inbox/Later/Shortlist/Feed/Archive` Collections appear in Bookshelf;
- Reader-side location move enters the new managed Collection and leaves the old one;
- unrelated user Collection membership remains intact;
- no duplicate local document was created.

### Gate 4A-2 tag projection retest — build 0.1.12

Do **not** run `Full document rescan`. The first normal sync after installing 0.1.12 intentionally performs only a metadata LIST backfill for the new tag projection.

1. In Reader, pick one already-managed article and give it a distinctive temporary tag, e.g. `gate4a-tag-test`.
2. Install the 0.1.12 `readwisereader.koplugin` build and restart KOReader.
3. Run **Readwise Reader -> Sync now** once.
4. Expected sync report:
   - `Errors: 0`;
   - `Reader tag metadata backfill: yes`;
   - no duplicate local document;
   - no manual/full HTML content rescan is required.
5. Refresh/reopen Bookshelf and confirm `gate4a-tag-test` appears under **Genres** and resolves to that same article.
6. In Reader, rename/remove that tag (or replace it with `gate4a-tag-test-2`).
7. Run a second normal **Sync now**.
8. Expected:
   - `Reader tag metadata backfill: no`;
   - same local article/path;
   - old tag/genre disappears and the new remote tag state is reflected;
   - Readwise location Collection and unrelated local Collections remain correct.
9. Open the article from Bookshelf and confirm progress/highlight/note still exist.
10. Restart KOReader once; confirm Bookshelf and Readwise Reader both still load and the projected tag/genre persists.
11. Run one final no-op sync and confirm no duplicate/error.

Pass report:
`primeiro sync backfill=yes + errors0: sim/não / tag apareceu em Genres: sim/não / alteração de tag atualizou: sim/não / sem duplicar: sim/não / collections preservadas: sim/não / progresso-highlight-nota preservados: sim/não / restart ok: sim/não / no-op final ok: sim/não`

### 0.1.12 physical tag result — FAIL isolated to Reader tag decoding

User-reported result:
- first metadata backfill sync: completed successfully;
- tag add/change sync path: completed;
- no duplicate: **PASS**;
- progress/highlight/note preservation: **PASS**;
- restart: **PASS**;
- final no-op sync: **PASS**;
- Bookshelf **Genres remained empty**: **FAIL**.

Diagnosis:
- real Reader Document LIST tag payloads are object/map records with a nested `name`;
- 0.1.12 assumed an array of strings and therefore projected no actual tag names.

### 0.1.13 targeted retest

0.1.13 normalizes the real LIST shape and speeds the one-time repair:
- projection marker is now `reader-tags-v2`;
- repair query is server-filtered to `category=article`;
- untagged articles do not get unnecessary metadata sidecar rewrites;
- unchanged Collections are not rewritten.

Retest:
1. Replace only `koreader/plugins/readwisereader.koplugin/` with 0.1.13 and restart KOReader.
2. Keep the distinctive Reader test tag on an already-managed article.
3. Run **Sync now** once; do not run Full document rescan.
4. Confirm `Reader tag metadata backfill: yes` and `Errors: 0`.
5. Reopen/refresh Bookshelf -> Genres.
6. Confirm the distinctive Reader tag is present and opens the same article.
7. Change/remove the tag in Reader and run one more normal sync.
8. Confirm the old genre disappears/new state appears without duplicate.

Return only:
`0.1.13 sync errors0: sim/não / tag apareceu em Genres: sim/não / mudança da tag refletiu: sim/não / sem duplicar: sim/não`

Gate 4A-2 final result: **PASS**.

Final 0.1.16 tag/cache validation:
- Reader document tag appeared in Bookshelf Genres after normal sync;
- deleting the tag in Reader and syncing again removed it from Genres;
- no Full document rescan was required;
- no duplicate/settings/sidecar/progress regression observed.

Proceed to Phase G / Gate 5.



## Phase G / Gate 5 — G1 relative local asset spike

Build: **0.1.17**

Purpose: validate the exact CRengine contract before production image downloads are implemented.

Procedure:
1. Install build 0.1.17 and restart KOReader.
2. Open **Readwise Reader -> Image asset spike (Gate 5)**.
3. The diagnostic HTML should open automatically.
4. Confirm a bordered/crossed image labelled **GATE 5** is visibly rendered between the first two text boxes.
5. Continue past the intentionally missing image reference.
6. Confirm **TEXT AFTER MISSING IMAGE** is still visible/readable.
7. Confirm KOReader remains responsive; close the document normally.
8. Reopen the same diagnostic action once and confirm it opens again without duplicate diagnostic files or crash.

Pass report:
`local GATE 5 image appeared: sim/não / text after image readable: sim/não / missing image did not crash: sim/não / text after missing image readable: sim/não / close-reopen ok: sim/não`

Stop condition:
- if the local relative image does not render, do not implement G2 against that strategy; collect `crash.log` only if KOReader crashes/freezes.


Physical result: **G1 PASS** on the target PW3.
- local relative image rendered;
- text around the image stayed readable;
- intentionally missing image did not crash/freeze KOReader;
- text after the missing asset stayed readable;
- close/reopen worked.

## Phase G / Gate 5 — G2 production image cache

Build: **0.1.18**

Implementation under test:
- new Reader articles cache HTTP(S) images as local relative assets;
- no fetched image is embedded as a data URI;
- per-image response cap: 2 MiB;
- per-article image network/cache budget: 8 MiB;
- max image attempts per article: 20;
- oversized, broken, unsupported, disabled, or over-budget images degrade to text placeholders;
- `Settings -> Documents -> Download article images` defaults ON;
- sync report exposes image downloaded/skipped/failed counts and bytes;
- existing already-local documents are not rewritten solely to add images in this phase.

### Gate 5 production test

Use a **newly saved Reader article that is not already local on the Kindle**, preferably one with several inline images. This avoids triggering the Phase Q content-refresh problem on an existing document.

1. Install 0.1.18 and restart KOReader.
2. Confirm **Settings -> Documents -> Download article images** is checked.
3. Save one image-heavy article to a currently enabled Reader location (Inbox or Later).
4. Run normal **Sync now**. Do not run Full document rescan.
5. In the sync summary, record:
   - `Downloaded`;
   - `Images downloaded`;
   - `Images skipped by limits/settings`;
   - `Images unavailable/unsupported`;
   - `Image bytes cached`;
   - `Errors`.
6. Open the new article from Bookshelf.
7. Confirm at least one real article image is visible and the surrounding text remains readable.
8. Scroll through the entire article. If any image was skipped/failed, confirm the placeholder/text path is still readable and KOReader remains responsive.
9. Close and reopen the article; confirm the images still render with Wi-Fi off if practical.
10. Run a second normal sync without changing the article and confirm no duplicate/new download regression.

Gate 5 pass report:
`new article downloaded: sim/não / real images appeared: sim/não / text remained usable: sim/não / no freeze/crash through whole article: sim/não / close-reopen images ok: sim/não / second sync no duplicate: sim/não / sync Errors=0: sim/não`

Optional cap/failure check (only if the chosen article naturally triggers it):
- a skipped/failed image with readable surrounding text is a PASS for failure tolerance; do not manufacture a giant file on the Kindle just to hit the cap.


### Gate 5 retest — build 0.1.19

0.1.18 device result: article downloaded, but article images did not. Root cause: Reader responsive/lazy image markup was not promoted into downloadable `img src` candidates.

0.1.19 adds support for:
- `picture/source srcset`;
- direct `img srcset`;
- `data-src`, `data-lazy-src`, `data-original`, `data-url`;
- tiny/data-URI lazy placeholders with the real URL in a responsive/lazy attribute.

Important: use a **different Reader article that has never been materialized on this Kindle**. The 0.1.18 test article is already considered local and normal sync will not rewrite its HTML before Phase Q.

Retest:
1. Install 0.1.19 and restart KOReader.
2. Keep **Download article images** ON.
3. Save a new image-heavy article into an enabled Reader location.
4. Run normal Sync now.
5. Record `Image candidates found`, `Responsive images promoted`, `Images downloaded`, `Images skipped...`, `Images unavailable...`, and `Errors`.
6. Open the article and verify real images + usable text.
7. Close/reopen; optionally turn Wi-Fi off before reopening to prove assets are local.

Return:
`image candidates >0: sim/não / images downloaded >0: sim/não / real images visible: sim/não / text usable: sim/não / no crash/freeze: sim/não / reopen/offline ok: sim/não / Errors=0: sim/não`


Recorded physical result:
- at least one real article image rendered: **PASS**;
- surrounding article text remained usable: **PASS**;
- KOReader remained responsive: **PASS**;
- close/reopen preserved the localized image: **PASS**;
- not every remote image rendered, accepted under Gate 5's explicit graceful-failure criterion;
- exact sync image counters were not captured and are not required to close the gate because end-to-end rendering + failure tolerance were directly observed.

**Gate 5 PASSED. Proceed to Phase H / Gate 6.**
