# Gate 16 hardening / release-candidate runbook

> Canonical gate definition: `IMPLEMENTATION_SPEC.md` Phase R.  
> This runbook records deterministic hardening and the final PW3 release-candidate test.  
> It never authorizes destructive remote cleanup or automatic replacement of existing local document bytes.

## Baseline

- Kindle Paperwhite 3 / firmware 5.16.2.1.1.
- KOReader v2026.07.1, package `kindlepw2`.
- Bookshelf v5.1.4 may remain installed.
- Gate 15 merged to `main` at `3a37df88bae65407d3faaa638c7536ad47fe5744`.
- Known-good rollback plugin build before Gate 16: 0.1.46.
- Gate 16 candidate: 0.1.47.
- Database schema remains **v2**, intentionally compatible with 0.1.46 rollback.

## Deterministic hardening matrix

The CI suite must pass all of these before device installation:

1. **Large library** — 5,000 unique Reader records across 50 pages, callback-streamed with cursor guards and no duplicates.
2. **Low disk** — raw preflight rejects below reserve; exact reserve boundary is accepted; ENOSPC during streamed raw **and processed HTML** writes removes the temp file, preserves a retryable `no_space` classification and exposes no partial final document.
3. **Malformed document** — paged scans isolate/count invalid records, including a whole malformed page with a valid next cursor, and continue valid later records; direct document lookup remains strict.
4. **Huge document** — processed HTML and Reader response/page sizes are bounded before render/materialization.
5. **Unicode** — multilingual filenames/HTML, combining marks, CJK, Arabic and emoji ZWJ survive; byte truncation never cuts a UTF-8 codepoint.
6. **429** — numeric Retry-After is honored; missing value uses bounded fallback; waiting remains cancellable.
7. **Intermittent network** — timeout/offline work is not treated as success; a metadata scan interrupted after partial callback work keeps the old watermark and safely rediscovers/materializes the same document on the next Sync; durable queues survive and ambiguous POST outcomes reconcile before any retry.
8. **Force-close / reboot** — a file-backed SQLite queue survives process re-open; stale highlight creates become blocked, never blind retries; retry deadlines persist.
9. **Migration** — real file-backed v1→v2 migration creates a pre-migration backup retaining old schema/data; transaction failure rolls back.
10. **Rollback** — schema is still v2; 0.1.46 can read the same DB if the 0.1.47 plugin directory is reverted.
11. **Secret review** — production logger calls must not directly reference sensitive payload fields; committed token/signed-URL tripwires pass; API URL query/fragment redaction is unit-tested.

## Before installing 0.1.47 on the PW3

With KOReader closed, preserve copies of:

- `koreader/plugins/readwisereader.koplugin/` (the working 0.1.46 directory);
- `koreader/settings/readwisereader.lua`;
- `koreader/settings/readwisereader.sqlite3` plus any `-wal`/`-shm` present;
- Readwise document directory and its `.sdr` sidecars when practical;
- current `koreader/crash.log` if it contains prior diagnostic evidence.

Do not copy the token/settings file into Git or chat.

## 0.1.47 PW3 release-candidate smoke

After installing only the new plugin directory and restarting KOReader:

1. Readwise Reader loads and existing settings/token remain usable.
2. Open one previously-managed article; position/highlights/notes are intact.
3. Run ordinary `Sync now` on the real library with Wi-Fi on.
   - Sync completes without fatal errors.
   - UI remains responsive/cancellable during long waits.
   - no duplicate documents/highlights;
   - no unexpected content replacement;
   - watermark advances only on success.
4. Run an unchanged second Sync.
   - no duplicate work;
   - no new metadata-only acknowledgement for already-settled article revisions.
5. Turn connectivity off outside the plugin, create a harmless local highlight/note in a managed article, and run Sync once.
   - local work remains durably queued;
   - no remote write is reported.
6. Restart KOReader while that work is still pending, restore connectivity, then Sync.
   - the queue is recovered;
   - the highlight/note reaches the correct Reader document once;
   - no duplicate POST/highlight.
7. Restart KOReader one more time and reopen the same document.
   - progress/highlights/notes remain intact;
   - plugin and Bookshelf still load.
8. Review the resulting `crash.log` locally for a Readwise token, Authorization header, signed raw URL/query or dumped private document/note content. If any appears, Gate 16 fails and the log should not be shared until redacted.

Do not deliberately fill the Kindle filesystem or manufacture corrupt/huge private documents for the physical gate; those failure modes are deterministic CI tests.

## Rollback from 0.1.47 to 0.1.46

If 0.1.47 is unstable:

1. close KOReader;
2. move the 0.1.47 `readwisereader.koplugin/` directory aside;
3. restore the backed-up 0.1.46 plugin directory;
4. keep the current Readwise documents and sidecars;
5. because both builds use schema v2, keep the current SQLite DB unless corruption is suspected;
6. if DB corruption/migration failure is suspected, restore the pre-test DB copy while KOReader is closed;
7. restart KOReader and run one no-op Sync before doing further remote mutations.

Do not roll back Kindle firmware. Do not downgrade KOReader for a plugin-only Gate 16 rollback.
