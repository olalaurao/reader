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

### Run history

#### 2026-09-22 — attempt 1: PARTIAL PASS

Build: `0.0.3`.

The full real-account metadata traversal succeeded:
- top-level documents: **1329**;
- API pages: **25**;
- duplicate records ignored: **0**;
- child records ignored: **1122**;
- locations: archive 176 / feed 40 / later 51 / new 1062;
- categories: article 843 / epub 88 / pdf 31 / podcast 14 / rss 40 / video 313;
- final UI reported that no documents were downloaded or changed;
- no pagination loop or final rate-limit failure was observed.

However, no progress/cancel surface appeared while scanning. The UI looked blocked until completion, so the cancellation smoke test was not possible.

Diagnosis from KOReader 2025.04 source: the plugin called `Trapper:dismissableRunInSubprocess()` without first entering `Trapper:wrap()`, causing KOReader's documented blocking fallback. Fixed in `0.0.4`.

Gate remains open pending the fixed-build retest.

#### 2026-09-22 — attempt 2: PASS

Build: `0.0.4`.

User-reported / visually confirmed results on target PW3 / KOReader 2025.04:
- visible scan/cancel status surface rendered: **yes**;
- placement was lower/left rather than centered: **yes; cosmetic only**;
- cancellation worked: **yes**;
- KOReader remained responsive / did not stay stuck: **yes**;
- subsequent full scan completed and showed the full summary: **yes**;
- plugin did not change Wi-Fi state: **yes**;
- no document was downloaded or altered: **yes**.

Combined with attempt 1's successful full traversal (25 pages / 1329 top-level documents), all Gate 2 criteria are satisfied.

Conclusion:
- **Gate 2 PASSED.**
- Phase E may begin after Phase D is merged to `main`.

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
