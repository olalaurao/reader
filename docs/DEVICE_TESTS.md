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

Status: **Gate 7 COMPLETE; Phase J / Gate 8 build 0.1.22 pending disposable API interoperability validation**

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


## Phase H / Gate 6 — original PDF + EPUB

Build: **0.1.20**

Purpose: prove original-format Reader PDF/EPUB materialization on the real PW3. Reader's current public LIST contract exposes `raw_source_url` only when requested; it is a direct S3 source link, may be empty for non-distributable documents and expires after one hour. Build 0.1.20 requests it immediately before materialization and never persists the signed URL.

Safety implemented:
- stream original bytes directly to a temp file;
- 64 MiB maximum raw source size;
- preserve at least 128 MiB free space before starting;
- validate PDF/EPUB signatures before atomic rename;
- clean incomplete temp files;
- processed HTML fallback only for safe non-transient raw-source failures;
- transient network/no-space failures remain retryable instead of silently changing format.

### Targeted Gate 6 procedure

Do **not** enable PDF/EPUB globally and do **not** run Full document rescan for this gate.

1. Install 0.1.20 and restart KOReader.
2. Open **Readwise Reader -> Test PDF / EPUB (Gate 6) -> Choose one PDF**.
3. Select a real PDF you recognize from Reader.
4. If the plugin reports that only an HTML fallback was available, choose a different PDF; that item does not satisfy the original-format gate.
5. When the original PDF opens:
   - confirm it behaves as a PDF (pages/zoom and normal KOReader PDF controls);
   - read/change page;
   - close and reopen it;
   - confirm progress survives.
6. Open **Test PDF / EPUB (Gate 6) -> Choose one EPUB**.
7. Select a real EPUB. If an HTML-fallback message appears, choose another.
8. For the original EPUB:
   - confirm normal EPUB/reflow/font controls;
   - read/change position;
   - close/reopen;
   - confirm progress survives.
9. With both originals already installed, optionally turn Wi-Fi off and reopen them once to prove local/offline reading.
10. Confirm KOReader remains responsive and Bookshelf/Readwise Reader still load.

Return:
`PDF abriu: sim/não / PDF original: sim/não / PDF reabriu+progresso: sim/não / EPUB abriu: sim/não / EPUB original+reflow: sim/não / EPUB reabriu+progresso: sim/não / offline ok: sim/não / sem crash: sim/não`

Gate 6 passes only with at least one **original PDF** and one **original EPUB**. HTML fallback is valid product behavior but is not evidence for the original-format gate.

Recorded physical result:
- original Reader PDF opened successfully: **PASS**;
- PDF close/reopen + progress preservation: **PASS**;
- original Reader EPUB opened successfully: **PASS**;
- EPUB reflow/font controls behaved normally: **PASS**;
- EPUB close/reopen + progress preservation: **PASS**;
- offline/local reopen: **PASS**;
- no crash/freeze: **PASS**.

**Gate 6 PASSED. Proceed to Phase I / Gate 7.**


## Phase I / Gate 7 — KOReader sidecar annotation identity

Build: **0.1.21**

This is a short **local-only** test. It does not upload a highlight to Reader yet, does not need a Full document rescan and does not need a whole-library sidecar scan.

1. Install 0.1.21 and restart KOReader.
2. Open one **already-managed Readwise article** from Bookshelf/Readwise.
3. Highlight a short piece of text.
4. Add this distinctive note exactly:
   `gate7 [[Foucault]]`

   `#pesquisar 🧠`
5. Close the article normally so KOReader saves its sidecar.
6. Reopen that same article.
7. While the article is open, use **Readwise Reader -> Scan current annotations (Gate 7)**.
8. Confirm:
   - `Highlights found` is at least 1;
   - `With notes` is at least 1;
   - the most recently modified highlight shows the exact selected text;
   - the note still contains `gate7 [[Foucault]]`, the blank line, `#pesquisar` and 🧠;
   - `Identity quality: strong`;
   - Page/location, Start and End are not empty;
   - copy/note the displayed `Local ID`.
9. Close and reopen the article one more time without editing that highlight.
10. Run **Scan current annotations (Gate 7)** again.
11. Confirm the same highlight has the **same Local ID** and is now counted as unchanged rather than new.
12. Confirm normal reading remains responsive. No network operation is required for the scan itself.

Return:
`texto exato: sim/não / nota exata: sim/não / locator preenchido: sim/não / identity strong: sim/não / mesmo Local ID após reopen: sim/não / segundo scan unchanged: sim/não / sem crash: sim/não`

If the diagnostic says there is no valid sidecar, close/reopen the document once and retry. Do not run Full document rescan.

Recorded physical result:
- selected text exact: **PASS**;
- note content entered on Kindle exact: **PASS**;
- locator populated: **PASS**;
- identity quality strong: **PASS**;
- same Local ID after reopen: **PASS**;
- second scan unchanged: **PASS**;
- no crash/freeze: **PASS**.
- The suggested 🧠 fixture character was not entered because the Kindle keyboard lacks emoji input; all typed note characters were preserved exactly, so this does not affect Gate 7.

**Gate 7 PASSED. Proceed to Phase J / Gate 8.**


## Phase J / Gate 8 — Reader v3 ↔ Readwise v2 annotation interoperability

Build: **0.1.22**

This gate intentionally changes **only disposable test data created by the plugin**. It does not select an existing article/highlight. The menu actions require confirmation before remote writes/deletes.

Keep Wi-Fi on for these four steps. Do not run normal Full document rescan.

### Step 1 — create disposable Reader highlight

1. Open **Readwise Reader -> Annotation API spike (Gate 8) -> 1. Create disposable highlight**.
2. Confirm the warning.
3. Wait for **Gate 8 · Step 1 complete**.
4. Record:
   - v3 child category is highlight;
   - v3 parent link matches;
   - initial note matches;
   - highlight tag matches;
   - highlight offset present;
   - highlight DOM location present.
5. On Reader web/phone, refresh the library and find the temporary document whose title starts with **KOReader Gate 8 disposable**.
6. Open it and confirm exactly one test highlight exists with note:
   `gate8 initial [[Foucault]]`
   and tag:
   `koreader-gate8`.

If step 1 errors/cancels after remote creation, use **Recovery: clean disposable Gate 8 data**. Do not press step 1 repeatedly.

### Step 2 — prove ID mapping + Reader v3 note update

1. On Kindle, run **2. Probe mapping + v3 note update**.
2. This may take ~15–25 seconds because it deliberately waits for the v2 representation rather than hammering the API.
3. Record:
   - Mapping method;
   - `v2 external_id = Reader child id`;
   - v2 text matches;
   - v3 parent still matches;
   - v3 note update verified;
   - v3 tag update verified.
4. Refresh the same disposable document in Reader.
5. Confirm its highlight note is now exactly:
   `gate8 updated through Reader v3 [[Foucault]]`.
6. Confirm the highlight has the added tag `gate8-v3-updated` if Reader exposes it immediately.

A mapping method based only on text/note is a **Gate 8 failure**. We require deterministic external-ID evidence.

### Step 3 — mutate the exact same highlight through Readwise v2

1. Run **3. Update note/color through v2**.
2. Record:
   - v2 note response matches;
   - v2 color response is green;
   - Reader v3 saw v2 note update.
3. Refresh Reader.
4. Confirm the same highlight's note is now exactly:
   `gate8 updated through Readwise v2 [[Foucault]]`.
5. If Reader exposes highlight colors, confirm it is green.

### Step 4 — Reader v3 delete + cross-API cleanup

1. Run **4. Delete + cleanup**.
2. Record:
   - Reader v3 DELETE succeeded;
   - Reader v3 no longer lists highlight;
   - Readwise v2 no longer exposes it after v3 delete;
   - whether v2 still exposed it initially;
   - whether v2 DELETE was needed for cleanup;
   - temporary parent cleanup succeeded.
3. Refresh Reader and confirm the **KOReader Gate 8 disposable** document is gone.

If cleanup reports any failure, run **Recovery: clean disposable Gate 8 data** once and report its result. Do not manually delete unrelated Reader data.

Return:
`step1 all yes: sim/não / Reader initial visible: sim/não / mapping method: <texto> / external_id=child: sim/não / v3 note update Reader: sim/não / v2 note update→v3: sim/não / v2 note visible Reader: sim/não / green: sim/não/não aparece cor / v3 delete: sim/não / v3 sumiu: sim/não / v2 sumiu após v3 delete: sim/não / v2 delete necessário: sim/não / parent cleanup: sim/não / doc temporário sumiu: sim/não`

Recorded physical result:
- all four disposable spike steps completed: **PASS**;
- parent-linked Reader v3 create/LIST, literal note and tag: **PASS**;
- deterministic Reader-child ↔ Readwise-v2 mapping: **PASS**;
- Reader v3 note/tag PATCH reflected in Reader: **PASS**;
- Readwise v2 note PATCH propagated back to the same Reader child: **PASS**;
- Reader v3 delete removed the child from v3 and v2 without needing the v2 delete fallback: **PASS**;
- disposable parent cleanup: **PASS**;
- color mutation worked as spike evidence only; production highlight-color sync is out of V1.

**Gate 8 PASSED. Proceed to Phase K / Gate 9.**


## Phase K / Gate 9 — exact Reader-visible text matching

Build: **0.1.24**

This gate is **read-only remotely**. It fetches the current managed Reader parent and compares the newest KOReader highlight against Reader-visible text. It does **not** create/update/delete a Reader highlight. The old 0.1.23 upload action is intentionally hidden until this gate passes.

For each case below, make the requested highlight the **newest** highlight in the article, close/reopen the article so the sidecar is flushed, then run:
**Readwise Reader -> Test current highlight match (Gate 9)**.

Keep Wi-Fi on for the diagnostic because it fetches the current Reader HTML.

### Case 1 — ordinary unique text
1. Open an already-managed Reader article.
2. Highlight a distinctive passage that occurs only once.
3. Close/reopen, run the Gate 9 diagnostic.
4. Expect:
   - `Matched: yes`;
   - `Result: exact` is ideal, but a safe normalization mode is acceptable if the HTML requires it;
   - `Reader exact visible text` represents the same selected passage;
   - `Remote writes: none`.

### Case 2 — paragraph/line-break boundary
1. Create a new highlight spanning the end of one paragraph/visible line boundary and the beginning of the next.
2. Close/reopen, run the diagnostic.
3. Expect `Matched: yes`; normally `Result: whitespace`.
4. Verify the displayed Reader text is the same passage, including the correct words on both sides of the boundary.

### Case 3 — curly quote / dash
1. In an article containing typographic quotes/apostrophes or an en/em dash, create a new highlight containing that punctuation.
2. Close/reopen, run the diagnostic.
3. Expect `Matched: yes`.
4. If KOReader and Reader expose different straight/curly forms, expect `Result: punctuation`; if they are byte-identical, `exact` is also valid.
5. Verify the recovered Reader text shows the correct passage.

### Case 4 — repeated text must be blocked
1. Create the newest highlight on a short passage that occurs identically at least twice in the Reader-visible article. If needed, use a repeated short phrase rather than risking a unique sentence.
2. Close/reopen, run the diagnostic.
3. Expect:
   - `Matched: no`;
   - `Result: ambiguous`;
   - `Remote writes: none`.
4. Do **not** use the upload action; it is not exposed in 0.1.24.

Return:
`unique: matched yes/no + result / line-break: matched yes/no + result / curly-dash: matched yes/no + result / repeated: ambiguous yes/no / every screen said Remote writes none: yes/no / no crash-freeze: yes/no`

Gate 9 passes only when the three safe-match cases recover the intended Reader-visible passage and the repeated case is rejected as ambiguous, with no remote write.

### Recorded physical result — 2026-09-23

**PASS** on the target Kindle PW3 / KOReader v2026.07.1.

Observed:
- unique-text case passed;
- paragraph/line-boundary case passed;
- curly quote/dash case passed;
- repeated-text case was correctly rejected as ambiguous;
- every diagnostic remained remotely read-only (`Remote writes: none`);
- no crash/freeze was observed.

**Gate 9 PASSED. Proceed to Phase L / Gate 10 only after Phase K is merged to `main`.**


## Phase L / Gate 10 — Reader highlight create + no duplicate

Build: **0.1.25**

This gate performs a real remote highlight creation. Use an already-managed Reader article and a new test highlight that you are comfortable keeping in Reader.

Phase L intentionally discovers annotations only from the **currently-open managed Reader document** during `Sync now`; it does not sweep sidecars for the whole library in this gate build.

### Test

1. Install build 0.1.25 without replacing:
   - `koreader/settings/readwisereader.lua`;
   - `readwisereader.sqlite3`;
   - downloaded Readwise documents;
   - KOReader sidecars.
2. Turn Wi-Fi on outside the plugin.
3. Open an already-managed Reader article. Prefer one without old unsynced test highlights if convenient.
4. Select a distinctive passage that occurs only once and create a highlight.
5. Add this exact note:
   `ver [[Foucault]]`
   then on the next line:
   `#pesquisar`
6. Close the article and reopen it so the KOReader sidecar is flushed. Leave that same article open.
7. Run **Readwise Reader -> Sync now**.
8. On the sync summary, record:
   - `Annotation sync`;
   - `Highlights created`;
   - `Highlight creates blocked safely`;
   - `Reconciliation markers verified`.
9. Refresh Reader on web/phone and confirm:
   - the new highlight is under the **same original article**;
   - the selected text is correct;
   - the note is exactly `ver [[Foucault]]\n#pesquisar`.
10. Without changing or adding highlights, run **Sync now** a second time while the same article is open.
11. Confirm:
   - second sync says `Highlights created: 0`;
   - no create is blocked;
   - Reader still shows only one copy of the tested highlight;
   - KOReader does not crash/freeze.

If the article already had other unsynced local highlights, the first sync may create more than one. That does not fail the gate by itself; identify the new `[[Foucault]]` test highlight and verify it specifically. The second unchanged sync must still create zero.

Return:
`doc certo: sim/não / texto certo: sim/não / nota exata: sim/não / primeiro sync created=<n> / primeiro blocked=<n> / marker verified=<n> / segundo sync created=0: sim/não / segundo blocked=0: sim/não / duplicata no Reader: sim/não / sem crash-freeze: sim/não`

Gate 10 passes only if the tested highlight reaches the correct parent with the exact note, at least one marker is verified for the create path, no create is blocked in the normal case, and the second unchanged sync creates no duplicate.
### Recorded physical result — 2026-09-23

**PASS** on the target Kindle PW3 / KOReader v2026.07.1.

Observed:
- correct original Reader document: **PASS**;
- selected text: **PASS**;
- exact multiline note with `[[Foucault]]` + `#pesquisar`: **PASS**;
- first sync blocked creates: **0 / PASS**;
- create marker verification: **PASS**;
- second unchanged sync created zero highlights: **PASS**;
- second sync blocked creates: **0 / PASS**;
- duplicate in Reader: **none / PASS**;
- no crash/freeze: **PASS**.

**Gate 10 PASSED. Proceed to Phase M / Gate 11 only after Phase L is merged to `main`.**


## Phase M / Gate 11 — official Readwise → Obsidian wikilink

Kindle plugin build: **0.1.25** (no new Kindle install required)

Use the exact highlight created during Gate 10. Its Reader note has already been physically verified as:

`ver [[Foucault]]`
`#pesquisar`

This gate tests only the downstream official Readwise export into the user's real Obsidian configuration.

### Before syncing
1. In Obsidian, confirm the **Readwise Official** community plugin is installed and enabled. If it is already configured, keep the existing configuration unchanged for the first test.
2. Open the Readwise Obsidian export preferences and inspect the active **Highlight** template.
3. Confirm whether it contains `highlight_note`.
   - The documented official default does.
   - If your custom template intentionally omits notes, stop and report `template exporta nota: não`; do not silently change it just to force the gate to pass.

### Test
1. In Reader, locate the Gate 10 article/highlight and confirm the note still contains `ver [[Foucault]]` and `#pesquisar`.
2. In Obsidian, run **Readwise Official: Sync your data now** from the Command Palette. If automatic sync already exported the highlight, do not duplicate/reset it; inspect the existing export instead.
3. Open the exported file for that same article.
4. Verify the Gate 10 selected highlight appears in the correct article file.
5. Inspect the Markdown source and confirm:
   - the note text is present;
   - `[[Foucault]]` is literally present, not escaped and not inside a code span/block;
   - `#pesquisar` is preserved.
6. Click/open the rendered `[[Foucault]]` link in Obsidian.
   - PASS means Obsidian treats it as a normal internal link (opening the existing `Foucault` note if present, or behaving as an unresolved internal link if that note does not exist).
7. Do not edit the Reader note yet; update behavior belongs to Gate 12 and the official Obsidian export is append-only for already-exported highlights.

### Important official limitation
New highlights are appended to exported Obsidian pages, but later edits to an already-exported highlight/note do not automatically rewrite that old block. A deliberate refresh/re-export is needed for historical edits. This is an official export limitation, not a KOReader sync failure.

Return:
`template exporta nota: sim/não / artigo certo: sim/não / highlight apareceu: sim/não / nota apareceu: sim/não / markdown tem [[Foucault]] literal: sim/não / #pesquisar preservado: sim/não / link funciona no Obsidian: sim/não`

Gate 11 passes only if the real active export configuration includes notes and the Gate 10 note reaches the correct Obsidian article with `[[Foucault]]` functioning as normal Obsidian wikilink.
### Recorded user result — 2026-09-23

**PASS** in the user's real Obsidian vault/configuration.

Observed:
- active template exports highlight notes: **yes**;
- correct article: **yes**;
- Gate 10 highlight appeared: **yes**;
- note appeared: **yes**;
- source Markdown contains literal `[[Foucault]]`: **yes**;
- `#pesquisar` preserved: **yes**;
- Obsidian wikilink behavior: **yes**.

**Gate 11 PASSED. Phase N / Gate 12 is now unblocked after Phase M merge.**

## Phase N / Gate 12 — note update, conflict, deletion OFF → ON

Build: **0.1.26**

Use a clean already-managed Reader article if possible. Keep the article open whenever you run **Sync now**. This build still limits annotation mutations to the currently-open managed document.

### A. Note update
1. Create/sync a fresh unique test highlight if the article does not already have a clean linked one.
2. On KOReader, edit that linked highlight note to exactly:
   `gate12 kindle [[Foucault]]`
   then on the next line:
   `#nota-update`
3. Close/reopen the article to flush the sidecar; leave it open.
4. Run **Readwise Reader → Sync now**.
5. Expect:
   - `Notes updated: 1` (or at least 1 if another intentional linked note changed);
   - `Note conflicts blocked: 0`;
   - `Annotation mutations blocked safely: 0`.
6. Refresh Reader and verify the exact same linked highlight now has exactly that multiline note.

### B. Conflict must not overwrite either side
1. Create and sync a **second** fresh test highlight in the same clean article with baseline note `gate12 conflict base`.
2. After it is linked, edit its KOReader note to `gate12 LOCAL conflict` but **do not sync yet**.
3. In Reader web/phone, edit that same second highlight note to `gate12 REMOTE conflict`.
4. Back on KOReader, close/reopen the article and run **Sync now**.
5. Expect:
   - `Note conflicts blocked: 1` for this controlled case;
   - no PATCH overwrites the Reader value.
6. Verify Reader still says `gate12 REMOTE conflict` and KOReader still says `gate12 LOCAL conflict`.

### C. Delete with propagation OFF
1. Confirm **Settings → Highlights → Propagate highlight deletions** is unchecked.
2. Delete the first Gate 12 linked highlight locally in KOReader (not the conflict fixture).
3. Close/reopen; keep the article open; run **Sync now**.
4. Expect:
   - `Local highlight deletions detected: 1`;
   - `Deletions retained remotely (propagation off): 1`;
   - `Remote highlight deletions: 0`.
5. Refresh Reader: the deleted-local test highlight must still exist remotely.
6. **Safety stop:** if either detected or retained is greater than 1, do not enable deletion; report the counts so the old tombstones can be inspected first.

### D. Deliberately enable deletion
Only continue if step C reported exactly one pending deletion.
1. Open **Settings → Highlights → Propagate highlight deletions**.
2. Select it and accept the destructive-action confirmation.
3. Return to the same article and run **Sync now**.
4. Expect `Remote highlight deletions: 1` and zero mutation block/error for that target.
5. Refresh Reader:
   - the first deleted-local test highlight is gone;
   - the second conflict-test highlight is still present.
6. Immediately return to Settings and turn **Propagate highlight deletions OFF** again.
7. Confirm no crash/freeze.

Return:
`nota update Reader exata: sim/não / notes updated=<n> / conflito detectado=sim/não / Reader conflito preservou remoto: sim/não / Kindle conflito preservou local: sim/não / delete OFF detected=<n> retained=<n> remote_deleted=<n> / remoto permaneceu com OFF: sim/não / delete ON remote_deleted=<n> / só alvo foi apagado: sim/não / setting voltou OFF: sim/não / sem crash-freeze: sim/não`

Gate 12 passes only after note update, no-overwrite conflict behavior, default-off deletion, and one explicitly verified linked delete all pass.


### Gate 12 attempt 1 — build 0.1.26 — FAIL / fixed in 0.1.27
Observed on the target PW3:
- current-document highlights scanned: 1;
- highlights already linked: 1;
- notes updated: 0;
- conflicts blocked: 0;
- mutation blocks: 0;
- annotation remote errors: 1.

Root cause was compatibility with pre-Gate-10 linked Reader children using the generic plugin source marker. Build 0.1.27 adds safe legacy support for note updates only. **Do not continue Gate 12 on 0.1.26.**

### Gate 12 attempt 2 — build 0.1.27 — FAIL / fixed in 0.1.28
Observed on the target PW3 after editing the note of an already-linked highlight:
- current-document highlights scanned: 2;
- highlights created: 0;
- highlights already linked: 2;
- notes updated: 0;
- note conflicts blocked: 0;
- annotation mutations blocked safely: 1;
- annotation remote errors: 0;
- Reader note did not change.

The same newly-created linked child had previously reported zero verified reconciliation markers. Build 0.1.28 therefore treats durable Reader child ID + correct parent + highlight category as sufficient identity for **note update only**. Remote deletion remains strict and unchanged.

#### 0.1.28 retest
Do not create another highlight. Keep the edited local note as-is.
1. Install 0.1.28.
2. Open the same managed article.
3. Close/reopen once so the sidecar is flushed, then leave the article open.
4. Run **Readwise Reader → Sync now**.
5. Expect:
   - `Highlights created: 0`;
   - `Notes updated: 1`;
   - `Note conflicts blocked: 0`;
   - `Annotation remote errors: 0`;
   - `Durable linked highlights accepted without marker` may be greater than 0;
   - the target note appears exactly in Reader.
6. Do **not** test conflict or deletion until this update case passes.

### Gate 12 attempt 3 — build 0.1.28 — FAIL / fixed in 0.1.29
Observed:
- scanned: 2;
- already linked: 2;
- notes updated: 0;
- note conflicts blocked: 2;
- mutation blocks: 0;
- durable linked highlights accepted without marker: 2;
- remote errors: 0.

Build 0.1.29 uses deterministic Readwise v2 `external_id` mapping for the remote note/conflict source and for the note PATCH. Do not create another highlight.

#### 0.1.29 retest
1. Install 0.1.29.
2. Keep the same local edited note(s) and the same article.
3. Close/reopen the article and leave it open.
4. Run Sync now.
5. Expected for the edited target:
   - `Highlights created: 0`;
   - `Readwise v2 mappings resolved` at least 1 on first resolution (or 0 if already persisted from a prior 0.1.29 run);
   - `Readwise v2 remote-note reads` at least 1;
   - `Readwise v2 note updates` at least 1 when the remote still equals the stored baseline;
   - `Notes updated` at least 1;
   - no false conflict for that target;
   - Reader shows the edited note.
6. Do not test deletion until note update passes.

### Gate 12 attempt 4 — build 0.1.29 — FAIL / fixed in 0.1.30
Observed:
- v2 mappings resolved: 2;
- v2 remote-note reads: 2;
- v2 note updates: 0;
- note conflicts blocked: 2;
- remote errors: 0.

This proves mapping/API reads are correct; build 0.1.30 changes only note equality comparison to tolerate invisible newline/whitespace normalization.

#### 0.1.30 retest
Do not create or edit another highlight.
1. Install 0.1.30.
2. Use the same article and same local edited note.
3. Close/reopen the article; leave it open.
4. Run Sync now.
5. Expected for the target:
   - Highlights created: 0;
   - v2 remote-note reads >= 1;
   - v2 note updates >= 1 if the remote still contains the old baseline;
   - Notes updated >= 1;
   - no false conflict for the target;
   - Reader displays the edited note.
6. Do not test deletion until this passes.

### Gate 12 attempt 5 — build 0.1.30 — Reader remained stale / fixed in 0.1.31
Observed:
- Notes updated: 1;
- v2 note updates: 1;
- note conflicts: 0;
- remote errors: 0;
- Reader still displayed the old note.

0.1.31 no longer accepts the v2 response as sufficient success. It verifies the exact Reader child, waits for propagation, and if necessary repairs that child with a v3 PATCH before persisting success.

#### 0.1.31 retest
Do not create or edit another highlight.
1. Install 0.1.31.
2. Use the same article and same local note.
3. Close/reopen the article; leave it open.
4. Run Sync now.
5. Expected recovery path may show:
   - `Readwise v2 note updates: 0` because v2 already has the desired value from 0.1.30;
   - `Reader note verification reads` > 0;
   - `Reader v3 repair PATCHes: 1` if Reader is still stale;
   - `Reader note repairs completed: 1`;
   - `Note updates reconciled: 1` rather than `Notes updated: 1` on this recovery run;
   - `Annotation remote errors: 0`;
   - Reader displays the new local note.
6. Do not test conflict/delete until the Reader visibly shows the new note.


### Gate 12 attempt 6 — build 0.1.31 — NOTE UPDATE PASS

Physical result on target PW3 / KOReader v2026.07.1:

- current-document highlights scanned: **2**;
- highlights created: **0**;
- highlights already linked: **2**;
- notes updated: **1**;
- note updates reconciled: **1**;
- note conflicts blocked: **0**;
- annotation mutations blocked safely: **0**;
- local highlight deletions detected: **0**;
- remote highlight deletions: **0**;
- deletions retained remotely: **0**;
- legacy linked highlights accepted safely: **0**;
- durable linked highlights accepted without marker: **8**;
- Readwise v2 annotation pages scanned: **0**;
- Readwise v2 mappings resolved: **0**;
- Readwise v2 remote-note reads: **2**;
- Readwise v2 note updates: **1**;
- Reader note verification reads: **6**;
- Reader propagation misses: **1**;
- Reader v3 repair PATCHes: **2**;
- Reader note repairs completed: **2**;
- annotation remote errors: **0**;
- the user refreshed/checked Reader and visually confirmed the edited note is correct.

**Gate 12A / note update: PASS.**

What this physically proves:
- a successful v2 note PATCH alone is not sufficient;
- the production path must verify the exact linked Reader v3 child;
- if Reader is stale after v2, a v3 repair PATCH to that same validated child can restore convergence;
- durable sync baseline must advance only after Reader visibility is proven.

Next: proceed to **Gate 12B conflict test**. Do not test deletion until conflict handling passes.
See `docs/ANNOTATION_SYNC_LESSONS.md` before modifying annotation logic again.


### Gate 12B — conflict handling — PASS

Physical result on target PW3 / KOReader v2026.07.1, build 0.1.31:
- current-document highlights scanned: **1**;
- highlights created: **0**;
- highlights already linked: **1**;
- notes updated: **0**;
- note updates reconciled: **0**;
- note conflicts blocked: **1**;
- annotation mutations blocked safely: **0**;
- local highlight deletions detected: **0**;
- remote highlight deletions: **0**;
- durable linked highlights accepted without marker: **1**;
- Readwise v2 annotation pages scanned: **3**;
- Readwise v2 mappings resolved: **1**;
- Readwise v2 remote-note reads: **1**;
- Readwise v2 note updates: **0**;
- Reader note verification reads: **0**;
- Reader v3 repair PATCHes: **0**;
- annotation remote errors: **0**;
- Reader remained `gate12 REMOTE conflict`;
- Kindle remained `gate12 LOCAL conflict`.

**Gate 12B PASS. No side was overwritten.**

Next: Gate 12C — deletion propagation OFF. Do not enable remote deletion until the OFF run reports exactly one pending deletion.


### Gate 12C — deletion propagation OFF — PASS

Physical result on target PW3 / KOReader v2026.07.1, build 0.1.31.

Setup:
- two fresh linked highlights were created successfully in one clean managed article.

After deleting only the target highlight locally while **Propagate highlight deletions** remained OFF:
- current-document highlights scanned: **1**;
- highlights created: **0**;
- highlights already linked: **1**;
- local highlight deletions detected: **1**;
- remote highlight deletions: **0**;
- deletions retained remotely (propagation off): **1**;
- annotation mutations blocked safely: **0**;
- annotation remote errors: **0**;
- the user confirmed both highlights still exist in Reader.

**Gate 12C PASS.**

Next: Gate 12D deliberate opt-in delete. Use the same tombstoned target; do not create a new target. Enable deletion, run Sync now once, verify only the target disappears remotely, then immediately disable deletion again.


### Gate 12D attempt 1 — build 0.1.31 — BLOCKED SAFELY / fixed in 0.1.32

Observed:
- current-document highlights scanned: **1**;
- highlights already linked: **1**;
- local highlight deletions detected: **1**;
- remote highlight deletions: **0**;
- annotation mutations blocked safely: **1**;
- annotation remote errors: **0**;
- target still existed in Reader.

Cause: the old destructive identity check still required the exact Reader source marker, which production Reader did not return reliably.

#### 0.1.32 retest

Use the **same tombstoned target** from Gate 12C/12D attempt 1. Do not create another target.

1. Install build 0.1.32.
2. Confirm **Propagate highlight deletions** is OFF after the failed 0.1.31 attempt.
3. Open the same article; keep it open.
4. Enable **Settings → Highlights → Propagate highlight deletions** and accept the destructive warning.
5. Run **Sync now once**.
6. Expected:
   - `Local highlight deletions detected: 1`;
   - `Delete cross-API identity verified: 1`;
   - `Reader delete verification reads: >=1`;
   - `Reader deletions verified: 1`;
   - `Delete verification pending: 0`;
   - `Remote highlight deletions: 1`;
   - `Annotation mutations blocked safely: 0`;
   - `Annotation remote errors: 0`.
7. Refresh Reader:
   - tombstoned target is gone;
   - control highlight remains.
8. Immediately turn **Propagate highlight deletions OFF** again.
9. If cross-API identity is not verified, delete remains 0, verification is pending, or any error/block appears: turn the setting OFF and stop.


### Gate 12D — deliberate opt-in deletion — PASS

Build: **0.1.32**

Observed:
- the tombstoned target disappeared from Reader;
- the control highlight remained in Reader;
- **Propagate highlight deletions** was turned OFF again.

Follow-up Sync now with propagation OFF:
- current-document highlights scanned: **2**;
- highlights created: **0**;
- highlights already linked: **2**;
- local highlight deletions detected: **0**;
- remote highlight deletions: **0**;
- deletions retained remotely: **0**;
- annotation mutations blocked safely: **0**;
- delete cross-API identity verified: **0** (no pending delete on this confirmation run);
- Reader delete verification reads: **0**;
- Reader deletions verified: **0**;
- delete verification pending: **0**;
- annotation remote errors: **0**.

The successful destructive-run diagnostic counters were not captured in a photo, so they are intentionally not reconstructed. The end state plus the clean follow-up prove that the target tombstone was reconciled and no unintended deletion remained pending.

**Gate 12D PASS. Gate 12 PASS.**


## Phase O / Gate 13 — offline queue, reboot and retry

Build: **0.1.33**

The live physical test intentionally covers the persistence/reboot boundary. 429/timeout/5xx/auth behavior is fault-injected in the automated suite so the test account does not need unsafe server-error manipulation.

### Gate 13A — queue while offline
Use a clean managed Reader article with no existing test highlight in the selected passage.

1. Install 0.1.33, preserving settings/database/documents/sidecars.
2. Open the article while online if needed, then turn **Wi-Fi OFF outside the plugin**.
3. Create one fresh unique KOReader highlight with note:
   `gate13 offline [[Foucault]]`
   then on the next line:
   `#queue-test`
4. Close/reopen the article once to flush the sidecar; leave it open.
5. Run **Readwise Reader → Sync now** while Wi-Fi is still OFF.
6. Expected:
   - Mode: `offline / local queue`;
   - Annotation sync: `queued_offline`;
   - Current-document highlights scanned: at least 1;
   - Highlight creates queued durably: at least 1;
   - Highlights created: **0**;
   - Create queue waiting after sync: at least 1;
   - no crash/freeze.
7. Reader must **not** contain the new highlight yet.

**Stop here if queued/waiting is 0. Do not turn Wi-Fi on and create another fixture; report the screen first.**

### Gate 13B — reboot with pending queue
1. With Wi-Fi still OFF and the queue item pending, fully exit/restart KOReader.
2. Reopen KOReader. The local article/highlight/note must still exist.
3. Do not recreate or edit the highlight.

### Gate 13C — reconnect and exactly-once delivery
1. Turn Wi-Fi ON outside the plugin.
2. You may leave any managed article open; the durable queue is not tied to the old in-memory document session.
3. Run **Sync now**.
4. Expected:
   - Create queue items processed: at least 1;
   - Highlights created: **1** or Highlights reconciled safely: **1**;
   - Create queue waiting after sync: **0**;
   - Highlight creates blocked safely: **0** for the normal offline fixture;
   - Annotation remote errors: **0**.
5. Refresh Reader and verify exactly one copy under the correct original document with exact note:
   `gate13 offline [[Foucault]]`
   `#queue-test`

### Gate 13D — second sync dedup
1. Run **Sync now** again without changing anything.
2. Expected:
   - Highlights created: **0**;
   - Create queue waiting after sync: **0**;
   - no duplicate in Reader;
   - local highlight/note still present;
   - no crash/freeze.

Return:
`offline mode sim/não / queued=<n> / waiting offline=<n> / sobreviveu reboot sim/não / reconnect created=<n> reconciled=<n> waiting=<n> / nota exata Reader sim/não / segundo sync created=<n> waiting=<n> / exatamente 1 cópia sim/não / local preservado sim/não / sem crash-freeze sim/não`

Gate 13 passes only if the same durable annotation survives offline + KOReader restart and reaches Reader exactly once after reconnect.


### Gate 13A attempt 1/2 — build 0.1.33 — FAIL / fixed in 0.1.34

The user correctly enabled Kindle Airplane Mode before testing, but both attempts still showed online behavior:
- metadata pages fetched;
- fresh highlight created remotely immediately;
- create queue processed in the same run;
- queue waiting ended at 0.

This was **not user error**. Build 0.1.33 used KOReader `NetworkMgr:isOnline()`, which on KOReader 2026.07.1 checks DNS reachability rather than the Kindle native Airplane Mode flag. Kindle KOReader can also restore Wi-Fi independently.

#### 0.1.34 Gate 13A retest
1. Install 0.1.34.
2. Use a new unique local highlight/note; do not reuse the two 0.1.33 fixtures that already reached Reader.
3. Enable **Airplane Mode in the native Kindle UI**.
4. Enter KOReader/plugin normally; no special timing/wait is required beyond letting the UI settle.
5. Close/reopen the managed article once to flush the sidecar.
6. Run ordinary **Sync now**.
7. Expected:
   - Mode: `offline / local queue`;
   - Annotation sync: `queued_offline`;
   - Highlights created: **0**;
   - Highlight creates queued durably: >=1;
   - Create queue items processed: **0**;
   - Create queue waiting after sync: >=1;
   - Metadata pages: **0**;
   - Content pages: **0**;
   - new fixture must not yet exist in Reader.
8. Stop after this screen. Do not reboot until Gate 13A passes.

### Gate 13A attempt — build 0.1.34 — FAIL

Despite native Kindle Airplane Mode being enabled, the report still showed online behavior:
- Metadata pages: **1**;
- Current-document highlights scanned: **3**;
- Highlights created: **1**;
- Highlights already linked: **2**;
- Highlight creates queued durably: **1**;
- Create queue items processed: **1**;
- Create queue waiting after sync: **0**.

Do not create another highlight for this spike.

### Build 0.1.35 — read-only network-state spike

Install 0.1.35 and run:
**Readwise Reader → Inspect network state (Gate 13)**

First observation:
1. enable native Kindle Airplane Mode;
2. open/return to KOReader;
3. run the diagnostic;
4. photograph the whole result screen.

Second observation:
1. disable Airplane Mode and connect Wi-Fi normally;
2. run the same diagnostic again;
3. photograph the whole result screen.

The diagnostic must show **Remote requests: none** and **Remote writes: none**.

Record these fields for both states:
- native airplaneMode;
- native wirelessEnable;
- native wifid enable;
- KOReader interface;
- KOReader isWifiOn;
- KOReader isConnected;
- KOReader isOnline;
- KOReader cached Wi-Fi;
- KOReader cached connected;
- Plugin network_available;
- Plugin reason.

Do **not** run Gate 13A Sync now again until the ON/OFF signals are compared.

### Build 0.1.35 — physical diagnostic result with no internet / Airplane Mode

Observed on target PW3 / KOReader v2026.07.1:
- Kindle: **true**;
- native `airplaneMode`: **unavailable**;
- native `wirelessEnable`: **unavailable**;
- native `wifid enable`: **unavailable**;
- KOReader interface: `wlan0`;
- KOReader `isWifiOn`: **true**;
- KOReader `isConnected`: **true**;
- KOReader `isOnline`: **true**;
- KOReader cached Wi-Fi: **true**;
- KOReader cached connected: **unavailable**;
- plugin local-network decision: **true / online**;
- remote requests: **none**;
- remote writes: **none**.

This is sufficient to reject both prior detection strategies:
1. the attempted native LIPC properties are not available on this target in the tested state;
2. KOReader's local connectivity booleans can remain true while the user has no internet/Airplane Mode.

A second 0.1.35 online screenshot is no longer required before implementing the safer contract because the offline observation alone proves the false-positive safety failure.

### Build 0.1.36 — pre-write reachability fix (superseded before physical retest)

Automated/package validation:
- draft PR #16;
- CI run #553 on implementation/package HEAD `f89204dd098a3e530990b8ced0e050b0e106d33d`: **SUCCESS**;
- development checks, Lua unit tests, ZIP build, package layout and artifact upload all passed;
- artifact ID: `10786469934`;
- artifact name: `readwisereader-koplugin-475dc29fd1fd180b40c0e9091c39f81b1532c901`;
- artifact digest: `sha256:7944e764ed09815ec51b1739769254b2578c2dcc8df19a832b45056215b1fb76`.
- verified installable inner ZIP SHA-256: `5be016c319586d9ca72512c82e4d98aa1ba02b505d92dc1aafd126a3901d381e`;
- inner ZIP integrity: `unzip -t` **PASS**, no errors.

0.1.36 no longer used those local flags as permission to write remotely. Before the physical retest, repository review against the canonical Phase L/N handoff found one remaining Phase O gap: create discovery was still limited to the currently-open document. That non-device work was completed in 0.1.37, so 0.1.36 is preserved as implementation history but is no longer the build to test physically.

### Build 0.1.37 — Gate 13A retest

Automated/package validation:
- draft PR #16;
- code/package CI run #597: **SUCCESS**;
- latest branch-head CI run #599: **SUCCESS**;
- development checks, full Lua unit suite, ZIP build, package layout and artifact upload all passed;
- latest artifact ID: `10808879560`;
- artifact name: `readwisereader-koplugin-809bc26d5a18fc7302b9b8532a5a1fae513156d0`;
- outer artifact SHA-256: `9accc0d982d701fb82d5df6fce4c3e519619c540649b4b4122554905f9438421`;
- installable inner `readwisereader.koplugin.zip` SHA-256: `771bfec4484f8d0654b717f1ae0029edd87fca8d842668c28c554485db864e53`;
- inner ZIP integrity: `unzip -t` **PASS**, no errors;
- packaged `constants.lua` reports version **0.1.37**;
- packaged ZIP contains no `tests/` entries.

Additional automated contract in 0.1.37:
- manual Sync discovers new create-highlight work across every **locally-present managed Reader document**, prioritizing the currently-open document;
- remote-only documents are excluded before sidecar IO;
- missing/non-authoritative sidecars and per-document scan failures are skipped safely;
- authoritative sidecars update durable annotation identity first, then queue those exact candidates without a second sidecar read;
- the read-only Readwise auth GET still gates every remote write;
- note update/delete mutation remains bounded to the current document for this gate.

Use a **new unique** local highlight/note; do not reuse fixtures already uploaded by 0.1.33/0.1.34.

1. Install 0.1.37, preserving DB/settings/documents/sidecars.
2. Enable native Kindle Airplane Mode / ensure there is no internet.
3. Open a clean managed article.
4. Create one unique highlight with:
   `gate13 probe [[Foucault]]`
   and next line:
   `#queue-test-0137`
5. Close/reopen once to flush the sidecar; leave article open.
6. Run ordinary **Sync now**.
7. Required result:
   - Mode: **offline / local queue**;
   - Remote preflight: `offline`, `timeout`, `tls` or `unknown` is acceptable for this no-internet state;
   - Managed annotation documents scanned: >=1;
   - Authoritative annotation sidecars: >=1;
   - Managed-document highlights scanned: >=1;
   - Highlight creates queued durably: >=1;
   - Highlights created: **0**;
   - Create queue items processed: **0**;
   - Create queue waiting after sync: >=1;
   - Metadata pages: **0**;
   - Content pages: **0**;
   - no watermark advance;
   - the new fixture is absent from Reader.
8. **Stop and return this screen.** Do not reboot yet unless all conditions above pass.

If Gate 13A passes, continue with the same queued item:
- restart KOReader while still offline;
- confirm local highlight/note survives;
- reconnect Wi-Fi outside the plugin;
- Sync now once: exactly one create or safe reconciliation, queue waiting 0;
- Sync now again unchanged: created 0, waiting 0, exactly one Reader copy.



### Gate 13A attempt — build 0.1.37 — FAIL SAFE / no report

Physical result on target PW3 / KOReader v2026.07.1:
- 0.1.37 was installed for the offline Gate 13A retest;
- native Kindle Airplane Mode / no internet remained in effect;
- the user used the fresh Gate 13 fixture created for this attempt;
- ordinary **Sync now** did **not** produce the expected summary report;
- the only UI result was: `Document sync failed safely`;
- no reboot/reconnect step was performed after this failure.

Interpretation:
- the worker's top-level `pcall` protected local data from an uncaught Lua exception but hid the stage;
- because 0.1.37 newly traverses multiple managed sidecars, a real-device sidecar/query/queue exception that was not represented by the unit fixtures is a plausible failure boundary;
- the exact throw source is **not claimed as proven** from the generic 0.1.37 message alone.

### Build 0.1.38 — Gate 13A retry

Automated/package validation:
- draft PR #16;
- CI run #640 on `99cd78a0a83f606c8415f04091b47b7f58be42a7`: **SUCCESS**;
- development checks: SUCCESS;
- full Lua unit suite: SUCCESS;
- ZIP build/layout: SUCCESS;
- artifact upload: SUCCESS;
- artifact ID: `10810568961`;
- artifact name: `readwisereader-koplugin-f2d4c98d4b24d29446635d9c368e02e10b10b654`;
- outer artifact SHA-256: `96d8dd7d9246cbb8aa7b387034d9724113308a11d2263a5c4b90214952df316e`;
- installable inner ZIP SHA-256: `e7fbb5006d228d9ba5166e6265ed42c9464b0f1c9630f4d7dfe5324b5ed0e582`;
- inner ZIP `unzip -t`: **PASS**, no errors;
- packaged `constants.lua`: version **0.1.38**;
- packaged ZIP contains no `tests/` entries.

0.1.38 keeps every 0.1.37 safety invariant and adds:
- per-document `pcall` isolation around sidecar scan and queue preparation;
- per-annotation normalization isolation inside a readable sidecar;
- optimized local-managed repository query fallback to the previous managed query, then current-document fallback;
- diagnostic counters for isolated scan/normalize/queue exceptions and repository fallback;
- outer worker-stage diagnostics if a global exception still escapes;
- no weakening of the read-only Readwise pre-write probe.

**Do not create another highlight. Reuse the exact fixture from the failed 0.1.37 attempt.**

1. Install 0.1.38, preserving DB/settings/documents/sidecars.
2. Keep native Kindle Airplane Mode ON / no internet.
3. Open the same managed article containing the existing Gate 13 fixture; do not edit or recreate it.
4. Close/reopen once if needed to ensure the sidecar is flushed; leave the article open.
5. Run ordinary **Sync now** once.
6. Required:
   - a full report appears (not generic worker failure);
   - Mode: **offline / local queue**;
   - Remote preflight: `offline`, `timeout`, `tls`, or `unknown`;
   - Current annotation document status: **ok**;
   - Managed annotation documents scanned: >=1;
   - Authoritative annotation sidecars: >=1;
   - Managed-document highlights scanned: >=1;
   - Highlight creates queued durably: >=1 **or** the same idempotent queue item remains waiting from 0.1.37;
   - Highlights created: **0**;
   - Create queue items processed: **0**;
   - Create queue waiting after sync: >=1;
   - Metadata pages: **0**;
   - Content pages: **0**;
   - new fixture remains absent from Reader.
7. It is acceptable for:
   - Annotation sync to be `queued_offline_partial`;
   - Annotation documents skipped safely / isolated exception counters to be >0,
   provided **Current annotation document status = ok**, the target fixture is waiting durably, and no remote work ran.
8. If the generic failure still occurs, report the new message including `stage: ...`; do not reboot.
9. If the report passes, stop and return the whole screen. Only then proceed to Gate 13B reboot with the same pending queue item.


### Gate 13 offline-state isolation before 0.1.38 Sync

New physical observation:
- native Kindle Airplane Mode does not remain a trustworthy offline fixture after returning to KOReader/Readwise Reader; Wi-Fi is observed ON again.

Before running 0.1.38 Sync:
1. In KOReader, open **Settings (gear) → Network**.
2. Disable **Restore Wi-Fi connection on resume**.
3. While still inside KOReader, turn **Wi-Fi connection OFF** from KOReader's own Network menu.
4. Open **Readwise Reader**, then close its menu **without running Sync**.
5. Check KOReader's Wi-Fi state.
6. If Wi-Fi is still OFF: proceed with the existing 0.1.38 Gate 13A instructions using the same existing highlight fixture.
7. If Wi-Fi turned ON merely by opening/closing Readwise Reader: **stop and report that result**. Do not run Sync and do not create another highlight.

Purpose: distinguish KOReader's own restore behavior from a possible plugin-load interaction before evaluating offline queue semantics.


### Gate 13 offline-state isolation result — PASS

Controlled physical setup:
- disable KOReader **Restore Wi-Fi connection on resume**;
- turn Wi-Fi OFF from KOReader's own Network menu;
- open/close Readwise Reader without Sync.

Observed:
- Wi-Fi remained OFF.

Use this controlled KOReader-offline state for the 0.1.38 Gate 13A retry. Do not rely on native Kindle Airplane Mode alone and do not create another highlight.


### Gate 13A build 0.1.38 — PASS

Controlled KOReader-offline physical result:
- Remote preflight: `unknown`;
- Annotation sync: `queued_offline_partial`;
- managed documents scanned: 801;
- authoritative sidecars: 13;
- skipped safely: 788;
- scan/normalize/queue exceptions: 0;
- repository source: `managed_local`;
- repository fallback: no;
- current annotation document status: `ok`;
- managed-document highlights scanned: 12;
- highlights created: 0;
- queued durably: 3;
- queue processed: 0;
- queue waiting: 3;
- metadata pages: 0;
- content pages: 0;
- errors: 0.

Gate 13A passes because the target current document was authoritative, all three create intents remained durable, no remote queue item was processed, and no document sync request advanced while offline.

### Gate 13B — reboot persistence

1. Keep KOReader **Restore Wi-Fi connection on resume** OFF.
2. Keep Wi-Fi OFF.
3. Fully restart KOReader.
4. Reopen the same article and confirm the existing Gate 13 highlight/note survived locally.
5. Still offline, run **Sync now** once.
6. Required:
   - created 0;
   - processed 0;
   - waiting 3;
   - current annotation document status `ok`;
   - metadata pages 0;
   - content pages 0.
7. Return the full report + local-survival result.
8. Do not reconnect Wi-Fi yet.


### Gate 13B — PASS

After full KOReader restart with Wi-Fi still OFF:
- local Gate 13 highlight survived;
- local Gate 13 note survived;
- queue waiting remained 3;
- highlights created remained 0;
- queue processed remained 0;
- metadata/content pages remained 0;
- current annotation document status remained `ok`.

Proceed to Gate 13C reconnect/exactly-once test.

### Gate 13C — reconnect / exactly-once

1. Keep build 0.1.38.
2. Do not create/edit/delete any Gate 13 fixture.
3. Enable Wi-Fi from KOReader's Network menu, outside the Readwise Reader plugin.
4. Confirm internet is available.
5. Run ordinary **Sync now** once.
6. Capture the full report.
7. Check Reader:
   - each pending new highlight/note is under the correct original document;
   - exactly one copy of each;
   - no duplicate.
8. Run **Sync now** again with no changes.
9. Capture the full report again.
10. Required second run:
   - Highlights created = 0;
   - queue waiting = 0;
   - exactly one Reader copy remains;
   - local annotations remain intact.


### Gate 13C attempt 1 — build 0.1.38 — FAIL SAFE / no usable report

Physical result:
- Gate 13A and Gate 13B had already passed;
- Wi-Fi was re-enabled from KOReader outside the plugin;
- ordinary **Sync now** was run once;
- UI returned only `Document sync failed safely`;
- no second Sync was run after this failure.

Do not infer that no remote write happened. The failed child process may have exited before or after mutating one queue item, and the generic UI does not establish the boundary.

### Build 0.1.39 — read-only reconnect diagnosis

Automated/package validation:
- draft PR #16;
- CI run #691 on `edf5fda8e01bfd653e2108c89ae50169486824aa`: **SUCCESS**;
- development checks: SUCCESS;
- full Lua unit suite: SUCCESS;
- ZIP build/layout: SUCCESS;
- artifact upload: SUCCESS;
- artifact ID: `10814635997`;
- artifact name: `readwisereader-koplugin-dbbc15b832486fe75d462ab1c89c72efbf036bfe`;
- outer artifact SHA-256: `96950e35ad6df0f6bc0b3b6e81500e6814065344ee4c5f2770320b017b36f36d`;
- installable inner ZIP SHA-256: `90e21fc2dc8da2e66e5edee21a37285172d71890fc2b3dd727460ce196e6ec0a`;
- inner ZIP `unzip -t`: **PASS**, no errors;
- packaged `constants.lua`: version **0.1.39**;
- packaged diagnostic files present:
  - `ui/reconnect_diagnostics.lua`;
  - `sync/reconnect_probe_worker.lua`;
- packaged ZIP contains no `tests/` entries.

Install 0.1.39 preserving DB/settings/documents/sidecars.

With Wi-Fi ON:
1. **Do not run Sync now.**
2. Do not create/edit/delete any Gate 13 fixture.
3. Run **Readwise Reader → Inspect reconnect queue (Gate 13)** once.
4. This diagnostic is remotely read-only:
   - local durable queue SELECT only;
   - Reader auth GET;
   - Reader highlight LIST for exact KOReader ownership markers;
   - Reader parent GET for text-match readiness;
   - no POST/PATCH/DELETE.
5. Return the whole diagnostic screen.

The diagnostic reports:
- last completed stage;
- auth status inside the KOReader subprocess;
- queue counts by `pending/retry_wait/in_flight/blocked/succeeded`;
- exact remote marker matches for active queue rows;
- read-only parent-document fetch/match status;
- recent queue rows without exposing their text/note/Reader IDs.

If the subprocess ends without a report, the UI reads a tiny local durable stage marker and shows:
`Last durable stage: <stage>`.

Do not resume mutation until this read-only evidence is reviewed.


### Build 0.1.39 physical reconnect diagnostic — parent_reads hard exit

With Wi-Fi ON and **without running Sync now**:
- **Inspect reconnect queue (Gate 13)** was run once;
- diagnostic ended without a report;
- durable last stage: `parent_reads`;
- UI explicitly reported `Remote writes: none`.

This proves the diagnostic passed its earlier queue/auth/marker stages and died only after entering the parent-content phase. It does not distinguish parent HTTP/JSON fetch from text matching yet.

Do not run normal Sync. Next diagnostic must isolate parent fetch from matching and retain sanitized partial evidence even if the child dies.


### Build 0.1.40 — bounded parent-fetch reconnect diagnosis

Reason:
- 0.1.39 physically hard-exited with last durable stage `parent_reads`;
- that stage contained both parent HTTP/JSON fetch and text matching, so it was not sufficient to assign cause.

0.1.40 changes the diagnostic only:
- retains queue/auth/exact-marker reads;
- persists sanitized partial snapshots after every stage;
- probes each active parent metadata-only first;
- probes parent HTML second with a **1 MiB response-body cap**;
- does **not** run text matching;
- displays parent HTML byte count only when the bounded fetch succeeds;
- no POST/PATCH/DELETE;
- no queue promotion/mutation.

Automated/package validation:
- CI run #720: development checks passed, but unit tests failed because the off-device test harness does not provide KOReader's runtime `json` module; no package was built from that failed run;
- test harness corrected with a scoped JSON stub; production code unchanged by that correction;
- CI run #727 on `9179fb8c0aeec4c6ea55f71ab63840ccbdeefc69`: **SUCCESS**;
- development checks: SUCCESS;
- full Lua unit suite: SUCCESS;
- ZIP build/layout: SUCCESS;
- artifact upload: SUCCESS;
- artifact ID: `10815790280`;
- artifact name: `readwisereader-koplugin-26ae1018469053e0bfba13f03f8d243330eab960`;
- outer artifact SHA-256: `8ea1c43a38058f0f536b930fcf72810f17c37db54166a37dae65dfae1d123256`;
- installable inner ZIP SHA-256: `683340446507b9084f8190af7a7e4db91cbf49a779fd54218fd9a0637e927ce4`;
- inner ZIP `unzip -t`: **PASS**, no errors;
- packaged `constants.lua`: version **0.1.40**;
- packaged reconnect worker/UI present;
- packaged ZIP contains no `tests/` entries.

Physical instructions:
1. install 0.1.40 preserving DB/settings/documents/sidecars;
2. keep Wi-Fi ON;
3. do not run Sync now;
4. do not change Gate 13 annotations;
5. run **Inspect reconnect queue (Gate 13)** once;
6. return the whole screen, including any recovered partial snapshot and last durable stage.


### Build 0.1.40 physical result — parent fetch PASS

Read-only reconnect diagnostic completed normally:
- stage `done_fetch_only`;
- auth passed;
- queue pending 3, in_flight 0, blocked 0;
- marker scan passed across 11 pages;
- active marker matches 0;
- all three pending parents fetched metadata + HTML successfully;
- HTML sizes: 9,851 / 27,477 / 8,564 bytes;
- remote writes none.

This rules out parent LIST/JSON/HTML retrieval as the physical hard-exit boundary for these fixtures. The remaining 0.1.39-only work was text matching/normalization, so the next spike must exercise that path read-only and in finer stages before Gate 13C mutation resumes.


### Build 0.1.41 — pure-Lua matcher reconnect diagnosis

Automated/package validation:
- draft PR #16;
- CI run #758 on `eaf9466dece5f7be31d608a3e3c003c2ec3b8c8c`: **SUCCESS**;
- development checks: SUCCESS;
- full Lua unit suite: SUCCESS;
- ZIP build/layout: SUCCESS;
- artifact upload: SUCCESS;
- artifact ID: `10815214175`;
- artifact name: `readwisereader-koplugin-3bb70eba730c69f4552ce04c4c3524a8eb64ced3`;
- outer artifact SHA-256: `83444d6b99770b2d6c843647c0a7ee5e4dae29631bbf93137159ee764a5c8153`;
- installable inner ZIP SHA-256: `77b6d0b109a63916e400155259794f7c147ec600d08d9d084bbd5072e0e59252`;
- inner ZIP `unzip -t`: **PASS**, no errors;
- packaged `constants.lua`: version **0.1.41**;
- packaged ZIP contains no `tests/` entries.

Physical prerequisite already proven by 0.1.40:
- queue pending 3;
- active remote marker matches 0;
- all 3 pending parent metadata/HTML fetches pass;
- HTML sizes 9,851 / 27,477 / 8,564 bytes;
- remote writes none.

0.1.41 diagnostic change:
- annotation matcher no longer loads/calls KOReader native `ffi/utf8proc.normalize_NFC`;
- exact match unchanged;
- conservative Latin canonical composition is pure Lua;
- whitespace/punctuation fallback remains;
- diagnostic invokes the real matcher and persists each matcher phase;
- parent body cap remains 1 MiB;
- no POST/PATCH/DELETE;
- no queue state mutation/promotion.

Physical instructions:
1. install 0.1.41 preserving DB/settings/documents/sidecars;
2. keep Wi-Fi ON;
3. do not run Sync now;
4. do not create/edit/delete Gate 13 annotations;
5. run **Inspect reconnect queue (Gate 13)** exactly once;
6. return the whole diagnostic screen;
7. if the child exits, return the recovered partial snapshot and exact last durable stage.


### Build 0.1.41 physical matcher result — PASS

Read-only Gate 13 reconnect diagnostic:
- stage `done_match_probe`;
- auth passed;
- queue pending 3;
- retry_wait 0;
- in_flight 0;
- blocked 0;
- succeeded 11;
- marker scan passed across 11 pages;
- active marker matches 0;
- item #1: HTML 9,851 bytes, matched exact;
- item #2: HTML 27,477 bytes, matched whitespace;
- item #3: HTML 8,564 bytes, matched whitespace;
- all three remain attempts=0 / remote_id=no;
- remote writes none.

This physically clears the optimized production matcher on the target PW3 for these pending create fixtures.

Proceed to controlled Gate 13C mutation:
1. keep 0.1.41 and Wi-Fi ON;
2. do not alter annotations;
3. run **Sync now once**;
4. return full report before any second Sync;
5. verify Reader contains exactly one copy of each expected new highlight/note.


### Gate 13C first controlled reconnect — plugin PASS

Build 0.1.41 ordinary Sync after the read-only matcher probe passed:
- remote preflight passed;
- highlights created 3;
- queue processed 3;
- queue waiting 0;
- retries/auth waits/blocked creates 0;
- unmatched/ambiguous 0;
- errors 0;
- metadata pages 1;
- content pages 0;
- current document reported `current_document_not_managed`, which is acceptable because create backlog processing is global.

Before the final unchanged second Sync:
1. inspect Reader;
2. confirm all 3 expected new highlights are in the correct original documents;
3. confirm exactly one copy of each;
4. confirm expected note content is present.

Do not run the second Sync until this Reader-side verification is complete.


### Gate 13C Reader verification — PASS

After the first controlled reconnect Sync on 0.1.41:
- all 3 new highlights were found in the correct original Reader documents;
- exactly one copy of each was present;
- expected notes were present;
- no duplicate was observed.

Final idempotency check:
1. make no annotation changes;
2. keep Wi-Fi ON;
3. run ordinary **Sync now** once;
4. require created 0 / processed 0 / waiting 0 / errors 0;
5. verify Reader still has exactly one copy of each Gate 13 item.


### Gate 13 final idempotency — PASS

After the first controlled reconnect created exactly the 3 pending highlights and Reader-side verification confirmed exactly one correct copy of each with expected notes, an unchanged second Sync was run.

Confirmed:
- Highlights created: 0;
- create queue processed: 0;
- create queue waiting: 0;
- unmatched/ambiguous: 0;
- no retry/auth wait/blocker;
- errors: 0;
- Reader still contains exactly one copy of each Gate 13 item.

**Gate 13 PASSED. Phase O complete.**

Next physical gate: Gate 14 / Finished → Archive.


### Phase P / Gate 14 P0 — build 0.1.42 finished-signal spike

Automated/package validation:
- draft PR #17;
- CI #810 caught an unterminated metadata string before tests/package; fixed immediately;
- CI #812 on corrected 0.1.42: **SUCCESS**;
- full Lua suite: SUCCESS;
- package/layout: SUCCESS;
- artifact ID: `10818495299`;
- outer SHA-256: `6cd590229ea205ac64bd027490b738166cb33846e8cacfefb70f6f92433bb58d`;
- installable ZIP SHA-256: `df37908276eb9938a87d3d401a01bbe607bf295cc477288b25e48bbddbfd2a7a`;
- installable ZIP integrity: PASS;
- packaged version: 0.1.42.

Purpose: experimentally verify the KOReader 2026.07.1 persisted Finished signal before implementing any Reader archive PATCH.

Source candidate: `doc_settings.summary.status == "complete"`.

0.1.42 diagnostic guarantees:
- current document must be Reader-managed;
- sidecar/runtime/BookList values are read only;
- remote requests: none;
- remote writes: none;
- local writes: none.

Physical sequence:
1. Install 0.1.42 preserving DB/settings/documents/sidecars.
2. Open one Reader-managed local document that can be used for this gate.
3. Run **Readwise Reader → Inspect finished status (Gate 14)**.
4. Capture the complete **before** screen.
5. Open KOReader **Book status** and choose **Finished**.
6. Close Book status so settings can flush.
7. Run **Inspect finished status (Gate 14)** again.
8. Capture the complete **after** screen.

Expected after state:
- Managed Reader document: yes;
- Local file present: yes;
- Sidecar present: yes;
- Sidecar `summary.status: complete`;
- BookList status: `complete`;
- Runtime `summary.status: complete`;
- Canonical finished candidate: yes;
- remote requests/writes: none;
- local writes: none.

Return both before/after screens. Do not run a new Phase P archive mutation build until this signal spike passes.


### Gate 14 P0 finished-signal physical result — PASS

Target: PW3 / KOReader v2026.07.1 / plugin 0.1.42.

Before marking Finished:
- managed Reader document yes;
- local file yes;
- Reader location in local DB `new`;
- sidecar yes;
- sidecar summary.status `reading`;
- sidecar summary.modified `2026-09-23`;
- sidecar percent_finished `0.1538`;
- BookList status `reading`;
- runtime summary.status `reading`;
- candidate no;
- remote requests/writes none;
- local writes none.

After **Book status → Finished**:
- local DB Reader location still `new`;
- sidecar yes;
- sidecar summary.status **`complete`**;
- sidecar summary.modified `2026-09-24`;
- sidecar percent_finished still **`0.1538`**;
- BookList status **`complete`**;
- runtime summary.status **`complete`**;
- candidate yes;
- remote requests/writes none;
- local writes none.

Result: **PASS**. Canonical Gate 14 signal is persisted `summary.status == "complete"`. Never infer it from percent_finished.

### Gate 14 P1 — build 0.1.43 physical archive test

0.1.43 implements durable/idempotent Finished → Archive.

First Sync:
1. install 0.1.43 preserving DB/settings/documents/sidecars;
2. leave the same fixture Finished;
3. ensure **Settings → Finished documents → Archive in Reader** is checked;
4. Wi-Fi/internet ON;
5. run **Sync now exactly once**;
6. return the whole report;
7. verify in Reader that the document location is Archive;
8. on Kindle verify:
   - local file still exists and opens;
   - sidecar still exists;
   - reading progress remains;
   - existing highlights remain;
   - existing notes remain.

Expected first-report archive fields:
- Finished status detected >= 1;
- Archive intents queued durably >= 1 (unless already archived is safely reconciled);
- Archive queue items processed >= 1;
- Reader documents archived = 1 **or** Archive state reconciled remotely = 1;
- Archive operations blocked safely = 0;
- Archive queue waiting after sync = 0;
- Archive remote errors = 0.

Do **not** run the second Sync until the first result is reviewed.

Second unchanged Sync:
- Reader documents archived = 0;
- Archive queue items processed = 0;
- Archive queue waiting after sync = 0;
- no archive error;
- Reader remains Archive;
- local file/sidecar/progress/annotations remain unchanged.


### Gate 14 P1 first archive local-preservation check — PASS

After the first 0.1.43 Sync archived the target in Reader, Kindle-side verification confirmed:
- local file still exists;
- document still opens;
- reading progress/position preserved;
- existing highlights preserved;
- existing notes preserved.

The first half of Gate 14 P1 therefore passes end-to-end: remote archive occurred without destructive local effects.

Proceed to the final unchanged second Sync:
- make no changes;
- Wi-Fi ON;
- run Sync now once;
- require archived=0 / archive processed=0 / archive waiting=0 / archive remote errors=0;
- Reader remains Archive;
- local state remains intact.


### Gate 14 final idempotency — PASS

After the first 0.1.43 Sync archived the target and the Kindle-side preservation check passed, one unchanged second Sync was run.

Confirmed:
- no repeated archive mutation;
- archive queue remained empty;
- Reader document remained in Archive;
- local document still exists and opens;
- sidecar remains intact;
- reading progress remains intact;
- highlights remain intact;
- notes remain intact;
- no annotation regression or fatal error.

**Gate 14 PASSED. Phase P complete.**

Next physical gate: Gate 15 / content refresh safety.


### Phase Q / Gate 15 Q1 — build 0.1.44 content-refresh safety spike

Purpose:
- prove that a Reader revision on an already-local document cannot silently replace local bytes or lose KOReader progress/annotations;
- establish article visible-text comparison behavior and raw PDF/EPUB deferral before Q2 changes any pending state.

0.1.44 safety contract:
- DB schema migrates v1 → v2 with the normal pre-migration `.bak` backup;
- legacy local files get **no invented materialized revision**;
- a changed Reader revision on an existing local file is persisted as `content_refresh_pending`;
- later no-op Syncs do not forget the pending state;
- existing local document bytes are **never auto-replaced**;
- sidecar is never rewritten by the refresh diagnostic;
- article diagnostic reads local/remote HTML under 4 MiB caps and compares normalized visible text only;
- the diagnostic never displays document text or comparison hashes;
- PDF/EPUB original content is not downloaded by the diagnostic;
- remote writes: none;
- local writes: none;
- automatic replacement allowed: no.

Automated/package validation for 0.1.44:
- draft PR #18;
- CI run #917 on `e491c7ed6096513d623f6ac6129e4ad73de56705`: **SUCCESS**;
- development checks: SUCCESS;
- full Lua unit suite: SUCCESS;
- package/layout: SUCCESS;
- artifact upload: SUCCESS;
- artifact ID: `10821257420`;
- artifact name: `readwisereader-koplugin-fd29f2a8927b20ed8b53af7c43539d3cdaa27ae2`;
- outer artifact SHA-256: `c73318305a728292e4b1c90c0c9da5c86c66de1899a37ad6b02601fc60b77459`;
- installable inner ZIP SHA-256: `6371f5d49656bb7fad201494a81f29bdc6df2e60cb895e39750a103ef84828b6`;
- inner ZIP integrity: PASS;
- packaged version: 0.1.44;
- Gate 15 policy/worker/UI files present;
- packaged ZIP contains no `tests/` entries.

#### Q1-A — article with real reading state

Use a Reader-managed local **article** that already has:
- nonzero reading progress and/or an XPointer;
- at least one highlight;
- preferably a note on that highlight.

1. Install 0.1.44 preserving settings/DB/documents/sidecars.
2. Open that article.
3. Run **Readwise Reader → Inspect content refresh safety (Gate 15)**.
4. Capture the complete baseline screen.
5. Do not change the Kindle document.
6. In Reader, change **only the document title**. Do not delete/re-save the article.
7. Wait until Reader has persisted the rename, then run ordinary **Sync now** once on the Kindle.
8. Capture the complete Sync report.
9. Reopen the same local article and verify:
   - same local file opens;
   - progress/position is unchanged;
   - highlight remains;
   - note remains.
10. Run **Inspect content refresh safety (Gate 15)** again and capture the complete screen.

Required post-revision evidence:
- Sync reports `Content refresh deferred safely >= 1`;
- Sync reports `Content refresh pending review >= 1`;
- no content page/download/replacement occurs for this existing file;
- diagnostic: `Refresh pending: yes`;
- diagnostic: `Sidecar present: yes`;
- diagnostic: reading-state-at-risk = yes;
- diagnostic: `Visible-text comparison: same`;
- diagnostic: `V1 refresh decision: same_visible_text_keep_local`;
- diagnostic: `Automatic replacement allowed: no`;
- diagnostic: remote writes none / local writes none;
- local progress/highlight/note unchanged.

For a legacy pre-v2 file, `Materialized remote revision: unavailable` / `materialized_baseline_unknown` is expected and safe. Do not invent a baseline.

#### Q1-B — raw PDF/EPUB, when an original-format local fixture is available

For one local Reader-managed document with `Local format: pdf` and one with `Local format: epub`:
1. run Gate 15 diagnostic baseline;
2. change only the title in Reader;
3. Sync once;
4. reopen the same local raw file and confirm its sidecar/position/annotations remain intact;
5. run Gate 15 diagnostic again.

Required:
- refresh pending persists;
- decision = `defer_raw_keep_local`;
- automatic replacement = no;
- no raw source download/replacement occurs.

If a suitable original PDF or EPUB is not already locally managed, do not create a risky replacement fixture merely for this spike; report that format as physically pending.

Do not implement Q2 or begin Gate 16 before Q1 evidence is reviewed.
