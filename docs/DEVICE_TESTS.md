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
