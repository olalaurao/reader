# Implementation Status

> This file is the resumability ledger for implementation. Update it after every meaningful work session.  
> Canonical design: `IMPLEMENTATION_SPEC.md`  
> Roadmap/product intent: `PLAN.md`

## 2026-09-24 — Phase R / Gate 16 hardening session

- **Milestone:** Phase R / Gate 16 — deterministic/off-device hardening in progress. Gate 15 remains passed complete.
- **Branch / HEAD:** `hardening/gate16-r1` / `91c6f5c8b1b8989c148f9fa0c9574e444a86be3e` before this STATUS commit.
- **Base inspected:** current `main` HEAD `3a37df88bae65407d3faaa638c7536ad47fe5744` (Gate 15 merge). `STATUS.md`, `IMPLEMENTATION_SPEC.md`, and `PLAN.md` were re-read from current GitHub state before changes.
- **Files altered:** `readwisereader.koplugin/tests/test_reader_pagination.lua`, `readwisereader.koplugin/tests/test_installer.lua`, `readwisereader.koplugin/tests/test_http.lua`, `readwisereader.koplugin/tests/test_filenames.lua`, and this `STATUS.md`.
- **Implemented/validated off-device:** no production behavior changed. Added deterministic hardening coverage for a synthetic 12,000-document/120-page Reader corpus; ENOSPC after a streamed download has begun; malformed Reader document records; a single oversized HTTP chunk crossing the configured response ceiling; cancellation during a 429 `Retry-After` wait; and UTF-8/multibyte filename truncation at the byte boundary.
- **Commits:** `be6be410` large-library pagination stress; `ba655f17` mid-stream disk exhaustion; `f7023bf3` malformed Reader item; `291a4f22` oversized response ceiling; `201ab69e` cancellable 429 backoff; `91c6f5c8` multibyte filename boundary.
- **Tests/checks:** test cases were added against existing pure-Lua contracts. GitHub Actions had not yet exposed a workflow run for the branch commits at the time of this handoff, so the full `./scripts/dev-check.sh`, Lua unit suite, package/layout build and artifact verification are **pending CI confirmation**; do not mark these new hardening cases passed until CI is green.
- **Gates concluded this session:** none. Gate 16 remains open.
- **Physical tests pending:** none requested yet. Per spec, deterministic/off-device hardening must be completed first.
- **Bugs/failures found:** no new production bug isolated yet. Existing code already has bounded Reader LIST pacing/repeated-cursor protection, raw-source free-space preflight, atomic temp-file install, response byte ceilings, 429 handling, and UTF-8-aware filename truncation; this session adds regression/stress evidence around those contracts.
- **Technical decisions:** exercise existing safety contracts before changing production code; do not add speculative hardening when the current implementation already expresses the required invariant. Large-library stress intentionally uses 12,000 unique records, materially above the current real library, while keeping the fixture generated in-memory and free of private data.
- **Spec deviations:** none.
- **Blockers:** CI result for the new branch tests is the immediate blocker to calling the deterministic cases passed.
- **Continuation:** GitHub combined status and PR-triggered workflow lookup still expose no checks for the branch, so CI remains unavailable rather than green. Added commit `cf97d452` locking the HTTP debug-log contract to path-only URLs (signed/query secrets are not emitted) and `26e67af0` exercising a real SQLite v1->v2 migration failure to verify transaction rollback preserves `user_version=1`, pre-existing rows, and removes the partially-added v2 column.
- **Current HEAD:** `26e67af0bd4944a94ac83e245fa308216a4c2f5b` before this STATUS commit. Branch is 9 commits ahead of Gate-15 `main`, with no production-code changes.
- **Tests/checks:** deterministic tests added, but the repository exposes no commit status / PR-triggered workflow run for this branch; therefore they remain pending execution rather than falsely recorded as passed.
- **Next exact steps, in order:** (1) execute the full dev-check/unit/package suite as soon as an executable CI/local runner is available and fix any fixture failure; (2) continue deterministic Gate 16 coverage for persistence/restart and intermittent-network queue recovery where existing tests do not already prove the invariant; (3) audit remaining logger calls for payload/token/signed-URL exposure; (4) update STATUS with executable evidence; (5) then define the smallest PW3 physical hardening matrix.

## 2026-09-25 — Gate 16 deterministic hardening complete; physical matrix next

- **Milestone:** Phase R / Gate 16 deterministic/off-device hardening is complete enough to enter the physical PW3 matrix. Gate 16 itself remains **OPEN** until the required device behavior passes.
- **Branch / HEAD before this STATUS commit:** `hardening/gate16-r1` / `908c9a8d347ebe26ffc838255e377dc82c3c43f1`. Draft PR #20 targets `main`.
- **CI evidence:** push workflow run #1148 (`36077985219`) on `908c9a8d` **SUCCESS**: development checks/Lua 5.1 syntax, complete Lua unit suite, package build, ZIP layout verification and artifact upload all passed.
- **Failure found and fixed:** the first Unicode boundary assertion was itself invalid because a valid multibyte code point naturally ends in a continuation byte. Runs from `91c6f5c8` through `8ed43b85` therefore failed at that test before later modules could execute. Commit `908c9a8d` replaced the faulty assertion with a complete Lua 5.1 UTF-8 structural validator; the full suite then passed.
- **Additional hardening added:** `8ed43b85` uses a file-backed SQLite DB across close/reopen to simulate a process/KOReader restart. An in-flight create survives durably and startup recovery blocks the ambiguous create instead of blindly retrying it; attempt count and payload remain intact.
- **Logs/redaction audit:** focused audit of the production entry/worker/probe/API/UI paths found only the stage-only worker warning and HTTP request debug log in the audited paths. HTTP logging passes the new regression proving query/signed-URL secrets are stripped by `safeUrl`; no token/payload logging was added.
- **Production behavior changed:** none in Phase R so far; hardening commits are tests/docs only.
- **Deterministic coverage now evidenced green:** large-library pagination (12,000 docs), low-storage mid-stream ENOSPC cleanup, malformed Reader item, oversized HTTP response, cancellable 429 wait, Unicode filename boundary, signed/query URL log redaction, migration transaction rollback, and durable queue/restart recovery.
- **Physical tests pending:** Gate 16 now needs the smallest real-device matrix for properties that off-device tests cannot establish: PW3 responsiveness/performance, real Wi-Fi interruption/recovery, process force-close/restart with durable queued work, reboot with durable queued work, sidecar/progress preservation through those failures, and install/rollback smoke.
- **Spec deviations:** none.
- **Next exact step:** perform the Gate 16 PW3 physical matrix below. Do not merge PR #20 or mark Gate 16 complete until it passes.

### Gate 16 physical matrix — first test only

Start with **R1: real intermittent Wi-Fi recovery**. Use an already-downloaded Reader-managed article; do not delete it or its sidecar.

1. With Wi-Fi on, open the article and create one new disposable highlight (a short unique sentence is best).
2. Turn Wi-Fi off / enable Kindle Airplane Mode.
3. Run **Readwise Reader -> Sync now** once.
4. Confirm the sync fails safely/queues locally rather than hanging or losing the highlight.
5. Turn Wi-Fi back on / disable Airplane Mode and wait until Kindle connectivity is actually restored.
6. Run **Sync now** again.
7. Check Reader and confirm that exact highlight appears **once**.
8. Run **Sync now** one more time and confirm it still appears only once.

Report only: whether the offline sync returned safely; whether the recovery sync succeeded; whether the highlight appeared once; whether the second online sync duplicated it; and any error text shown. If R1 passes, STATUS should be updated before advancing to force-close/reboot tests.

## 2026-09-25 — Gate 16 R1 physical PASS; R2 force-close next

- **Physical evidence supplied by user:** Gate 16 R1 real intermittent-Wi-Fi matrix passed completely on the target PW3: offline Sync returned safely, the subsequent online recovery Sync succeeded, the new highlight appeared remotely exactly once, and the second online Sync did not duplicate it. No blocking error was reported.
- **Conclusion:** hardening item 7 (Wi-Fi/rede intermitente) is **PASS**. This also re-confirms durable local discovery/queueing before remote-write eligibility and idempotent recovery under the real Kindle network behavior previously found unreliable in Gate 13.
- **Code changes for R1 result:** none required; observed production behavior matches the existing contract.
- **Branch / HEAD before this STATUS commit:** `hardening/gate16-r1` / `5c64a888c5ad541914f1ca8609f76d3637d4401c`; CI on that HEAD is green for both push and draft PR #20.
- **Gate 16:** remains **OPEN**. Per the canonical hardening order, the next unresolved device-only item is force-close, followed by reboot. Do not skip to reboot before force-close is observed.
- **Next physical test — R2 force-close with durable queued work:** use an already-downloaded Reader-managed article. With Wi-Fi/Airplane Mode OFFLINE, create one new disposable highlight and run Sync once so it is discovered/persisted locally and remote write is withheld. Then fully exit/force-close KOReader (do not reboot the Kindle), relaunch KOReader, restore Wi-Fi, run Sync, and verify in Reader that the exact highlight appears once. Run Sync once more and verify no duplicate. Also confirm the article still opens at its prior reading position and its pre-existing highlights/notes remain present. Report: offline Sync safe; KOReader closed/reopened normally; recovery Sync succeeded; highlight appeared once; second Sync did not duplicate; progress/old annotations preserved; any error text.

## 2026-09-25 — Gate 16 R2 force-close physical PASS; R3 reboot next

- **Physical evidence supplied by user:** the complete R2 force-close matrix requested in the previous STATUS handoff passed on the target PW3. Offline Sync returned safely with the new highlight queued, KOReader closed/reopened normally without rebooting the Kindle, online recovery Sync succeeded, the highlight appeared remotely exactly once, the following Sync did not duplicate it, and the document's prior reading position plus existing highlights/notes remained intact. No blocking error was reported.
- **Conclusion:** hardening item 8 (force-close/process restart with durable queued work) is **PASS** on-device. Together with the deterministic file-backed SQLite restart test, this closes the force-close persistence risk without production changes.
- **CI evidence entering R2:** commit `401769249f9c37b7560932082c215382c07c0d6d` passed both push run `36078395879` and draft-PR run `36078399808`.
- **Code changes for R2 result:** none required.
- **Gate 16:** remains **OPEN**. The next canonical hardening item is 9, reboot; migration/rollback/log-redaction evidence already exists off-device but cannot be used to skip the real reboot matrix.
- **Next physical test — R3 full Kindle reboot with durable queued work:** use an already-downloaded Reader-managed article. Start offline/Airplane Mode, create one new disposable highlight, and run Sync once so the operation is durably queued while remote writes are withheld. Then perform a full Kindle restart/reboot (not merely KOReader exit). After the Kindle and KOReader return, restore Wi-Fi and wait for real connectivity, run Sync, and verify the exact highlight appears in Reader once. Run Sync once more and verify no duplicate. Open the article and confirm prior reading position plus pre-existing highlights/notes are intact. Also confirm the Readwise Reader plugin/settings/token still load normally after the reboot. Report: offline Sync safe; Kindle rebooted normally; plugin/settings survived; recovery Sync succeeded; highlight appeared once; second Sync did not duplicate; progress/old annotations preserved; any error text.

## 2026-09-25 — Gate 16 R3 reboot physical PASS; R4 rollback smoke next

- **Physical result:** the full R3 reboot matrix requested in the previous handoff passed on the target PW3. Offline Sync safely persisted the new highlight; the Kindle rebooted normally; plugin settings/token survived; recovery Sync succeeded; the highlight appeared remotely once; the following Sync did not duplicate it; prior reading position and existing highlights/notes remained intact. No blocking error was reported.
- **Conclusion:** hardening item 9 (reboot with durable queued work) is **PASS** on-device. R1-R3 now cover intermittent network recovery, process restart, full reboot, durable queue recovery and preservation of document state.
- **CI entering R3:** commit `9bf7c007d234d5b998056f9a432aa04e7bf8c585` passed push run `36078690845` and draft-PR run `36078694778`.
- **Already evidenced off-device:** migration rollback and log/redaction have green deterministic coverage on this branch. No production-code change is justified by R3.
- **Remaining device-only closure:** installation/rollback smoke required by hardening item 50. Gate 16 remains open until that passes.
- **Next physical test (R4):** back up the current known-good plugin directory plus settings/database; exit KOReader; temporarily disable the plugin by moving its directory out of the active plugins directory while leaving Reader documents/sidecars untouched; relaunch and confirm KOReader starts normally without Readwise Reader; exit again, restore the exact plugin directory, relaunch, confirm Readwise Reader and its settings/token load; open an existing managed article and verify position/highlights/notes; run one online Sync and confirm success without duplicates.

## 2026-09-25 — Gate 16 R4 PASS; Gate 16 complete

- Physical R4 install/rollback smoke passed on the target PW3: KOReader started normally with the plugin temporarily disabled; restoring the same plugin directory restored Readwise Reader; token/settings and existing document progress/highlights/notes were preserved; online Sync succeeded without duplicates; no blocking error was reported.
- Gate 16 is **PASSED COMPLETE** on PW3 / KOReader v2026.07.1. Phase R now has green evidence for the full hardening sequence, including large-library pagination, storage failure cleanup, malformed/oversized input, Unicode, 429 handling, intermittent network recovery, process restart, full reboot, migration rollback, install/rollback, state preservation and log redaction.
- No production behavior changed in Phase R; hardening changes are regression/stress tests and documentation.
- CI entering closure: `1d8830f790d72f2c12e75d9f6e6c64498e429dc8`; push `36078991043` and PR `36078995811` both passed.
- Spec deviations: none.
- Next: final CI on this closure commit, merge PR #20 to main if green, then begin Phase S / V1 acceptance. Do not tag v1.0.0 before the complete acceptance script passes.

## 2026-09-25 — Phase R merged; Phase S / V1 acceptance started

- **Gate 16 / Phase R:** PASSED COMPLETE on target PW3 / KOReader v2026.07.1, including R4 installation/rollback smoke.
- **Merge:** PR #20 merged to `main` as `bdbee7262123ae7dd16a38ac9602b436a322d336` after branch CI on `d560972a2af0e9bc9256178a1950f92d3b7f1781` passed for both push (`36079141231`) and PR (`36079143999`).
- **Production changes in Phase R:** none; tests/docs only.
- **Current phase:** Phase S / V1 acceptance. Per IMPLEMENTATION_SPEC section 42, the complete acceptance script must pass on the actual PW3 before `v1.0.0` may be tagged.
- **No off-device implementation is justified before acceptance begins:** the first unresolved evidence is physical Reader -> Kindle acquisition on a fresh Reader article. Existing deterministic suites already cover the underlying pagination/download/install contracts; do not manufacture a substitute for the real-device acceptance path.
- **Acceptance A1 (next physical checkpoint; steps 1-6):** begin with the installed plugin and no pending queue items; save one new article in Reader; ensure Wi-Fi is enabled outside KOReader; run `Sync now`; confirm the new article downloads exactly once; open it and read enough to establish a non-zero reading position. Do not create the acceptance highlight/note yet. Report: Sync success/error, article present once, opens normally, and reading position established.
- **Gate/release state:** Phase S OPEN; `v1.0.0` NOT authorized until the entire section-42 script passes.

## 2026-09-25 — Phase S handoff verified; A1 is the next blocker

- Re-inspected merged `main`, canonical `STATUS.md`, `IMPLEMENTATION_SPEC.md`, and `PLAN.md` before advancing.
- PR #20 is closed/merged; Phase R landed as `bdbee7262123ae7dd16a38ac9602b436a322d336`. Current `main` before this commit is `0fa5f82cd6491c40ec22b4ceb99e0403dfaf0cc0` (`docs: start Phase S V1 acceptance`).
- Gate 16 remains PASSED COMPLETE. No later implementation gate may substitute for the section-42 real-device V1 acceptance sequence.
- No production change is justified before A1: the next missing evidence is physical acquisition/opening of a fresh Reader article on the target PW3.
- **Exact blocker:** Acceptance A1 / section-42 steps 1-6. Start with no pending queue; save one new article in Reader; Wi-Fi on; `Sync now`; verify exactly one local copy; open it and establish non-zero reading position. Do not create the acceptance highlight/note yet.
- After A1 PASS, record it before proceeding to the offline annotation portion (steps 7-14).

## 2026-09-25 — Phase S Acceptance A1 PASS; A2 offline annotation next

- **A1 physical PASS on target PW3:** user confirmed the section-42 steps 1-6 checkpoint passed completely: Sync succeeded, the fresh Reader article materialized locally exactly once, opened normally, and a non-zero reading position was established.
- **CI entering A1:** `fcf6ea4105a0c018623bb37050b4255bed556108` push run `36079421068` completed SUCCESS.
- **Production changes:** none. The observed end-to-end Reader -> Kindle path matches the accepted contracts.
- **Phase S:** remains OPEN; do not tag V1 yet.
- **Next physical checkpoint — A2 / section-42 steps 7-14:** on the same article, turn Wi-Fi off; continue reading; create one highlight; attach the exact note `ver [[Foucault]] e [[Biopolítica]]\n\n#pesquisar`; close and reopen the document and confirm the annotation is still present; while still offline run `Sync now`; confirm Sync returns safely and the annotation remains pending/not lost. Do not restore Wi-Fi yet. Report whether offline reading worked, highlight/note survived reopen exactly, offline Sync returned safely, and annotation remained pending.

## 2026-09-25 — Phase S Acceptance A1 PHYSICAL PASS; A2 offline annotation next

- Re-read canonical STATUS/spec/plan and verified current `main` CI before recording this result.
- **A1 / section-42 steps 1-6:** PHYSICAL PASS on target PW3. User confirmed the online Sync succeeded, the fresh Reader article materialized locally exactly once, opened normally, and a non-zero reading position was established.
- **CI entering A1:** current `main` `f2c0fe58afdcf650d597d150060078401d539c49` passed push run `36079534163`.
- No production code change is warranted by A1; observed behavior matches the existing Reader -> Kindle acquisition contract.
- Phase S remains OPEN. `v1.0.0` remains unauthorized until the complete section-42 acceptance script passes.
- **Next physical checkpoint A2 / steps 7-14:** on this same acceptance article, turn Wi-Fi off; continue reading; create one highlight; add the exact note `ver [[Foucault]] e [[Biopolítica]]\n\n#pesquisar`; close and reopen the document and confirm the annotation remains; while still offline run `Sync now`; confirm it returns safely and the annotation remains pending/not lost. Do not restore Wi-Fi yet. Report: offline reading worked, exact note survived close/reopen, offline Sync returned safely, annotation remained present/pending, and any error text.

## 2026-09-25 — Acceptance A2 passed

A2 (acceptance steps 7-14) passed on the target PW3. Offline reading and the new annotation survived document reopen and an offline sync without loss. No production change was required. The prior A1 documentation commit passed CI run 36079597398. Phase S remains open. Next checkpoint is A3 (steps 15-20): reconnect, sync the same annotation to its original Reader document, verify the note, then sync again and verify no duplicate.

## 2026-09-25 — Acceptance A3 passed

A3 (acceptance steps 15-20) passed on the target PW3. After connectivity returned, Sync uploaded the queued highlight to the same original Reader document; the note remained intact; a second Sync created no duplicate. CI run 36079680834 for the A2 documentation commit passed. No production change was required. Phase S remains open. Next checkpoint is A4 (steps 21-23): export/sync through Readwise to Obsidian, confirm the wikilinks behave as links there, then exercise the already-in-scope note-update path and verify the edited note reaches Reader.

## 2026-09-25 — Acceptance A4 passed

A4 (acceptance steps 21-23) passed on the target workflow: Readwise export/sync reached Obsidian, the acceptance wikilinks behaved as expected, and the in-scope note-update path was exercised successfully back to Reader without creating a parallel highlight. CI run 36079750409 for the A3 documentation commit passed. No production change was required. Phase S remains open. Next checkpoint is A5 (steps 24-25): retryable network failure recovery followed by KOReader restart with a pending queue item; both must recover without duplication.

## 2026-09-25 — Acceptance A5 passed

A5 (acceptance steps 24-25) passed on the target PW3. With Wi-Fi unavailable, a new disposable highlight was discovered and retained locally; KOReader was fully closed and reopened while the queue item remained pending; after connectivity returned, Sync recovered the item to the same Reader document exactly once; the following Sync produced no duplicate. This satisfies the Phase-S retryable-network-failure and KOReader-restart-with-pending-queue checks. CI run 36079801327 for the A4 documentation commit passed. No production change was required.

Phase S remains OPEN. The next unresolved V1 acceptance evidence comes from PLAN.md criteria 17-20, which are part of canonical V1 scope even though section 42 of IMPLEMENTATION_SPEC.md does not spell them out: repeat Reader location -> managed Collection projection and Reader tag -> Bookshelf metadata projection on the current acceptance document before marking it finished/archive.

## 2026-09-25 — Acceptance A6 passed

A6 (PLAN.md V1 acceptance criteria 17-18) passed on the target PW3. On the same acceptance document, a Reader location change synced to the corresponding managed `Readwise: ...` Collection without creating a second local copy, while the document's non-managed local Collection remained associated. This re-validates location projection and ownership preservation in the integrated V1 flow. CI run 36079933898 on the prior Phase-S handoff passed. No production change was required.

Phase S remains OPEN. The next unresolved integrated criterion is A7 / PLAN.md 19-20: change a Reader document tag, sync, and confirm the same local document receives updated Bookshelf-compatible tag/genre/keyword metadata without creating a Collection per tag.

## 2026-09-25 — Acceptance A7 passed

A7 (PLAN.md V1 acceptance criteria 19-20) passed on the target PW3. On the same acceptance document, a Reader-side tag change synced into the document's Bookshelf-compatible metadata (tag/genre/keyword) without creating a managed Collection for the tag and without duplicating the local document. CI run 36080108838 for the A6 handoff passed. No production change was required.

Phase S remains OPEN. The remaining physical acceptance is now reduced to: (A8) mark this acceptance document finished, sync, verify Reader Archive plus intact local file/sidecar/progress/annotations; then (A9) inspect final logs for secrets/private content and run one final no-op Sync proving zero new documents/highlights. If both pass, Phase S can close and release-candidate/tag work can proceed off-device.

## 2026-09-25 — Acceptance A8 passed

A8 (IMPLEMENTATION_SPEC.md acceptance steps 26-30 and PLAN.md V1 acceptance criteria 24-27) passed on the target PW3. The same acceptance document was marked Finished in KOReader; with Archive in Reader enabled, one Sync moved the document to Reader Archive. The local file remained present and opened normally, reading position/progress remained intact, and existing highlights/notes remained intact. No production change was required.

Phase S remains OPEN only for A9: final log/redaction review plus one unchanged no-op Sync proving zero new documents/highlights. Do not tag `v1.0.0` before A9 passes and Phase S is explicitly closed.

## 2026-09-25 — Phase S final off-device log audit complete

Before requesting the final device log, the production Lua tree was re-audited for logging callsites. The only production logger calls are:
- `api/http.lua`: request method plus `safeUrl(url)`; `safeUrl` strips the entire query string before logging;
- `sync/worker.lua`: a fixed warning plus the non-sensitive worker stage name;
- `ui/article.lua`: three Gate-3/UI exception warnings containing only the caught exception string.

No production logger call intentionally writes Authorization headers, access tokens, request bodies, response bodies, annotation text, document HTML, Reader titles/IDs, or signed URL query parameters. Existing `test_http.lua` regression coverage explicitly verifies that an Authorization token and signed/query secrets are absent from HTTP debug logs. No production change is justified by this audit.

A9 remains the only V1 acceptance blocker. The next physical evidence is the actual KOReader `crash.log` from the target Kindle after the completed A1-A8 acceptance run, inspected for token/signed-URL/full-private-content leakage. After that log passes, run exactly one unchanged online `Sync now` and require zero newly downloaded documents and zero newly created highlights before closing Phase S.

## 2026-09-25 — Phase S A8/A9-off-device handoff

- Branch: `main`.
- Pre-handoff HEAD: `40821b37710f0c05b2a4cb35af1d48d641da6a1d`.
- Files changed in this continuation: `STATUS.md`, `PLAN.md`; no production Lua changed.
- A8: PHYSICAL PASS — Finished -> Reader Archive completed; local file, sidecar, progress, highlights and notes preserved.
- A9 off-device half: PASS — final logging/redaction audit found no regression; production logging remains path-only/stage-only and signed/query-secret redaction regression coverage is present.
- CI: workflow `36080770490` on `40821b37710f0c05b2a4cb35af1d48d641da6a1d` completed SUCCESS.
- Gates 0-16 remain PASSED COMPLETE. Phase S remains OPEN only for the final physical A9 evidence.
- No bugs/failures requiring production changes were found in this continuation.
- Spec deviations: none.
- Exact blocker / next physical action: inspect the target Kindle's current KOReader `crash.log` for access token, signed source URL/query credentials, or full private document/annotation content; if clean, make no Reader/Kindle changes and run exactly one online `Sync now`. Require zero new document downloads, zero new highlights created, no repeated archive mutation, and zero fatal errors. After that PASS, Phase S may be closed and release-candidate/`v1.0.0` work can proceed off-device.

## 2026-09-25 — Acceptance A9 PHYSICAL PASS; Phase S complete

User confirmed the complete final A9 checkpoint on the target PW3: the real KOReader log from the completed acceptance run contained no access token, signed source URL/query credential, or full private document/annotation content; the final unchanged online `Sync now` produced zero new document downloads, zero new highlights, no repeated Archive mutation, and no fatal error.

This closes IMPLEMENTATION_SPEC section 42 steps 31-32 and the final PLAN.md V1 acceptance requirements. A1-A9 are now PASSED as one integrated V1 flow on the target PW3 / KOReader v2026.07.1. Gates 0-16 and Phase S are PASSED COMPLETE. No production bug or spec deviation was found in A9.

Release authorization: `v1.0.0` is now allowed after release-version/documentation preparation and a green full CI/package run. Do not change the validated sync behavior during release preparation.

## 2026-09-25 — V1 release candidate green on main

- **Milestone:** Phase S / V1 acceptance PASSED COMPLETE; runtime version is now `1.0.0`.
- **Branch / validated release HEAD:** `main` at `221a8a6a7cd2c39b09bed8c87829a9f5cd908d0d` before this documentation-only closeout commit. It is byte-for-byte the release candidate that was tested on `release/v1.0.0` and then fast-forwarded to `main`.
- **Files changed by the release-preparation commit:** `STATUS.md`, `IMPLEMENTATION_SPEC.md`, `PLAN.md`, `README.md`, `CHANGELOG.md`, `docs/DEVICE_TESTS.md`, `readwisereader.koplugin/constants.lua`, and `readwisereader.koplugin/_meta.lua`.
- **Production behavior changes:** none. Only version/metadata/documentation changed after physical acceptance.
- **Automated validation:** workflow `36081055755` on release commit `221a8a6a...` completed **SUCCESS**. Development checks, full Lua unit suite, installable ZIP build, package-layout verification, and artifact upload all passed.
- **Release artifact:** `readwisereader-koplugin-221a8a6a7cd2c39b09bed8c87829a9f5cd908d0d`, artifact id `10842220953`, artifact digest `sha256:1453dbd54441880749aa0652315f471e4b66d2feff84a26108d7bfb9c71d1486`.
- **Physical acceptance:** A1-A9 PASS; no device test remains pending for V1.
- **Bugs/failures:** none open that block V1; no release-preparation CI failure.
- **Technical decision:** freeze runtime behavior between the accepted build and V1 tag; release preparation only changes version/docs.
- **Spec deviations:** none.
- **Only remaining release action:** create Git tag `v1.0.0` pointing at the final green `main` documentation-closeout commit. The currently available GitHub connector does not expose tag/ref creation for tags, so do not substitute a branch for a tag.
- **Next step:** after this docs-only closeout commit passes CI, create `v1.0.0` at that exact green `main` SHA. No further Kindle test is required unless runtime code changes.

## 2026-09-25 — Phase T / Gate 17A started: Reader → KOReader existing highlights

User requested post-V1 Reader → KOReader import after observing that an original Reader EPUB downloaded correctly but its pre-existing Reader highlights did not appear in KOReader.

Canonical review confirmed this was an explicit V1 non-goal, not an EPUB-download regression. Scope is now deliberately extended for v1.1.

Architecture validated before implementation:
- current Reader API v3 exposes highlight child records with `parent_id`, `content`, `notes`, `highlight_offset`, and `highlight_location`;
- Reader `highlight_location` is a serialized position in Reader processed HTML and cannot be treated as a CRengine XPointer for an original EPUB;
- KOReader v2026.07.1 rolling documents expose `findAllText()` with `start/end` XPointers and `getTextFromXPointers()` for exact round-trip validation;
- KOReader local insertion path is known, but intentionally remains disabled until the locator spike passes;
- Reader LIST has no documented `parent_id` filter, so Gate 17A scans `category=highlight` with existing pagination/rate-limit/cancellation safeguards and filters exact parent locally.

Branch: `feature/v1.1-reader-highlight-import`.
Build: `1.1.0-alpha.1`.

Implemented Gate 17A:
- Reader API normalization now preserves highlight `content`;
- read-only worker resolves the current managed EPUB/HTML and scans Reader highlight children;
- exact `parent_id` filtering and stable offset/date ordering;
- UI probes at most 3 highlight texts using KOReader's own full-text search;
- only one literal result with valid XPointer start/end and exact text round-trip counts as unique;
- ambiguous/missing/different results are reported;
- remote writes = 0; local writes = 0;
- PDF is explicitly rejected until a separate paging-position spike.

No sidecar, annotation, queue, DB-link, or remote mutation path is enabled yet. Gate 17B remains blocked on physical PW3 evidence from a real managed EPUB that already contains Reader highlights.

## 2026-09-25 — Gate 17A off-device implementation green; PW3 probe next

- **Branch / code HEAD validated:** `feature/v1.1-reader-highlight-import` / `8e4d4e42476fdd0bccf0eeaee97f583bbfbe5032`.
- **Build:** `1.1.0-alpha.1`.
- **CI:** workflow `36089780096` completed **SUCCESS**. Development checks, full Lua unit suite, installable ZIP build, package-layout verification and artifact upload all passed.
- **Artifact:** `readwisereader-koplugin-8e4d4e42476fdd0bccf0eeaee97f583bbfbe5032`, artifact id `10844249761`, outer artifact digest `sha256:ef730dacbf74931a53ace718cac6b3d4f56c3839415c8a1dc5378490eb317da5`.
- **Implemented/verified off-device:** Reader highlight `content` normalization; exact parent filtering; safe EPUB/HTML-only scope; stable remote ordering; at-most-three local probes; unique/ambiguous/missing classification; exact XPointer text round-trip; UI/preflight behavior; PDF rejection in this gate.
- **Safety:** Gate 17A performs zero Reader writes and zero local annotation/sidecar/DB-link writes.
- **Production import status:** NOT enabled. Gate 17B is blocked on physical locator evidence.
- **Next physical test:** install this alpha preserving settings/DB/documents/sidecars; open the same managed EPUB that already has Reader highlights; Wi-Fi ON; run **Readwise Reader → Inspect Reader highlights (Gate 17A)** once; return the full result. PASS requires at least one `Unique exact XPointer matches` and both `Remote writes: none` / `Local writes: none`. Do not create/delete/edit highlights for this probe.

## 2026-09-25 — Gate 17A attempt 1 BLOCKED by false rolling preflight

Physical attempt 1 on the target PW3 did not reach the Reader/XPointer probe. With the managed EPUB open, the plugin showed `Gate 17A currently supports rolling EPUB/HTML documents only`.

Root cause was identified in the Gate 17A UI preflight, not in the EPUB or Reader data: the alpha compared `reader_ui.rolling ~= true`, but KOReader exposes `ui.rolling` as a module/object for rolling documents rather than the literal boolean `true`. A valid EPUB therefore failed the preflight.

No remote or local annotation write occurred; the failure happened before the worker/probe ran. Existing document/sidecar state was not mutated.

Required fix before retry:
- treat any non-nil/truthy `reader_ui.rolling` module as rolling;
- regression-test with a table/object value, not boolean `true`;
- rerun full CI/package checks;
- then repeat only the same Gate 17A physical probe.

## 2026-09-25 — Gate 17A false rolling preflight fixed; retry build green

The attempt-1 failure was fixed by treating KOReader's `reader_ui.rolling` as the module/object it actually is, instead of requiring the literal boolean `true`.

Regression coverage now stubs `rolling = {}` so this exact KOReader runtime shape is locked in. No locator/import behavior changed beyond allowing a valid rolling EPUB/HTML to reach the existing read-only Gate 17A probe.

- fix commit: `f81820f74bb3cbb85b5c0190dbfe512b3fceecc2`;
- regression test commit: `b36dea9ea9a2110f8f74ac2395a9a5c8f962fcb7`;
- CI workflow `36091470601`: **SUCCESS**;
- development checks: PASS;
- full Lua unit suite: PASS;
- installable ZIP build: PASS;
- package layout verification: PASS;
- artifact upload: PASS;
- CI artifact id: `10846016344`;
- extracted install ZIP SHA-256: `c0862e027254d4aa28af90721504cff799d587ade30d46986e46c41c18e1d5a3`.

Gate 17A remains OPEN only for the physical retry. Repeat the same read-only test on the same managed EPUB with existing Reader highlights. No annotation should be created yet.

## 2026-09-25 — Gate 17A PHYSICAL PASS

Target PW3 physical result after the rolling-preflight fix:
- Reader highlight pages scanned: **11**;
- Reader highlight records scanned: **1086**;
- exact highlights belonging to the open managed EPUB: **70**;
- highlights with text: **70**;
- local match probes run: **3**;
- unique exact XPointer matches: **3/3**;
- ambiguous matches: **0**;
- missing matches: **0**;
- other/invalid matches: **0**;
- remote writes: **none**;
- local writes: **none**.

This proves the Gate 17A architecture on the real target: Reader highlight child identity can be filtered by exact `parent_id`, and at least the sampled existing Reader highlight texts can be resolved unambiguously to real CRengine XPointer ranges in the original local EPUB. No Reader DOM locator was reused as a KOReader position.

Gate 17A is **PASSED COMPLETE**. Gate 17B is unblocked: import exactly one existing Reader highlight into the currently-open EPUB through KOReader's native highlight path, preserve its Reader note literally, persist the sidecar, immediately link the resulting local annotation ID to the existing Reader highlight child ID in SQLite, and prove reopen persistence plus no outbound duplicate on the next Sync.

## 2026-09-25 — Gate 17B off-device implementation green; one-item import physical test next

Gate 17A is PASSED physically (70 Reader highlights found for the real EPUB; 3/3 sampled passages resolved to unique exact XPointers).

Build `1.1.0-alpha.2` implements Gate 17B without advancing to bulk import:
- shared KOReader locator returns only an exact unique XPointer range with exact text round-trip;
- import action prefers an existing Reader highlight with a note when one is available;
- exactly one unlinked remote highlight is imported per action;
- KOReader's native `ReaderHighlight:saveHighlight()` creates the annotation in the currently-open rolling EPUB/HTML;
- `ReaderUI:saveSettings()` flushes the sidecar;
- the plugin immediately re-reads the sidecar and requires the newly-created local annotation ID to be present before linking anything in SQLite;
- the imported local annotation is linked transactionally to the pre-existing Reader highlight child ID with synced text/note hashes and remote update marker;
- next outbound annotation scan therefore sees the local annotation as already remote-linked instead of queueing a new Reader highlight create;
- if sidecar persistence or durable link creation fails, the just-created local highlight is rolled back and settings are saved again;
- no Reader mutation is executed by the import action.

New deterministic coverage:
- exact unique/missing/ambiguous locator behavior;
- Reader note retention in the remote probe;
- persisted-sidecar verification and durable import linker;
- remote-ID repository lookup + transactional imported link;
- successful one-item UI import including note transport;
- local rollback when durable linking fails;
- existing storage semantics with an imported annotation row.

CI failures found/fixed before handoff:
1. first Gate 17B run `36092424664` caught Lua gettext shadowing from a numeric `_` loop variable in the new success path; fixed in `b1a5e003...`;
2. second run `36092540482` showed only a stale storage-test count (fixture now correctly contained two annotations); expectation fixed in `8f4e7885...`.

Validated code HEAD before documentation closeout: `8f4e7885a308b7b88f53d287ebdf852948b873f6`.
Full CI `36092610213`: **SUCCESS** — dev checks, full Lua suite, installable ZIP, package-layout verification and artifact upload all passed.
Artifact id: `10846108427`; artifact digest: `sha256:5806a68ab891d1563fb606422ffde43bca906aeb0ec8626f6c0aafc80a7b8a33`.

Gate 17B remains OPEN only for target-PW3 proof. Do not implement Gate 17C bulk/idempotent integration until this one imported highlight survives close/reopen and a subsequent ordinary Sync proves it is not uploaded as a duplicate.

## 2026-09-25 — Gate 17B handoff finalized

Documentation/handoff HEAD `d1e61a042d75e8872f868f47daa6e513789d239c` passed full CI workflow `36092823512` **SUCCESS** after the implementation-green run `36092610213`.

Installable Gate 17B build supplied for the next PW3 checkpoint:
- version: `1.1.0-alpha.2`;
- validated implementation commit: `8f4e7885a308b7b88f53d287ebdf852948b873f6`;
- CI artifact id: `10846108427`;
- extracted install ZIP SHA-256: `617db37861d1fea5512bfd9a9cd96dcb9be11056c4b6baadfdfd9cd10ca05fc5`.

No Gate 17C work has begun. Exact blocker is Gate 17B-1 physical import + close/reopen persistence on the same EPUB. Ordinary Sync must not be run until 17B-1 is reported.

## 2026-09-25 — Gate 17B-1 physical import + reopen persistence PASS

User completed the first Gate 17B physical checkpoint on the target PW3 using build `1.1.0-alpha.2` and the same managed EPUB from Gate 17A.

Accepted physical evidence:
- the explicit **Import one Reader highlight (Gate 17B)** action reported `Imported local highlights: 1`;
- the imported highlight was visible in the KOReader EPUB;
- the imported Reader note was present locally;
- after closing and reopening the EPUB, both the imported highlight and its note remained present;
- no ordinary Sync had been run before this persistence proof.

Conclusion:
- local creation through KOReader's native highlight path + sidecar persistence has passed on-device;
- Reader note transport has passed for the imported item;
- Gate 17B remains OPEN only for the outbound-deduplication proof and final reopen check;
- Gate 17C remains blocked.

### Next exact physical checkpoint — Gate 17B-2 outbound dedupe
1. Keep Wi-Fi ON and the same EPUB available.
2. Run ordinary **Readwise Reader -> Sync now** exactly once.
3. In Reader, inspect the exact imported highlight and verify that there is still only **one** remote highlight for that passage/note; the Sync must not create a duplicate child.
4. Report the Sync result/error text and whether the Reader highlight is still present exactly once.
5. If no duplicate was created, close/reopen the EPUB once more and verify the imported local highlight/note remain intact. That will close Gate 17B.

Do not run the explicit Gate 17B import action again during this checkpoint.

## 2026-09-25 — Gate 17B-2 outbound dedupe PASS; final reopen remains

User reported the requested ordinary Sync checkpoint completed correctly on `1.1.0-alpha.2`:
- ordinary **Sync now** succeeded;
- the imported Reader highlight remained present remotely exactly once (no duplicate child was created);
- its Reader note remained correct.

This closes the outbound-deduplication requirement for the imported Gate 17B annotation. The pre-Sync close/reopen persistence proof already passed in 17B-1.

One formal Gate 17B criterion from the canonical spec has **not yet been explicitly reported**: close/reopen the EPUB once more *after* that successful ordinary Sync and confirm the imported local highlight/note still remain. Gate 17B therefore remains OPEN only for that final post-Sync reopen observation.

## 2026-09-25 — Gate 17C off-device candidate implemented; physical start still gated

Build `1.1.0-alpha.3` is implemented on branch `feature/v1.1-reader-highlight-import`.

Implementation commits:
- `46689342a35d2e3ae20ba2710106b949473ae44a` — bounded bulk Reader → KOReader import integrated with manual Sync;
- `b1da02f36b8ea6d5b036bdc46f281c70171f1e71` — repair accidental literal newline syntax in constants.

CI:
- initial run `36094436071` stopped at development checks because two inserted newlines in `constants.lua` were encoded literally as `\\n`; no unit tests ran on that failed revision;
- corrected run `36094535608` is **SUCCESS**: development checks, complete Lua unit suite, installable ZIP build, package-layout verification and artifact upload all passed.
- artifact id: `10847216168`;
- extracted install ZIP SHA-256: `6f5b56ee7786826cfdcda0f57f5b97ede7a8424e06a54695099e7f99e782122c`.

Gate 17C candidate behavior:
- successful online manual Sync may run a parent-process Reader → KOReader import pass for the currently-open managed rolling EPUB/HTML only;
- remote highlight fetch remains read-only and subprocess-isolated;
- local import is bounded to 20 newly-created annotations and 30 locator attempts per run;
- already-linked Reader child IDs are skipped before locator work;
- ambiguous/missing/invalid text locations and exact local-position collisions are skipped, never guessed;
- each created annotation preserves the Reader note and still follows the proven 17B order: native KOReader save → sidecar save → sidecar verification → durable Reader child-ID link;
- a per-item sidecar/link failure rolls back only the just-created local item and stops the batch safely;
- cancelling/failing the post-Sync import does **not** undo or falsify a document Sync that already completed and committed its watermark;
- repeated runs are covered deterministically: linked IDs import zero times, and bounded batches advance without duplicating earlier imports;
- the Sync report now exposes Reader → KOReader import status/counters.

Sequencing note: Gate 17C code was prepared after the outbound-dedupe proof but before the final post-Sync Gate 17B reopen was explicitly reported. **Do not physically execute Gate 17C or call Gate 17B complete until that final reopen passes.** No Gate 17D work has begun.

### Exact next physical action
With the currently-installed `1.1.0-alpha.2`, close the same EPUB and reopen it once. Confirm the Gate 17B imported highlight and its note are still present. If yes, Gate 17B closes and `1.1.0-alpha.3` becomes authorized for the Gate 17C physical matrix.

## Current milestone

**Phase T / Gate 17A — Reader → KOReader existing-highlight locator spike; V1.0.0 remains released**

Phase P / Gate 14 is complete and merged to `main` through PR #17 as `5d7c954d051e491c1b11344057c59df7e2cf9656`.

Gate 15 Q1-A physical result on PW3 / KOReader v2026.07.1 / build 0.1.45:
- 0.1.44 crash was fixed in 0.1.45;
- baseline article had `percent_finished=0.1538`, 6 annotations, XPointer and checksum;
- Reader title-only same-ID revision produced `Content refresh pending review: 1`;
- Sync downloaded **0 content pages** for the existing file;
- local progress/position, highlights and notes remained intact;
- post-revision diagnostic: pending yes, remote probe passed, visible-text comparison **same**, decision `same_visible_text_keep_local`, replacement no;
- remote/local diagnostic writes: none.

Therefore Q1-A article safety **PASSED** and Q2 was authorized.

Build 0.1.46 implements Q2 without enabling replacement:
- normal Sync examines up to 5 pending HTML articles per cycle;
- local/Reader HTML reads are bounded to 4 MiB;
- only the exact durable pending `updated_at` revision may be acknowledged;
- normalized visible-text equality clears only the pending marker;
- local document bytes and sidecar/progress/annotations are never rewritten;
- changed/unverified/raced article revisions remain pending;
- raw PDF/EPUB revisions remain pending and are not replacement-downloaded;
- automatic byte replacement remains disabled.

Gate 15 remains **OPEN** only until raw-format coverage/scope is closed. Article Q2 acknowledgement and unchanged-second-Sync idempotency are now physically passed.

### Gate 4A migration step — KOReader upgrade completed

Physical result on target PW3:
- backup completed before upgrade;
- KOReader upgraded from 2025.04 to **2026.07.1** using the official `kindlepw2` package;
- KOReader relaunched successfully after the update;
- Kindle firmware/jailbreak/KUAL were not changed;
- Bookshelf is not installed yet.

### Gate 4A-1 — PASS

Physical result on target PW3 / KOReader 2026.07.1:
- Readwise Reader loads after the KOReader upgrade;
- existing token remains usable and `Test connection` succeeds;
- previously-downloaded Reader article opens normally;
- reading progress is preserved;
- existing highlight + note are preserved;
- two consecutive `Sync now` runs complete with no errors and no duplicates;
- `Full document rescan` cancels cleanly;
- KOReader remains responsive after cancellation;
- cancelled rescan does not advance the document watermark;
- one Reader-side move/rename on an already-managed article syncs without duplicate/same ownership breakage;
- KOReader restart succeeds and Readwise Reader continues to load/settings persist.

Conclusion:
- **Gate 4A-1 PASSED.**
- official KOReader **v2026.07.1** is now the canonical physical V1 baseline for Phase G and later work;
- KOReader 2025.04 remains the historical Gate 0–4 compatibility baseline only;
- next blocker is **Gate 4A-2: Bookshelf v5.1.4 coexistence**, including Reader location Collections and Reader tags -> Bookshelf-compatible metadata.

### Gate 4A-2 preparation

- Gate 4A-1 documentation CI run #132: **SUCCESS**.
- Pinned Bookshelf release: **v5.1.4**.
- Official asset: `bookshelf.koplugin.zip`.
- SHA-256: `f23a66dd1ea50e80ddc421f0c5b62b5a7ebe99da05e63be59bd5ae3d08537dc0`.
- Install target on Kindle: `/mnt/us/koreader/plugins/bookshelf.koplugin/`.
- KOReader built-in **Cover browser** must be enabled.
- Keep normal File Manager as startup initially; do **not** enable `Start with -> Bookshelf` until coexistence passes.

Physical Gate 4A-2 smoke result:
- Bookshelf v5.1.4 installed from the official `bookshelf.koplugin.zip`;
- Bookshelf tab appears in KOReader;
- Readwise Reader still appears after Bookshelf installation;
- plugin-load coexistence therefore passes the initial smoke check.

Next: open Bookshelf manually, verify Readwise-managed documents/Collections/open-close/progress and run Readwise sync while Bookshelf is installed. Reader-tag metadata projection is not yet implemented in code and will be added after the base coexistence checks pass.


### Gate 4A-2 attempt 1 — FAIL / hard UI freeze in Bookshelf

Physical result on target PW3 / KOReader 2026.07.1 + Bookshelf v5.1.4:
- Bookshelf opened successfully;
- a Readwise-managed article was visible in Bookshelf;
- while navigating Bookshelf tabs/shelves (Home/Recent), the UI hard-froze;
- the Kindle stopped responding to normal input;
- recovery required holding the power button until the Kindle rebooted.

This is a **Gate 4A-2 failure**, not a cosmetic issue. Do not mark Bookshelf coexistence passed until the freeze is diagnosed and reproduced/fixed or safely attributed upstream.

Immediate next action:
- preserve/retrieve the latest `koreader/crash.log` before more Bookshelf activity can overwrite useful context;
- do not enable `Start with -> Bookshelf`;
- keep normal File Manager as startup;
- Readwise Reader baseline from Gate 4A-1 remains valid unless the log shows cross-plugin corruption.

Crash-log diagnosis from the failed Bookshelf session:
- KOReader was on v2026.07.1;
- both Bookshelf and Readwise Reader loaded; only the expected deprecated `_meta.lua name` warnings were emitted;
- there is **no Bookshelf Lua traceback** before the hard freeze;
- immediately after Bookshelf loaded/was opened, KOReader logged repeated FreeType failures for Bookshelf's bundled fonts:
  - `RobotoCondensed-Regular.ttf`;
  - `Inter-ExtraBold.ttf`;
  - `Caveat-Regular.ttf`;
- these filenames match Bookshelf v5.1.4's bundled/fresh-install default fonts and its startup font-install path;
- therefore the strongest current lead is Bookshelf first-run bundled-font installation/registration or corrupted copied font files, not a Readwise Reader exception.

Controlled recovery before retest:
1. with KOReader closed, keep the Readwise documents/sidecars/settings/database intact;
2. optionally move unrelated legacy books off-device (after backup) to reduce the library Bookshelf/CoverBrowser scans; do not assume Reader PDF/EPUB support exists yet;
3. rebuild CoverBrowser metadata cache after the content cleanup by removing only `koreader/settings/bookinfo_cache.sqlite3` while KOReader is closed;
4. ensure Bookshelf bundled TTFs are present and valid in Kindle's `/mnt/us/fonts/` before KOReader starts; if necessary overwrite them from `koreader/plugins/bookshelf.koplugin/fonts/`;
5. restart KOReader once so the font scanner sees them before Bookshelf is opened;
6. retry only Bookshelf Home -> Recent navigation first. If it still hard-freezes, stop and collect the new log before any further coexistence work.

### Gate 4A-2 attempt 2 — recovery retest

After a controlled Kindle/Documents cleanup and recovery of the required KUAL/Readwise content:
- Bookshelf opens;
- Home navigation works;
- Series and Genres are noticeably slow on the PW3, but no longer hard-freeze;
- the previous hard-freeze was **not reproduced** in this retest;
- required KUAL launcher files and Readwise document content were restored successfully.

Current interpretation:
- Bookshelf is usable again, but Series/Genres performance remains a device/library-size concern;
- keep `Start with -> Bookshelf` disabled until the remaining coexistence checks pass;
- continue Gate 4A-2 with targeted functional checks only; do not stress-test large grouped shelves unnecessarily.


### Gate 4A-2 base coexistence functional pass

Physical result on target PW3 / KOReader 2026.07.1 + Bookshelf v5.1.4:
- a Readwise-managed article opens successfully from Bookshelf;
- existing reading progress is preserved;
- closing the article returns to Bookshelf without crash;
- Readwise Reader `Sync now` completes successfully with Bookshelf installed;
- a second no-op sync completes without creating duplicates.

Base Bookshelf/Readwise coexistence is therefore **PASS**. Remaining Gate 4A-2 blockers are:
- validate Reader-location Collections inside Bookshelf and a Reader-side location move;
- implement and validate Reader tags -> Bookshelf-compatible metadata;
- final restart/persistence/no-op coexistence check.


### Gate 4A-2 Collections move test — PASS

Physical result:
- managed Readwise Collections appear in Bookshelf;
- Reader-side location move is reflected in the new managed Collection;
- the document leaves the old managed Collection;
- unrelated user Collection membership is preserved;
- no duplicate local document or duplicate entry in the same Collection was created;
- the same document appearing once in its managed Readwise Collection and once in the unrelated user Collection is expected multi-Collection membership, not duplication.

### Gate 4A-2 Reader tags -> Bookshelf genres — 0.1.12 physical FAIL; 0.1.13 fix ready

0.1.12 physical result:
- all targeted coexistence checks passed except Bookshelf Genres;
- Bookshelf Genres remained empty even after Reader tag add/change and successful sync;
- no duplicate was created; progress/highlight/note, restart, Collections and no-op sync remained good.

Root cause:
- Reader Document LIST returns document `tags` in practice as an object/map of tag records whose values contain `name`, not as the array-of-strings shape assumed by 0.1.12;
- 0.1.12 iterated tags with `ipairs`, so the object yielded zero tag names and wrote an empty `keywords` field;
- the older upstream Readwise Reader plugin already has explicit handling for this real LIST response shape.

Experimental build: **0.1.13**.

Implemented:
- Reader document `tags` are projected to KOReader custom metadata `keywords`;
- values are newline-separated so Bookshelf consumes them as independent Genres;
- Reader tag order is preserved, duplicates/empty values are removed, and embedded newlines inside a tag are normalized safely;
- an empty Reader tag list explicitly writes `keywords = ""` so stale embedded genres do not reappear;
- a projection-version marker (`reader-tags-v1`) triggers a **one-time metadata-only full Reader LIST backfill** for already-managed documents;
- that backfill does **not** replay the expensive HTML/content materialization;
- unchanged Collections are not rewritten during the one-time tag backfill, while real Reader-side location moves are still applied;
- subsequent Reader tag changes use the normal incremental sync and keep the same Reader-ID/local path ownership.

Automated validation:
- Run #153 on `3d4a107...`: **SUCCESS** after fixing the Lua nil-valued ternary in the new metadata backfill;
- Run #155 on `ec09d544...`: **SUCCESS** — syntax, unit tests, package/layout and artifact build, including tag-update/backfill and minimal-Collection-write coverage;
- installable inner ZIP SHA-256: `3a283e2aaa7fa47d67880b191c9df0a1ea459343f2283d9abdfd183ae0386297`.

0.1.13 fix + optimization:
- normalize both Reader tag shapes at the API boundary:
  - LIST object/map values with `{ name = ... }`;
  - arrays of tag strings used by create/update contracts/tests;
- bump projection marker to `reader-tags-v2` so affected existing documents repair automatically;
- narrow the one-time projection repair to `category=article`, excluding highlight/note child records server-side;
- during that repair, only tagged documents need a metadata sidecar rewrite; untagged documents and unchanged Collections are not rewritten;
- the normal incremental sync path remains watermark-based;
- normal incremental sync no longer stats every managed local file on every run; it trusts the durable `is_local_present` bit for unchanged rows and verifies the filesystem only for changed/repair-relevant documents;
- no-op syncs skip the KOReader Collections refresh entirely when there is no postprocess work;
- explicit Full document rescan remains the repair path that verifies all managed local paths on disk.

Expected performance impact on this real library:
- previous all-document metadata repair traversed the whole Reader corpus, historically ~25 LIST pages including child records;
- v2 repair should traverse roughly the article subset (~843 top-level articles in the last full scan), about 9 LIST pages at limit 100, plus sidecar writes only for tagged articles;
- at the documented 20 LIST requests/minute pacing, that removes most of the one-time wait but cannot eliminate the API rate-limit floor.

Automated validation:
- run #159: SUCCESS — actual Reader LIST tag-object fixture;
- run #160: SUCCESS — narrowed projection repair implementation;
- run #161: SUCCESS — optimized v2 tag-repair coverage;
- run #163 on `b45a1dea...`: SUCCESS — tag repair build;
- run #167: SUCCESS — normal sync filesystem-walk optimization;
- run #168: SUCCESS — no-op Collections refresh optimization;
- run #169: SUCCESS — unit coverage proving no-op incremental sync does not stat every managed file;
- run #170 on `7fc5141b...`: SUCCESS — final 0.1.13 optimized build, syntax/tests/package/layout/artifact;
- installable inner ZIP SHA-256: `da646cfe674a4734f8a8ee9cb178e4d519e28612f962afe1042aa45db6ce3a69`.

Gate 4A-2 remains **OPEN only for a short 0.1.13 physical tag visibility check**. Do not run a manual full document rescan.

0.1.13 physical retest — partial:
- Bookshelf Genres is no longer empty; existing Reader document tags now appear, confirming the tag-object decoding/projection fix works on-device;
- the distinctive temporary test tag did **not** appear;
- user confirmed the missing test tag is a **document tag**, not a highlight tag;
- therefore Gate 4A-2 still has one real tag-coherency bug to isolate.

Targeted isolation added in experimental **0.1.14**:
- uses Reader's public Tag LIST endpoint to resolve an exact document-tag name to its tag key;
- uses Reader's tag-filtered Document LIST endpoint to ask the API directly which documents are associated with that tag;
- cross-checks returned document IDs against the plugin's managed/local database state;
- reports counts only (tag exists, matching documents, top-level/article matches, managed/local matches and categories), avoiding another whole-library rescan;
- this distinguishes:
  1. Reader API not exposing the UI-visible tag association;
  2. Reader API exposing it but the plugin failing to project it.

Automated validation:
- runs #173–177 passed implementation/UI wiring;
- run #179 on `27f3c05...`: **SUCCESS** — full syntax/unit/package/layout/artifact;
- installable 0.1.14 inner ZIP SHA-256: `7f54925596654e0975dabffe2973c4664e7f0c0a4335ff925e8850675cf08323`.

0.1.14 physical diagnostic result for document tag **`tag teste`**:
- Tag exists in Reader Tag API: **yes**;
- Documents returned for this tag: **1**;
- Top-level documents: **1**;
- Top-level articles: **1**;
- Already managed by this plugin: **1**;
- Managed + local: **1**;
- Returned payloads containing this tag name: **1**;
- Categories: `article=1`;
- Tag API pages: **1**; document pages: **1**.

This proves Reader's public API currently exposes the missing tag on the exact top-level article already owned locally by the plugin. The remaining fault is therefore between normal incremental change discovery and KOReader metadata postprocess, not Reader UI/tag classification and not Bookshelf genre parsing.

0.1.15 adds one further targeted probe: for each matching managed document, query the same ID again using the plugin's current `document_query_after` watermark and report whether Reader returns it through `updatedAfter`, plus whether the stored remote revision already equals the current remote revision. This requires only one extra document request for this one-document test and avoids another library scan.

0.1.15 physical diagnostic result for document tag **`tag teste`**:
- incremental query watermark: `2026-09-23T03:25:29Z`;
- visible through incremental `updatedAfter`: **1**;
- stored revision already equals remote: **0**;
- remote revision newer than stored: **1**.

This proves a tag-only Reader change **is** surfaced by the exact incremental query used by the plugin and the plugin database has not already consumed that revision. Combined with the 0.1.14 proof, Reader change discovery is working correctly.

Root cause isolated in Bookshelf v5.1.4 cache behavior:
- Readwise Reader writes the changed custom `keywords` metadata and broadcasts KOReader `InvalidateMetadataCache` + `BookMetadataChanged`;
- Bookshelf's `onBookMetadataChanged` invalidates its per-chip/group result caches via `invalidateBookCache()`, but deliberately keeps its **light metadata cache** warm;
- Bookshelf Genres are grouped from that light metadata cache;
- Bookshelf's own repository comments state that changes to metadata content such as genres require `invalidateLightMeta()`, otherwise chips can remain stale;
- this exactly explains the device result: the one-time backfill/restart exposed the historical tags, while a later incremental tag edit wrote the sidecar but the already-warm Genres source remained stale.

Experimental **0.1.16** fix:
- after a parent-process sync successfully writes one or more KOReader metadata sidecars, call a single optional Bookshelf cache refresh;
- only act if `lib/bookshelf_book_repository` is already loaded, so there is no hard Bookshelf dependency and no cost when Bookshelf is absent/not yet used;
- invalidate `light metadata` once, then invalidate Bookshelf book/group result caches once;
- do not repeat invalidation per article;
- no-op syncs still perform no Bookshelf cache refresh.

0.1.16 physical result:
- existing Reader document tag `tag teste` appeared in Bookshelf Genres after one normal incremental sync;
- the tag was then deleted in Reader;
- one more normal incremental sync removed it from Bookshelf Genres;
- no Full document rescan or extra KOReader restart was required for either direction;
- the stale Bookshelf light-metadata cache fix therefore behaves as intended.

### Gate 4A-2 — PASS

Gate 4A-2 is closed on the target PW3 / KOReader 2026.07.1 + Bookshelf v5.1.4.

Validated across the complete coexistence sequence:
- both plugins load and survive restart;
- Bookshelf opens Reader-managed documents and preserves progress/highlight/note state;
- normal and no-op Readwise syncs remain idempotent;
- Reader location changes update only plugin-managed Collections and preserve unrelated user Collections;
- Reader document tags appear as Bookshelf Genres;
- later tag add/remove changes propagate through a normal incremental sync;
- no duplicate local document is created;
- the initial Bookshelf hard-freeze did not reproduce after the controlled device/library/font recovery; Series/Genres can still be slow on the PW3, so this remains a performance note rather than a gate blocker.

**Phase F.5 is complete. Phase G / Gate 5 (images) is now unblocked.**

## Phase G — images

### G1 relative local asset spike — build 0.1.17 ready

Canonical baseline:
- Kindle PW3;
- KOReader v2026.07.1;
- Bookshelf v5.1.4 may remain installed.

Research before implementation:
- KOReader v2026.07.1's own QuickStart generator comments that **crengine will not accept full image paths** and rewrites image references to relative paths before opening generated HTML;
- this supports testing document-relative local assets as the preferred alternative to putting large image payloads inside the HTML;
- the older community Readwise Reader plugin instead inlined downloaded images as data URIs and explicitly warned that image-heavy HTML could destabilize memory-constrained ereaders;
- therefore G1 deliberately validates adjacent relative assets first before selecting the production image strategy.

0.1.17 adds a diagnostic-only menu action:
- **Readwise Reader -> Image asset spike (Gate 5)**;
- installs a tiny diagnostic HTML under `<download_root>/Diagnostics/`;
- installs one local SVG under `Diagnostics/gate5-assets/`;
- HTML references it only as `gate5-assets/gate5-test.svg` (no absolute Kindle path);
- also references one intentionally missing relative asset;
- opens the diagnostic HTML directly through the existing KOReader document adapter;
- does not change normal Reader sync or download behavior.

Expected device evidence:
1. the local `GATE 5` image renders;
2. text before and after it remains readable;
3. the intentionally missing image does not crash/freeze KOReader;
4. text after the missing image remains readable;
5. close/reopen preserves normal document behavior.

Physical G1 result on the target PW3: **PASS**.
- local relative SVG rendered;
- text before/after remained readable;
- intentionally missing relative image did not crash/freeze KOReader;
- text after the missing image remained readable;
- close/reopen worked normally.

Therefore the relative-local-asset contract is accepted for G2.

### G2 bounded production image cache — implementation in progress

Chosen strategy:
- keep article HTML small; never inline fetched images as data URIs;
- store article assets in a deterministic hidden sibling directory under `Articles/`;
- rewrite `<img src>` to document-relative local paths validated by G1;
- strip `<picture>/<source>` alternate remote sources after localization so CRengine does not bypass the local asset;
- replace failed/disabled/over-limit images with a small textual placeholder while preserving surrounding article text.

Conservative PW3 caps:
- max 2 MiB per image response;
- max 8 MiB fetched/cached image budget per article;
- max 20 image download attempts per article;
- HTTP response sink aborts once the per-request body limit is crossed, so one unexpectedly huge image is not accumulated fully in RAM.

Failure policy:
- image failure is non-fatal to the document;
- unsupported/broken/oversized images are counted and replaced with placeholders;
- article HTML remains installable/readable;
- successful asset files use the existing atomic installer;
- newly-created assets are cleaned up if the parent HTML installation ultimately fails.

Settings/reporting:
- `Settings -> Documents -> Download article images` toggle added (default ON);
- sync summary reports downloaded/reused/skipped/failed image counts and cached bytes;
- existing already-local articles are not rewritten just to add images; remote content refresh remains Phase Q, so Gate 5 production validation must use a newly-materialized article.

Automated validation:
- bounded HTTP response body test: PASS;
- image URL dedupe, PNG/JPEG/SVG detection, local relative rewrite, `<picture>/<source>` stripping and graceful failed-image placeholder tests: PASS;
- disabled-image and over-limit behavior tests: PASS;
- deterministic hidden asset directory tests: PASS;
- article materializer integration test: PASS;
- run #234 on `f37143af...`: **SUCCESS** — syntax, all unit tests, packaging/layout and artifact;
- installable inner ZIP SHA-256: `16f4447911cf817b0cd673649f102013febc77a45d8b0d9f291fc78735d69cf8`.

0.1.18 physical result: **FAIL — article images did not download/render**.

Root cause found by comparing the production parser with the archived community Reader plugin and the Reader HTML shapes it handles:
- 0.1.18 only treated a literal `<img src="...">` as an image candidate;
- Reader commonly emits responsive images through `<picture><source srcset="...">` and lazy-image attributes such as `data-src` / `srcset`;
- 0.1.18 then stripped `<source>` elements after processing, so a responsive picture could end up with **zero downloadable candidates**;
- this is consistent with the device symptom: article materialization succeeded but image download did not happen.

0.1.19 fix:
- normalize `<picture>/<source srcset>` into one concrete `<img>` before localization;
- choose a <=1200px responsive candidate when available;
- support direct `img srcset`, `data-src`, `data-lazy-src`, `data-original` and `data-url`;
- prefer lazy/responsive URLs over tiny data-URI placeholders;
- keep the existing relative-local-asset, size caps, timeout/failure placeholders and atomic install strategy;
- sync report now shows **Image candidates found** and **Responsive images promoted** to make this failure class visible.

Important test constraint:
- an article already materialized by 0.1.18 is intentionally considered local and is **not rewritten** by a later ordinary sync; this is the conservative content-refresh contract held until Phase Q;
- therefore the 0.1.19 Gate 5 retest must use a **different newly-saved Reader article** that has never been downloaded to this Kindle.

Automated validation for 0.1.19:
- actual responsive `<picture><source srcset>` fixture: PASS;
- direct `img srcset`: PASS;
- lazy `data-src`: PASS;
- density-only picture srcset keeps the proven `<img>` fallback instead of choosing an arbitrary 1x/2x source: PASS;
- all existing image caps/failure tests remain green;
- run #244 on `2c3cb8e...`: **SUCCESS** — syntax, unit tests, package/layout and artifact;
- installable inner ZIP SHA-256: `11f8e3273d9b5a2e8fdc6152a373714f5b6dab5063a69a0e46614f8ce1dc6ca4`.

Build **0.1.19** is ready for a **new-article** physical retest. Do not reuse the article already materialized without images by 0.1.18, because ordinary sync deliberately does not rewrite an existing local HTML document before Phase Q.

0.1.19 physical retest — partial PASS evidence:
- a newly materialized image-heavy Reader article rendered at least one real inline image on the PW3;
- therefore responsive/lazy candidate discovery, HTTP fetch, local asset install, relative-path rewrite and CRengine rendering all work end-to-end for at least one production image;
- other article images did not all appear, which is acceptable for Gate 5 if the article text remains usable and KOReader stays stable, because Gate 5 explicitly requires graceful tolerance when some images fail;
- user did not capture the sync summary counters, so exact candidate/download/skip counts are unavailable for this run.

Do not delete/re-download this same local article merely to recover the report: normal sync intentionally treats it as already local before Phase Q. If counters are needed later, use a different newly-saved article.

Final physical confirmation:
- close/reopen succeeded;
- the successfully localized image remained visible;
- article text remained usable;
- no freeze/crash was reported.

### Gate 5 — PASS

Gate 5 is closed on the target PW3 / KOReader 2026.07.1.

Accepted production behavior:
- at least one real Reader article image is localized end-to-end as an offline relative asset;
- image failure is non-fatal and the text remains usable;
- missing/unsupported/over-limit images may degrade to placeholders;
- the PW3 remains responsive;
- already-local documents are not rewritten just to add/fix images before Phase Q content-refresh safety work.

**Phase G is complete. Phase H / Gate 6 (raw PDF + EPUB with fallback) is now unblocked.**

## Phase H — raw PDF / EPUB

### 0.1.20 implementation ready for Gate 6

Baseline:
- target PW3 / KOReader v2026.07.1;
- Bookshelf v5.1.4 may remain installed;
- Phase G / Gate 5 is closed and merged to `main` through PR #8 as `f33bcd6210931b3d74bcb5a814e1cc9e3591fec2`.

Implemented H1/H2/H3/H4:
- Reader `raw_source_url` is requested only when a PDF/EPUB actually needs materialization; signed source URLs are never persisted and request logging strips their query parameters;
- raw files stream directly from HTTP into a temporary file instead of being accumulated fully in Lua memory;
- streamed files are fsynced, minimally validated, atomically renamed and temp files are removed on failure;
- PDF validation requires the `%PDF-` signature;
- EPUB validation requires ZIP magic;
- safety cap: **64 MiB per raw source**;
- free-space reserve before raw download: **128 MiB**;
- transient network/no-space failures remain retryable and do not silently substitute content;
- missing/expired/non-distributable/invalid/over-limit raw sources may fall back to Reader processed HTML **only when usable HTML exists**;
- raw-without-fallback becomes a stable nonretryable per-document content skip rather than stranding the global watermark;
- local state records the actual format/strategy (`reader_raw_source` vs `reader_html_fallback`);
- normal sync supports PDF/EPUB categories, but they remain OFF by default so upgrading does not unexpectedly backfill the user's whole raw-format library;
- sync summary reports original raw downloads, HTML fallbacks and raw bytes;
- targeted **Readwise Reader -> Test PDF / EPUB (Gate 6)** picker was added so physical Gate 6 can test exactly one PDF and one EPUB without enabling global category filters;
- if the chosen item only produces HTML fallback, the Gate 6 UI says so and asks for a different document instead of falsely treating the fallback as an original-format pass.

Automated coverage includes:
- bounded streaming HTTP sink and sink failure;
- streamed temp/fsync/validate/atomic-install lifecycle;
- PDF/EPUB magic validation;
- raw missing/invalid/oversize/fallback eligibility;
- no-space preflight;
- original PDF materialization and EPUB HTML fallback;
- raw source with no HTML fallback;
- full and incremental sync requesting fresh raw URLs only for raw categories;
- targeted Gate 6 candidate fetch requesting both processed HTML and a fresh raw URL;
- targeted Gate 6 UI: original raw opens normally, while HTML fallback still receives KOReader metadata/Collection projection but is explicitly rejected as original-format gate evidence.
- run #294: **SUCCESS** — raw/fallback UI path coverage;
- run #295 on `84741215...`: **SUCCESS** — full syntax, all unit tests, package/layout and artifact;
- run #296 on `5852ac33...`: **SUCCESS** — final 0.1.20 documentation/build tip;
- installable inner ZIP verified with `unzip -t`; SHA-256: `20fe677c52ea4eefba24c4fb4e98c09b286df04f2b0eaddd416f64e2de4fd23c`.

Physical Gate 6 result on the target PW3 / KOReader 2026.07.1:
- one real Reader PDF downloaded/opened as the original PDF: **PASS**;
- PDF close/reopen and reading progress preservation: **PASS**;
- one real Reader EPUB downloaded/opened as the original EPUB: **PASS**;
- EPUB reflow/font reading behavior: **PASS**;
- EPUB close/reopen and reading progress preservation: **PASS**;
- offline/local reopen: **PASS**;
- no crash/freeze: **PASS**.

### Gate 6 — PASS

Gate 6 is closed. **Phase H is complete and Phase I / Gate 7 (KOReader sidecar/annotation adapter) is now unblocked.**

## Phase I — KOReader sidecar / annotation adapter

### 0.1.21 implementation ready for Gate 7

KOReader v2026.07.1 source contract revalidated before implementation:
- `DocSettings:open(doc_path)` resolves the active sidecar location rather than requiring this plugin to hardcode `.sdr` paths;
- a valid loaded sidecar exposes `source_candidate`;
- `ReaderAnnotation:onReadSettings()` reads the canonical `annotations` setting;
- `ReaderAnnotation:onSaveSettings()` writes the same `annotations` table;
- current annotation records contain creation/update timestamps, highlight style/color, selected text, note, page/XPointer and start/end positions;
- KOReader's own matching logic uses stable creation/location fields rather than mutable note/text values.

Implemented:
- new `koreader/annotations.lua` adapter reads sidecars through `DocSettings`;
- only actual highlights (`drawer ~= nil`) are candidates; page bookmarks are ignored;
- selected text and note are preserved literally, including newlines, UTF-8, Markdown and `[[wikilinks]]`;
- strong local annotation identity follows the canonical contract:
  `SHA256(reader_document_id + datetime + canonical_locator)`;
- locator serialization is deterministic, sorts nested table keys and normalizes locale-dependent decimal separators for PDF coordinates;
- mutable text, note, color, style, chapter, page labels and calculated page numbers are excluded from identity;
- missing `datetime` uses a degraded first-seen identity; later text edits reuse the stored ID only when the locator has one unambiguous prior match;
- identity collisions are detected and surfaced rather than silently merged;
- local text/note edits are detected by SHA-256 hashes without changing a strong local ID;
- local deletion is detected only from an authoritative, valid sidecar annotation table;
- **missing document file, missing/invalid sidecar, or missing `annotations` key never implies deletion**;
- managed ownership is resolved only by exact `documents.local_path` DB linkage, never by folder/title/filename inference;
- storage now supports local-path document lookup, per-document annotation listing and local deletion tombstones;
- a targeted **Scan current annotations (Gate 7)** action scans only the currently-open managed document, avoiding a whole-library sidecar walk;
- the device diagnostic shows counts, stable local ID, identity quality, locator evidence, exact selected text and exact note for the most recently modified highlight;
- no Reader/Readwise write endpoint is called in Phase I.

Automated coverage:
- note edit and text edit do not change strong identity;
- locator change does change identity;
- delete/recreate with a new creation timestamp gets a new identity;
- PDF locator table key order is canonical;
- page bookmarks are ignored;
- malformed highlights are skipped safely;
- no-sidecar / missing-annotations state is non-authoritative;
- add/edit/delete detection and deletion tombstone behavior;
- degraded identity survives later text edits through unambiguous locator reconciliation;
- unrelated documents cannot be scanned as managed Reader documents;
- missing local managed file never implies annotation deletion;
- Gate 7 diagnostic preserves literal `[[Foucault]]`, hashtags, emoji and line breaks in its on-device evidence;
- run #339 on `c638f6cb...`: **SUCCESS** — full syntax, all unit tests, package/layout and artifact;
- installable inner ZIP verified with `unzip -t`; SHA-256: `b609cf81ea4e3e621e9235d8c4e3156c429c9cbbd3e1d0ef9847639a0596262f`.

Physical Gate 7 result on the target PW3 / KOReader 2026.07.1:
- exact selected text was read from the KOReader sidecar: **PASS**;
- the exact note content actually entered on the Kindle was preserved, including `[[Foucault]]`, blank line and `#pesquisar`: **PASS**;
- the emoji from the suggested fixture was not entered because the Kindle keyboard does not provide emoji input; this is not a persistence failure and is not a Gate 7 blocker;
- locator/page/start/end evidence was populated: **PASS**;
- identity quality was strong: **PASS**;
- the same Local ID survived close/reopen: **PASS**;
- the second scan classified the same annotation as unchanged rather than new: **PASS**;
- no crash/freeze: **PASS**.

### Gate 7 — PASS

Gate 7 is closed. **Phase I is complete and Phase J / Gate 8 (annotation API interoperability spike) is now unblocked.**

## Phase J — annotation API interoperability spike

### 0.1.22 implementation ready for Gate 8

Public API research refreshed on 2026-09-23 before writing mutation code:
- Reader v3 highlight create remains `POST /api/v3/save/` with `parent_id` + exact `content`;
- Reader LIST now explicitly documents highlight `notes`, `highlight_offset` and serialized DOM `highlight_location`;
- **Reader UPDATE now explicitly documents that highlights accept `notes` and `tags`**, superseding the older project assumption that note updates required v2;
- Reader v3 DELETE documents 204 for deleting a highlight child;
- Readwise v2 Highlight LIST/DETAIL expose numeric ID + `external_id`;
- Readwise Export documents Reader-backed user-book `external_id` and highlight `external_id`, giving a candidate deterministic bridge between Reader child IDs and v2 numeric highlight IDs;
- Readwise v2 PATCH supports note/color and DELETE supports numeric highlight deletion.

Canonical research/evidence ledger: `docs/API_INTEROP.md`.

Implemented:
- Reader v3 save/create-highlight/update/delete wrappers with JSON request validation;
- Reader child normalization now includes `highlight_offset` and `highlight_location`;
- new Readwise v2 wrapper for Highlight LIST/DETAIL/PATCH/DELETE plus Export probe;
- staged Gate 8 state machine using only plugin-created disposable data;
- **Step 1** creates a temporary Reader HTML article, waits until the exact test phrase is highlightable, creates one Reader v3 child highlight with note/tag, and records the IDs durably before any cancellable follow-up;
- **Step 2** requires a deterministic v2 mapping (prefer `v2 highlight.external_id == Reader child id`; Export external IDs are a second deterministic path), then PATCHes note/tags through Reader v3 and verifies v3 LIST;
- a parent+text+note-only v2 match is explicitly classified non-deterministic and blocks the spike rather than being accepted;
- **Step 3** PATCHes the same proven numeric v2 highlight note + green color and polls Reader v3 to test cross-API propagation;
- **Step 4** DELETEs through Reader v3, verifies v3 disappearance, allows several seconds for v2 propagation, uses v2 DELETE only if that exact proven disposable numeric ID still exists, then deletes the disposable parent;
- separate recovery cleanup action only touches Gate 8 IDs durably stored by the spike;
- cancellation after parent/highlight creation cannot strand an unknown remote object because each disposable ID is persisted immediately;
- no existing Reader document/highlight is selected or mutated by Gate 8.

Automated coverage:
- Reader v3 mutation request methods, payloads and child locator fields;
- Readwise v2 LIST/DETAIL/PATCH/DELETE/Export request shapes;
- staged create → deterministic mapping → v3 update → v2 update → v3 delete/cleanup state machine;
- ambiguous text/note-only mapping is blocked;
- v2 cleanup fallback only targets a deterministic stored numeric ID;
- partial parent-only state is recoverable;
- all existing Phase A–I tests continue to pass through the latest successful Phase J runs.

Automated/package validation:
- run #371 on `3eeb7efb...`: **SUCCESS** — syntax, all unit tests, package/layout and artifact;
- workflow artifact digest: `sha256:df8d7a86ab921345789aac79b578fc2aca926e4e8ad0c6430b7b7ecb18aa8d49`;
- installable inner ZIP verified with `unzip -t`; SHA-256: `17e5ae9c060407becb1053684f557d3aeae04042c0e790b42b8b5c0518a4db6d`.

Physical Gate 8 result on the target PW3 / KOReader 2026.07.1:
- all four disposable spike steps completed successfully;
- Reader v3 highlight create/parent linkage/note/tag verification passed;
- deterministic Reader-child ↔ Readwise-v2 mapping passed, so no text/note heuristic was needed;
- Reader v3 note/tag update passed;
- Readwise v2 note update response matched and the same Reader v3 child reflected the new note after refresh;
- the v2 response also reported green for the disposable color mutation;
- Reader v3 delete succeeded, the child disappeared from v3, and Readwise v2 no longer exposed it; v2 DELETE cleanup fallback was not needed;
- disposable parent cleanup succeeded.

Product decision from the physical run:
- **highlight color synchronization is dropped from V1**. Reader currently provides no useful multi-color workflow for this project and the target PW3 is monochrome. The Gate 8 green mutation remains interoperability evidence only.

### Gate 8 — PASS

Gate 8 is closed. **Phase J is complete. Phase K text matching is unblocked; Phase L remote creation remains gated behind Gate 9.**








- freeze/back up the known-good 2025.04 state;
- upgrade KOReader only to official `v2026.07.1` using the PW3 `kindlepw2` package;
- run the shorter Gate 4A-1 compatibility regression for Readwise Reader;
- only then install/test Bookshelf `v5.1.4` and validate Reader location Collections + Reader tags metadata;
- Phase G remains blocked until Gate 4A-1 and Gate 4A-2 pass.

The KOReader upgrade does **not** require replaying Gates 0–4 from scratch. Gate 4A-1 deliberately samples only the KOReader-internal contracts that could regress across the version jump.

## Current branch / commit

- Branch: `phase-q/content-refresh-gate15`
- Draft PR: **#18** — keep draft / do not merge until Gate 15 passes physically.
- Base/integrated `main`: `5d7c954d051e491c1b11344057c59df7e2cf9656` (PR #17 merge / Phase P + Gate 14 passed)
- Validated 0.1.46 code/package head: `2fe649de11ed4acb5b3914386e7f98e52f81646b`.
- Validated pre-final handoff HEAD: `56307e13fac7745c9493f24ead1350fcf53c3712`; this final STATUS-only handoff commit follows it.
- Build version for physical Gate 15 Q2: **0.1.46**.
- Database schema: **v2**.
- CI run **#984** on 0.1.46 code/package head: **SUCCESS**.
  - development checks: SUCCESS;
  - full Lua unit suite: SUCCESS;
  - installable ZIP build: SUCCESS;
  - package layout validation: SUCCESS;
  - artifact upload: SUCCESS.
- Validated 0.1.46 artifact:
  - workflow run: `36039445357` / run #984;
  - artifact ID: `10826561188`;
  - artifact name: `readwisereader-koplugin-0dad9ec6c32778662f0b0bf7a11ca99ae2cdade5`;
  - outer artifact SHA-256: `4149d57aa00b6500c6b6ec96a39b85977df2d3109f3cfb5c4785506bb97716cf`;
  - installable inner `readwisereader.koplugin.zip` SHA-256: `9e9b0d61eb2d13911c80d4a937524679d9f11a935a23cafa624ac6e0cacc9c1f`;
  - inner ZIP `unzip -t`: **PASS**, no errors;
  - packaged version: **0.1.46**;
  - `sync/content_refresh_reconcile.lua` present;
  - packaged ZIP contains no `tests/` entries.
- 0.1.44 is superseded and must not be used.
- 0.1.45 remains the Q1-A physical proof build; 0.1.46 is the Q2 validation build.
- Pre-final handoff CI run **#992** on `56307e13fac7745c9493f24ead1350fcf53c3712`: **SUCCESS** across development checks, full Lua suite, package/layout and artifact upload.
- The final STATUS-only commit does not change installable plugin bytes.

## Target environment

- Kindle Paperwhite 3 / 7th generation
- Serial prefix: `G090KB`
- Firmware: `5.16.2.1.1 (4097470002)`
- Jailbreak/KUAL functional
- KOReader historical Gate 0–4 baseline: `2025.04`
- canonical physical V1 baseline from Gate 4A-1 onward: official KOReader `v2026.07.1`, `kindlepw2` package
- Bookshelf `v5.1.4` coexistence: Gate 4A-2 PASSED; current target is Phase Q / Gate 15 content-refresh safety

## Phase A result

- Gate 0: **PASSED** on 2026-09-22.
- Readwise Reader menu appeared.
- Bootstrap popup opened.
- Removing the plugin restored normal KOReader behavior.
- Phase A PR #1 was merged into `main` as `e050f21246706ee25c79f011ba1cfdc389c827bd`.

## Files changed in Phase B

Added/updated on `phase-b/config-auth-gate1`:

- `.github/workflows/test.yml`
- `CHANGELOG.md`
- `README.md`
- `STATUS.md`
- `docs/DEVICE_TESTS.md`
- `readwisereader.koplugin/_meta.lua`
- `readwisereader.koplugin/constants.lua`
- `readwisereader.koplugin/config.lua`
- `readwisereader.koplugin/main.lua`
- `readwisereader.koplugin/api/http.lua`
- `readwisereader.koplugin/api/reader.lua`
- `readwisereader.koplugin/ui/settings.lua`
- `readwisereader.koplugin/tests/run.lua`
- `readwisereader.koplugin/tests/test_config.lua`
- `readwisereader.koplugin/tests/test_http.lua`
- `readwisereader.koplugin/tests/test_reader.lua`
- `scripts/package.sh`


## Phase D result

### D1 — Reader v3 LIST one page

- Added Reader v3 `GET /api/v3/list/` support with `Authorization: Token <TOKEN>`.
- Added deterministic percent-encoded query construction for:
  - `id`;
  - `updatedAfter`;
  - `location`;
  - `category`;
  - repeated `tag`;
  - `limit` (validated 1..100);
  - `pageCursor`;
  - `withHtmlContent`;
  - `withRawSourceUrl`.
- Metadata scans explicitly request neither HTML bodies nor raw-source URLs.
- Added JSON decoding and response-shape validation.
- Documents without a valid Reader ID are rejected as malformed rather than silently accepted.
- The normalized document shape includes the documented metadata needed by later phases.
- No remote-write endpoint was added.

### D2 — complete pagination / safety

- Added sequential cursor pagination with `limit=100`.
- Added repeated-cursor detection.
- Added guard against an empty page that still advertises another cursor.
- Deduplicates records by Reader document ID across pages while recording duplicate count.
- Keeps only IDs in the dedupe set; it does not retain all document bodies/pages in memory.
- Propagates partial scan metrics with failures.
- Added cooperative cancellation checks.
- Added proactive LIST pacing at 3.1 seconds between request starts, slightly below the documented 20 requests/minute ceiling.
- Added bounded 429 recovery:
  - honors numeric `Retry-After` when supplied;
  - otherwise uses bounded 5s/15s fallback delays;
  - retries the same page at most twice;
  - never advances the cursor or dispatches page data before a successful response.
- Sleep/pacing is cancellation-aware.

### D3 — Gate 2 metadata-only UI

- Plugin version advanced to experimental `0.0.4` after the first device scan exposed a UI/cancellation wiring bug.
- Added **Readwise Reader → Scan Reader metadata (Gate 2)**.
- Requires an already-configured token and checks current connectivity only; it does not enable Wi-Fi.
- Runs the scan through `Trapper:wrap()` and then KOReader's `Trapper:dismissableRunInSubprocess`, which is the required KOReader 2025.04 pattern for a visible/dismissable subprocess operation.
- The first 0.0.3 build omitted the outer `Trapper:wrap()`; KOReader therefore fell back to a blocking in-process execution. This is fixed in 0.0.4 and covered by a UI wiring unit test.
- Full-library result reports:
  - top-level Reader documents;
  - API pages;
  - duplicate records ignored;
  - child records ignored;
  - counts by Reader location;
  - counts by category.
- Child records with `parent_id` are counted diagnostically but never treated as top-level reading documents.
- Gate 2 scan does **not**:
  - download or materialize any document;
  - request `html_content`;
  - request `raw_source_url`;
  - write Reader/Readwise state;
  - enqueue annotation/archive operations;
  - toggle Wi-Fi.

### Phase D automated validation

- Run #24 on `5b560b24b6fc908a70a5a587a6a73c7f1d5fec90`: **SUCCESS** — D1 request/query/parser tests.
- Run #25 on `23456463d6de8f9e98d50275e584f7cac2762216`: **SUCCESS** — multi-page pagination, dedupe, repeated cursor, malformed empty-loop, cancellation, 429 propagation.
- Run #26 on `d77cda0244fbda8c1d97eb4b8842d90b86d6d5be`: **SUCCESS** — metadata scanner/UI wiring and package.
- Run #31 on `50fe2ad9bbb362b94eebc7d73bc30816e557965d`: **SUCCESS** — final Phase D code including 21-page pacing simulation, cancellation during pacing, bounded Retry-After recovery, syntax, all unit tests, package and ZIP layout.

## Physical Gate 2 result — attempt 1

Date: 2026-09-22  
Build: `0.0.3` / package based on `813dcbe901e54920389d9a4e7cf9c03fc8fb30cd`  
Result: **PARTIAL PASS — full traversal succeeded; responsiveness/cancellation failed**

Observed on the target PW3 / KOReader 2025.04:
- full metadata scan completed and reached the final report;
- top-level documents: **1329**;
- API pages: **25**;
- duplicate records ignored: **0**;
- child records ignored: **1122**;
- locations:
  - archive: **176**;
  - feed: **40**;
  - later: **51**;
  - new: **1062**;
- categories:
  - article: **843**;
  - epub: **88**;
  - pdf: **31**;
  - podcast: **14**;
  - rss: **40**;
  - video: **313**;
- the final UI explicitly reported: **No documents were downloaded or changed.**
- no cursor-loop, pagination error or final rate-limit failure was observed.

Failure:
- while the scan was running, no progress/cancel widget was visible;
- the KOReader UI appeared blocked/frozen until the scan completed;
- cancellation could therefore not be exercised.

Root cause verified against the pinned KOReader 2025.04 `frontend/ui/trapper.lua`:
- `dismissableRunInSubprocess()` is interactive only when called from a Trapper coroutine;
- when called unwrapped, it deliberately logs a warning and falls back to a blocking in-process run;
- the 0.0.3 Gate 2 menu path was missing the outer `Trapper:wrap()`.

Fix:
- `0.0.4` wraps the online scan as the final menu callback action with `Trapper:wrap()`;
- the subprocess call remains inside that wrapped function;
- added a unit test proving the online path enters `wrap()` before `dismissableRunInSubprocess()` and that the offline path starts no scan;
- run #35 passed.

Gate 2 remains **OPEN** until the 0.0.4 device retest confirms visible progress/cancellation and a successful full scan without the blocking behavior.

## Physical Gate 2 result — attempt 2 / PASS

Date: 2026-09-22  
Build: `0.0.4` / branch `phase-d/reader-metadata-gate2`  
Result: **PASS** on the target PW3 / KOReader 2025.04.

Observed:
- the scan status/cancel surface was visibly rendered on-device; its placement was lower/left rather than centered, which is cosmetic and does not affect Gate 2 criteria;
- tapping the visible scan surface cancelled the scan successfully;
- KOReader remained responsive after cancellation;
- a subsequent full metadata scan completed successfully and displayed the complete summary;
- the scan did not leave KOReader stuck/unresponsive;
- the plugin did not alter Wi-Fi state;
- no Reader document was downloaded, created or changed.

Combined with attempt 1, Gate 2 evidence now covers:
- complete real-account traversal: **25 API pages / 1329 top-level documents**;
- no cursor loop;
- no duplicate API records emitted twice;
- no final rate-limit failure;
- responsive/cancellable device behavior;
- metadata-only/read-only behavior.

Conclusion:
- **Gate 2 PASSED.**
- Phase D was subsequently merged to `main` through PR #4 as `489c0eaf45359fc3025072a9ba4c52297ca134d8`.
- Phase E was unblocked.

## Physical Gate 3 result — attempt 1 / FAIL before article selection

Date: 2026-09-22  
Build: `0.1.0` / package based on `c6484ceb3dd0ca1427623921cc718e3588852e94`  
Result: **FAIL — selector UI did not appear after metadata load**

Observed on the target PW3 / KOReader 2025.04:
- **Download one article (Gate 3)** opened the visible cancellable **Loading Reader articles…** surface;
- the loading surface disappeared normally;
- no article selector appeared afterward;
- KOReader returned to the existing menu and remained usable;
- no article was selected/downloaded, so later Gate 3 rendering/annotation checks were not reached.

Diagnosis:
- the 0.1.0 Gate 3 action kept the originating TouchMenu open with `keep_menu_open=true`;
- after the Trapper subprocess completed, it constructed and showed the candidate `Menu` directly inside the resumed Trapper coroutine;
- KOReader's own menu flow is safer when transitioning to a separate menu after the originating TouchMenu is closed and on a later UI tick;
- errors inside `Trapper:wrap()` are caught/logged, which matches the observed silent-return symptom.

0.1.1 fix:
- allow the originating TouchMenu to close when the Trapper job first yields;
- after the subprocess completes, schedule candidate-selector creation with `UIManager:nextTick()`;
- use KOReader's proven `Menu` + `CenterContainer` pattern;
- close the selector before scheduling the chosen article download;
- wrap selector creation, local installation and automatic opening with user-visible safe fallback messages;
- added `test_article_ui.lua` covering the complete selector transition sequence.

Gate 3 remains **OPEN** pending 0.1.1 physical retest.

## Physical Gate 3 result — attempt 2 / FAIL during selector construction

Date: 2026-09-22  
Build: `0.1.1` / package based on `e4e844427b73af2a36c6b92e0f74a10b170cf15d`  
Result: **FAIL — selector construction raised a caught KOReader UI error**

Observed on the target PW3 / KOReader 2025.04:
- **Loading Reader articles…** appeared;
- the metadata request completed and the loading surface disappeared;
- the plugin then displayed the explicit fallback:
  - **“The Reader article list could not be displayed. Please retry with the updated Gate 3 build.”**
- this proves the flow reached `_showCandidateMenu()` and the protected selector construction/exhibition block raised an error;
- KOReader remained usable;
- no article was selected/downloaded, so later Gate 3 checks were not reached.

Device-log root cause recovered:
- 0.1.0 repeatedly logged `ui/article.lua:44: attempt to call local '_' (a number value)` from `candidateItems`;
- 0.1.1 logged `ReadwiseReader: [UI] article selector failed ... ui/article.lua:47: attempt to call local '_' (a number value)`;
- the selector loop used `for _, candidate in ipairs(...)`, which locally shadowed gettext `_`;
- the failure is triggered specifically when a candidate has no title and the fallback calls `_("Untitled")`.

0.1.2 fix:
- rename the numeric loop index so gettext `_` remains callable;
- index the generated item table explicitly;
- add a UI regression fixture with an untitled Reader candidate and assert the visible fallback is exactly `Untitled`;
- run #50 passed the full suite/package.

Gate 3 remains **OPEN** pending 0.1.2 physical retest.

## Physical Gate 3 result — attempt 3 / PASS

Date: 2026-09-22  
Build: `0.1.2` / branch `phase-e/first-article-gate3`  
Result: **PASS** on the target PW3 / KOReader 2025.04.

User completed the full Gate 3 checklist successfully:
- article candidate selector appeared;
- selected article downloaded and opened automatically;
- article rendered as a normal KOReader document;
- Unicode/non-ASCII text behaved normally;
- font size and margin controls reflowed the content;
- search worked;
- dictionary behavior was validated as requested/configured;
- a local highlight was created successfully;
- a local note was attached successfully;
- the document was closed and reopened;
- reading position/progress persisted;
- highlight and note persisted after reopen;
- KOReader remained usable;
- plugin did not require or perform destructive document replacement.

Conclusion:
- **Gate 3 PASSED.**
- Phase E can be merged to `main`.
- Phase F document sync engine is unblocked.

## Physical Gate 4 result — attempt 1 / FAIL (filter-scope backfill)

Date: 2026-09-22  
Build: `0.1.3` / branch `phase-f/document-sync-gate4`  
Result: **FAIL — incremental sync could advance its watermark while newly-enabled historical filter scope remained undiscovered.**

Observed on the target PW3 / KOReader 2025.04:
- sync completed without crash and reported `Mode: incremental`;
- `Downloaded: 0`, `Already local / unchanged: 0`, `Metadata updated: 0`, `Reader location changes: 0`, `Filtered out: 0`, `Errors: 0`;
- metadata traversal was one page and the UI reported `Incremental watermark updated`;
- enabling all Reader locations afterward still did not backfill historical documents.

Root cause:
- Phase F persisted only the time watermark, not the filter scope associated with that watermark;
- after a successful sync, changing Locations/Types still used `updatedAfter`;
- the first recovery implementation also exposed a Lua-specific bug in `full_scan and nil or fallback`: because the true branch is `nil`, Lua evaluates the fallback and accidentally restores the old watermark;
- `updatedAfter` can only discover records changed since the watermark, so old documents in a newly-enabled location are invisible to that incremental pass.

0.1.4 fix:
- persist a canonical sorted document-filter scope alongside the watermark;
- any scope change forces a safe full backfill using the current filters;
- full/backfill scans now set `updated_after` explicitly to nil rather than using the invalid Lua nil-valued ternary idiom;
- a missing scope marker from the earlier 0.1.3 build also forces a full backfill, recovering the device automatically without deleting the database or files;
- commit the new scope only after parent-process metadata/Collection post-processing succeeds together with the watermark;
- added regression coverage proving that enabling Archive after a prior Inbox-only sync downloads an old Archive article without using `updatedAfter`.

Gate 4 remains **OPEN** pending the 0.1.4 physical retest.

## Physical Gate 4 result — recovery attempts 2–4 / OPEN

Date: 2026-09-22  
Builds: `0.1.5`, `0.1.6`, `0.1.7`  
Result: **OPEN — filter/backfill recovered; 10 persistent retryable materialization failures still block the watermark.**

Observed on the target PW3 / KOReader 2025.04:
- enabling all five documented Reader locations with `article` successfully backfilled the library;
- the full scan saw ~1330 top-level documents and materialized **788 articles**;
- a repeat full scan reused all **788** local files without creating duplicates;
- metadata post-processing errors: **0**;
- Collection post-processing errors: **0**;
- the original 55 item failures were split by 0.1.7 into:
  - **45 permanent/non-retryable skips** (safe to record without blocking the global watermark);
  - **10 retryable item errors**;
- two consecutive 0.1.7 runs reproduced the same **10 retryable errors**, so the watermark correctly remained uncommitted and mode remained `full`.

Interpretation:
- the filter-scope/backfill bug is fixed;
- idempotent reuse of the 788 successfully materialized files is working;
- the remaining blocker is inside per-document materialization, before parent metadata/Collection work;
- permanent per-document content failures no longer strand the entire library;
- the 10 remaining failures need their safe I/O stage identified before changing retry semantics.

0.1.8 diagnostic work:
- installer retryable I/O errors now carry a non-sensitive stage label: `path`, `mkdir`, `open`, `write`, `flush`, `size`, or `rename`;
- sync aggregates stage counts without exposing Reader IDs, titles, paths, or raw OS error text;
- summary adds `Retryable stages: ...`;
- regression tests cover stage classification and aggregation;
- Gate 4 remains **OPEN** until those 10 failures are diagnosed/fixed and a subsequent no-change sync is truly incremental.

0.1.9 physical diagnostic:
- all 10 retryable failures are `open/invalid_name`;
- available storage after sync: **2552.8 MB**, so ENOSPC is ruled out;
- metadata and Collection parent-side writes remain at 0 errors;
- therefore the remaining blocker is path/filename acceptance on the Kindle filesystem for those 10 titles, not storage pressure or post-processing.

0.1.10 fix:
- when the first install attempt fails specifically with `io/open/invalid_name`, retry the same rendered content once using an ASCII-safe fallback filename derived from the Reader ID;
- Reader ID remains the ownership identity and the real Reader title remains in KOReader metadata, so the fallback does not lose title display or create title-based identity;
- other retryable I/O failures are not reclassified or hidden;
- added regression coverage for the invalid-name fallback path.

0.1.10 physical retest:
- **PASS for full/backfill materialization recovery** on the target PW3 / KOReader 2025.04;
- `Downloaded: 10`;
- `Already local / unchanged: 788`;
- `Skipped (not materializable): 45`;
- `Retryable item errors: 0`;
- `Retryable stages: none`;
- `Errors: 0`;
- metadata write errors: 0;
- Collection write errors: 0;
- watermark updated successfully;
- storage available after sync: ~2552.8 MB.

This closes the invalid-filename blocker and proves the full scan can complete cleanly across the current article library. Gate 4 remains OPEN for the remaining behavioral checks: true incremental no-change sync, location move without duplication, title rename without duplication, cancellation, and recovery.

0.1.10 no-change incremental retest:
- `Mode: incremental`;
- `Downloaded: 0`;
- `Errors: 0`;
- metadata pages: 1;
- content pages: 0;
- no duplicate download was observed;
- watermark advanced successfully.

This **functionally passes G4.2 idempotency**, but the report also exposed an efficiency bug: the 45 permanent `content` skips were retried on every incremental run even when Reader returned no changed metadata. That behavior does not duplicate files or corrupt state, but it defeats the intended "process only changes" incremental model.

0.1.11 fix:
- permanent missing-local failures (`content` / `exists`) are no longer pre-seeded into every incremental materialization pass;
- they stay dormant while their Reader revision is unchanged;
- if `updatedAfter` later surfaces a changed remote revision, the item becomes eligible for retry again;
- retryable failures such as I/O remain retryable on later syncs;
- regression tests cover both no-change suppression and retry-after-remote-change.

Gate 4 remains OPEN pending the clean 0.1.11 no-op retest, then location move, title rename, cancellation, and recovery.

### G4.3 Reader location move — PASS

On-device result:
- `Mode: incremental`;
- `Downloaded: 0`;
- `Metadata updated: 1`;
- `Reader location changes: 1`;
- `Errors: 0`;
- metadata write errors: 0;
- Collection write errors: 0;
- watermark advanced successfully;
- user confirmed **no duplicate local file**;
- user confirmed the document **moved to the expected plugin-managed Readwise Collection**.

The prior mixed/failed attempt is not used as Gate evidence because the user had also changed a different organization value from KOReader before realizing this Gate specifically required a Reader-side location change. The clean Reader-side test above is the canonical G4.3 result.

Conclusion:
- **G4.3 PASSED.**
- Reader location -> KOReader Collection projection is physically validated on the target device.
- Gate 4 next step: **G4.4 Reader title rename** on an already-managed article, verifying metadata update on the same local path with no duplicate and preserved sidecar/progress/highlights.


### G4.4 Reader title rename — PASS

Physical result on the target device:
- Reader title changed remotely;
- sync updated the KOReader-visible title;
- no duplicate local document was created;
- reading progress was preserved;
- the local document therefore remained attached to the existing Reader-ID-owned path rather than being rematerialized under the new title.

Conclusion:
- **G4.4 PASSED** for rename identity/metadata/progress preservation.
- Gate 4 next step: **G4.5 cancellation + recovery**.


### G4.5 cancellation + recovery — PASS

Physical result on the target device:
- Full document rescan displayed the cancellable Trapper surface;
- cancellation completed cleanly;
- KOReader remained responsive and did not freeze;
- no corrupted/incomplete replacement file was observed;
- the cancelled run did **not** advance the document watermark;
- a subsequent normal `Sync now` completed successfully with `Errors: 0`.

Conclusion:
- **G4.5 PASSED.**

### Gate 4 final result — PASS

Date: 2026-09-22/23  
Target: PW3 / KOReader 2025.04  
Result: **PASS**

Physical evidence across the Gate 4 recovery builds validates:
- large full/backfill article materialization on the real Reader account;
- stable Reader-ID ownership and no duplicate creation;
- clean incremental no-change sync;
- invalid Kindle filename fallback;
- Reader location move -> KOReader managed Collection without duplicate;
- Reader title rename -> same local file with preserved reading progress;
- cancellable full rescan;
- cancelled run does not advance watermark;
- normal sync recovers after cancellation;
- metadata/Collection parent writes complete without errors in the successful runs;
- plugin does not require destructive replacement of existing managed files.

The later 0.1.11 permanent-skip optimization is covered by automated regression tests; it does not change the validated Reader-ID/location/title/cancellation ownership contracts.

**Gate 4 PASSED. Phase F is unblocked for final CI/PR merge.**

Next mandatory stage after merge: **Phase F.5 / Gate 4A**:
1. freeze/back up the known-good 2025.04 state;
2. upgrade KOReader only to official v2026.07.1 `kindlepw2`;
3. run the shorter Gate 4A-1 compatibility regression (not Gates 0–4 from scratch);
4. install Bookshelf v5.1.4 only after 4A-1 passes;
5. run Gate 4A-2 coexistence, including Reader location Collections and Reader tags -> Bookshelf metadata;
6. only then begin Phase G.


### G4.3 location-move attempt on pre-0.1.11 behavior

A Reader-side location move was detected on-device:
- `Mode: incremental`;
- `Metadata updated: 1`;
- `Reader location changes: 1`;
- `Content refresh deferred safely: 1`;
- metadata/Collection parent write errors: 0.

However the run was **not a clean G4.3 pass**:
- `Skipped (not materializable): 44`;
- `Errors: 1`;
- watermark was not advanced.

The `44` permanent skips are diagnostic evidence that this run still used the pre-0.1.11 retry behavior (0.1.10-equivalent state), because 0.1.11 suppresses unchanged permanent skips from the incremental pending set. The lone unclassified error is consistent with one of the old pre-seeded missing documents failing its per-ID refetch before materialization.

The actual Reader location change itself was observed, but G4.3 must be repeated on 0.1.11+ by moving the same managed article again (preferably back to the previous Reader location) and verifying:
- `Errors: 0`;
- no duplicate/local-path change;
- the path is in the new plugin-managed `Readwise: ...` Collection and removed from the old managed location Collection;
- unrelated user Collections remain untouched.

### Canonical organization/Bookshelf contract added

PLAN, IMPLEMENTATION_SPEC, DEVICE_TESTS and the KOReader/Bookshelf upgrade runbook now define Reader as the source of truth for remote organization projection:
- Reader location -> exactly one plugin-managed `Readwise: Inbox/Later/Shortlist/Feed/Archive` Collection;
- Reader title/author/summary/site -> KOReader custom metadata on the same local path;
- Reader tags -> KOReader/Bookshelf-compatible metadata (target `keywords`), not one Collection per tag;
- later Reader-side changes must reconcile on the next successful incremental sync;
- Bookshelf consumes these Collections/metadata after Gate 4A, without becoming a second source of truth.





## Phase F result — off-device complete, Gate 4 pending

### F1 — document ownership and filters

- Plugin version advanced to experimental `0.1.3`.
- Added configurable download root under `/mnt/us/documents/` with traversal/root-escape validation.
- Added persistent Reader location filters for Inbox (`new`), Later, Shortlist, Feed and Archive.
- Added category filter UI; only `article` is enabled/supported in Phase F. PDF/EPUB/Email/RSS remain later gates.
- Default root remains `/mnt/us/documents/Readwise`.
- Default Phase F locations remain Inbox + Later; Gate 4 instructions deliberately require reviewing filters first so the real account is not bulk-downloaded accidentally.

### F1/F2 — full-first / incremental-later article sync

- First document sync performs a metadata pass and full materialization only for supported articles matching configured filters.
- Subsequent syncs use Reader `updatedAfter` with a canonical scan-start watermark plus a separate 5-minute overlap query bound.
- Reader document ID is the only ownership identity. Title changes never create a second document.
- Missing managed local files can be rematerialized when still eligible.
- Existing managed files are reused; Phase F does not blindly replace remote-changed content.
- Remote title/author/site/location changes update the existing row and KOReader metadata.
- Remote content changes on an existing local document are counted as `content_refresh_deferred`; destructive replacement remains Phase Q.
- Reader location maps idempotently to managed collections:
  - Readwise: Inbox;
  - Readwise: Later;
  - Readwise: Shortlist;
  - Readwise: Feed;
  - Readwise: Archive.
- Collection sync removes a file only from other **plugin-managed** Readwise collections; unrelated user collections are preserved.

### F3 — responsive/cancellable sync and parent-process finalization

- Added top-level:
  - `Sync now (Gate 4)`;
  - `Sync status`;
  - `Full document rescan`.
- First sync and full rescan require explicit confirmation.
- Long work runs through `Trapper:wrap()` + `dismissableRunInSubprocess`.
- Review of KOReader 2025.04 Trapper documentation exposed an important process-boundary rule: the child process must not manipulate UIManager or KOReader settings/cache known by the parent.
- Final architecture therefore keeps network requests, atomic file installation and SQLite work in the child, but defers KOReader custom metadata and Collection writes to the parent.
- The document watermark is proposed by the child but committed only after parent metadata/Collection post-processing succeeds.
- Watermark, overlap query bound, last-success time and full-scan time are committed transactionally with `SyncMeta:setMany()`.
- If post-processing or the atomic sync-meta transaction fails, the summary reports an error and the watermark is not advanced.
- Cancellation keeps already-installed atomic files but does not commit a new watermark.
- The plugin still only inspects connectivity and never toggles Wi-Fi.

### Phase F automated validation

Successful coverage includes:
- first full sync of multiple articles;
- second incremental no-op;
- rename + location change without re-download/path duplication;
- canonical watermark + 5-minute overlap;
- failed scan does not advance watermark;
- deferred watermark path used by subprocess worker;
- parent metadata/collection failure does not advance watermark;
- atomic sync-meta commit;
- download-root path traversal/root escape rejection;
- unrelated Collections preservation + idempotent managed Collection writes;
- UI first-sync confirmation, cancellation, offline preflight and completion summary;
- all previous Phase A-E/storage/API tests;
- package/layout and tests excluded from the installable ZIP.

Gate 4 is still **OPEN** until the real PW3 validates:
- multiple article download;
- second sync unchanged/no duplicates;
- Reader location move;
- Reader title rename;
- cancellation/recovery.

### Planned Phase F.5 / Gate 4A

Research recorded in `docs/KOREADER_UPGRADE.md`:
- upgrade only **after Gate 4** so 2025.04 remains a clean before/after baseline;
- pin official KOReader `v2026.07.1`;
- use `koreader-kindlepw2-v2026.07.1.zip` on this PW3/firmware; `kindlehf` requires firmware >= 5.16.3;
- revalidate Readwise Reader alone before introducing Bookshelf;
- then install/test Bookshelf `v5.1.4` with Cover browser enabled;
- do not begin Phase G until Gate 4A-1 and Gate 4A-2 pass.

## Phase E result

### E1 — first processed Reader article

- Plugin version advanced to experimental `0.1.0`.
- Added **Readwise Reader → Download one article (Gate 3)**.
- Candidate selection happens locally on the Kindle:
  - one metadata-only Reader LIST request;
  - `category=article`;
  - up to 100 candidates;
  - child records are excluded;
  - titles/authors are shown only in the device selector and are not written to fixtures/logs by the plugin.
- Added `Reader:getDocument(id, true, false)` using the documented Reader v3 LIST-by-ID contract.
- The selected article is fetched with `withHtmlContent=true` and `withRawSourceUrl=false`.
- Gate 3 accepts top-level `article` records only and rejects missing/empty processed HTML.

### E1 — safe local materialization

- Added stable filenames in the form `<safe-title>--rw-<stable-id-label>.html`.
- Filename handling covers:
  - NUL/control characters;
  - slash/backslash and common invalid filename characters;
  - traversal-style `..`;
  - whitespace/trailing dots;
  - UTF-8-safe byte truncation;
  - deterministic full-ID-sensitive suffixing.
- Default Gate 3 destination:
  - `/mnt/us/documents/Readwise/Articles/`
- Added a minimal UTF-8 HTML shell around Reader's processed body without inserting a visible local-only title/author into the article body. This avoids creating highlighted text that does not exist in the Reader parent content.
- If Reader returns a complete HTML document, only its body content is embedded in the local shell.
- Added atomic installation:
  - create destination directory;
  - write `.tmp` in the same destination;
  - verify write/size;
  - fsync temporary file;
  - close;
  - atomic rename;
  - fsync directory.
- An existing destination is never overwritten blindly.
- A previously managed local article is reused/opened rather than rematerialized, preserving future sidecar/progress safety.
- Stores local format/path/content hash/fingerprint/materialization state in the Phase C SQLite document repository.
- Temporary/signed raw-source URLs are not requested or persisted.

### E2 — KOReader metadata / open

- Added a KOReader adapter that writes custom metadata through the pinned KOReader 2025.04 `DocSettings:flushCustomMetadata(filepath)` path:
  - title;
  - authors;
  - summary/description;
  - site name/series.
- Broadcasts `InvalidateMetadataCache` and `BookMetadataChanged`.
- Opens the installed article through the pinned KOReader 2025.04 safe path:
  - `SetupShowReader`;
  - `ReaderUI:showReader(filepath)`.
- Network work remains in the cancellable Trapper subprocess; SQLite/materialization/metadata occur in the parent process.
- The plugin still only inspects connectivity and never enables/disables Wi-Fi.

### Phase E automated validation

Run #44: **SUCCESS**
- Lua 5.1 syntax;
- Reader LIST-by-ID / HTML toggle;
- filename tests for ASCII, Portuguese, emoji, separators, traversal, long UTF-8 and deterministic collision resistance;
- minimal HTML/Unicode/body extraction;
- atomic installer success and no-overwrite behavior;
- all pre-existing tests;
- installable package/layout.

Run #45: **SUCCESS**
- first-article candidate filtering;
- materialization/local-state wiring;
- existing managed-file reuse;
- KOReader metadata event wiring;
- safe ReaderUI open wiring;
- all prior Phase A-D/storage tests;
- package/layout.

### Phase E known scope boundaries

- This is deliberately a **single-article Gate 3 path**, not the Phase F library sync engine.
- Candidate selection shows up to 100 top-level article records from one metadata page; full library selection/sync belongs to Phase F.
- Images are not localized/cached yet. Dedicated image behavior is Phase G / Gate 5 and must not be inferred from Gate 3.
- PDF/EPUB raw-source handling is not implemented here; that is Phase H / Gate 6.
- No annotation upload/remote write exists in Phase E.

## Phase C result

### C1 — SQLite/schema/migrations

- Added database path `<DataStorage:getSettingsDir()>/readwisereader.sqlite3`.
- Uses KOReader's `lua-ljsqlite3/init` in production.
- Uses WAL when `Device:canUseWAL()` is true and TRUNCATE otherwise.
- Enables foreign keys and a 5-second busy timeout.
- Added schema version 1 with `PRAGMA user_version`.
- Added transactional forward migration with rollback on failure.
- Future nonzero schema migrations require a `.bak` copy before changing the database.
- Added `documents`, `annotation_links`, `queue` and `sync_meta` tables plus indexes defined by the spec.

### C2 — storage repositories

- Added a documents repository keyed strictly by Reader document ID.
- Remote metadata upserts preserve local path/content state.
- Title/location changes update the same row rather than creating duplicates.
- Temporary `raw_source_url` is intentionally not represented in the durable document repository.
- Added annotation-link storage keeping Reader child IDs and Readwise v2 IDs separate.
- Added durable queue insertion by unique idempotency key.
- Duplicate enqueue returns the existing operation without replacing its payload.
- Added startup-style recovery of stale `in_flight` queue rows back to `pending`.
- Added `sync_meta` get/set/delete storage for future watermarks and scan markers.
- No remote write behavior was added.

### Phase C tests

GitHub Actions run #17 on `803e9ea1a20fdaba8b0649253ff015278a44bc3d`: **SUCCESS**

Validated C1 against real SQLite in CI:
- fresh schema and schema version;
- foreign keys;
- queue uniqueness;
- annotation foreign key;
- transaction rollback;
- migration rollback path;
- package/syntax checks.

GitHub Actions run #18 on `123d1bb9c0e227f56c0acd7a63bca86883af8912`: **SUCCESS**

Validated C2:
- document upsert and stable Reader identity across rename/location change;
- preservation of local document state;
- no persistence of temporary raw-source URL input;
- annotation remote-link preservation across later local scans;
- separate Reader v3 child and Readwise v2 ID fields;
- queue idempotency;
- stale in-flight recovery;
- sync_meta lifecycle;
- package/syntax checks.

## What was implemented

### B1 — local configuration / access token

- Added `LuaSettings`-backed config at `<DataStorage:getSettingsDir()>/readwisereader.lua`.
- Token is intentionally local plaintext because KOReader settings are plaintext; it is not described as encrypted.
- Added password-masked token entry.
- Saved token value is never displayed after saving; menu exposes only configured/not-set state.
- Added replace and clear behavior.
- Blank/whitespace-only token is rejected.
- Token is not copied into SQLite or any other state.
- No token logging was introduced.

### B2 — auth transport / Test connection

- Added a small HTTP transport abstraction using KOReader/LuaSocket patterns:
  - `socket.http`;
  - `ltn12`;
  - KOReader `socketutil` timeout helpers.
- Socket timeout is reset after each attempted request, including thrown errors.
- Request logging contains only HTTP method and URL without query parameters; Authorization headers are never logged.
- Normalized error classes implemented for:
  - offline/network;
  - timeout;
  - TLS;
  - rate limit + numeric `Retry-After` when available;
  - auth;
  - other client errors;
  - server errors;
  - unknown errors.
- Added Reader auth wrapper using:
  - `GET https://readwise.io/api/v2/auth/`;
  - `Authorization: Token <TOKEN>`;
  - expected success `204`.
- Added **Settings → Account → Test connection**.
- User-facing results distinguish valid token, rejected token, offline, timeout, TLS, rate limit, server and unknown errors.
- The plugin checks `NetworkMgr:isOnline()` only. It deliberately does **not** use `runWhenOnline`, `beforeWifiAction` or any Wi-Fi enable/disable flow.

### Packaging/tests

- Version advanced to experimental `0.0.2`.
- Lua unit tests now run in CI.
- Installable ZIP excludes development tests.
- Gate 1 device instructions explicitly document token cleanup in addition to plugin rollback.

## What works off-device

- Config set/get/clear behavior.
- Whitespace trimming and empty-token rejection.
- Auth request construction.
- 204 success handling.
- 401/403 auth failure classification.
- 429 + `Retry-After`.
- timeout/offline/TLS/server classification helpers.
- timeout reset even when the HTTP stack throws.
- token/query redaction from normal request logging.
- deterministic package layout without test files.

## Tests executed and results

### B1 GitHub Actions

Commit: `2b9d5ebb1ab72ad6729f474a20f7b869fc964130`  
Workflow run #8: **SUCCESS**

Validated:
- Lua 5.1 syntax;
- config unit tests;
- packaging;
- required ZIP structure;
- development tests excluded from ZIP.

### B2 GitHub Actions

Commit: `6e776d8c903b846ff5f89b0aa06a4bf88394d7f9`  
Workflow run #9: **SUCCESS**

Validated:
- Lua 5.1 syntax for all plugin/test files;
- config tests;
- HTTP transport/error/redaction tests;
- Reader auth wrapper tests;
- packaging;
- required ZIP structure;
- development tests excluded from ZIP.

### External contracts checked before B2

Against current Readwise documentation:
- authentication uses `Authorization: Token <TOKEN>`;
- validation endpoint is `GET /api/v2/auth/`;
- successful validation returns `204`.

Against KOReader v2025.04 source:
- `LuaSettings` supports local settings + flush/backups;
- password fields use `text_type = "password"`;
- `socketutil` provides timeout/table-sink helpers;
- `NetworkMgr:isOnline()` checks online state, while `runWhenOnline()` can enter Wi-Fi connection flows and is therefore intentionally not used.

## Gates completed

Current authoritative summary:
- Gate 0: **PASSED**.
- Gate 1: **PASSED** — target PW3 / KOReader 2025.04.
- Gate 2: **PASSED** — metadata pagination/cancellation.
- Gate 3: **PASSED** — first article download/open/persistence.
- Gate 4: **PASSED** — document sync on KOReader 2025.04.
- Gate 4A-1: **PASSED** — KOReader v2026.07.1 compatibility.
- Gate 4A-2: **PASSED** — Bookshelf v5.1.4 coexistence/Collections/tags.
- Gate 5: **PASSED** — article images with graceful failure tolerance.
- Gate 6: **PASSED** — original Reader PDF + EPUB.
- Gate 7: **PASSED** — KOReader sidecar annotation identity.
- Gate 8: **PASSED** — Reader v3 ↔ Readwise v2 annotation interoperability.
- Gate 9: **PASSED** — physical PW3 / KOReader v2026.07.1, build 0.1.24.
- Gate 10: **PASSED** — physical PW3 / KOReader v2026.07.1, build 0.1.25.
- Gate 11: **PASSED** — real Readwise Official → Obsidian export/configuration.
- Gate 12: **PASSED** — build 0.1.32 final physical close; note update, conflict, delete-OFF, deliberate delete-ON all validated.
- Gate 13: **PENDING PHYSICAL TEST** — build 0.1.33; O1/O2/O3 implemented and automated.
- Gates 14–15: **NOT YET PASSED**.

Historical early-gate detail:
- B1 off-device implementation: complete.
- B2 off-device implementation: complete.
- **Gate 1: PASSED — 2026-09-22 on target PW3 / KOReader 2025.04.**

## Physical Gate 1 result

Date: 2026-09-22  
Result: **PASS** on the target PW3 / KOReader 2025.04.

Validated:
- token field masked;
- valid token authenticated successfully;
- incorrect/invalid token rejected cleanly;
- offline state detected with Wi-Fi off;
- plugin did not enable Wi-Fi;
- token clear path worked without exposing the credential.

The real token was entered locally through `koreader/settings/readwisereader.lua` over USB after manual Kindle entry proved impractical. No token value was shared or committed.

Next physical gate: **Gate 2**, after Phase C storage and Phase D Reader metadata implementation.

## Bugs / failures found

- Gate 2 device attempt 1 proved the API traversal itself works on the real account (25 pages / 1329 top-level docs) but exposed a real PW3 UI bug: `dismissableRunInSubprocess()` was invoked without `Trapper:wrap()`, so KOReader 2025.04 fell back to blocking in-process execution. Fixed in 0.0.4.
- Runs #33/#34 failed only in the newly-added UI test fixture while its module-cache reset was being corrected; the production fix already passed syntax. Run #35 passed the corrected fixture and full suite.
- Phase D run #23 exposed a test-injection bug: the injected JSON decoder was shaped like KOReader's JSON module but the test supplied a function. Production parsing design was unchanged; decoder injection was simplified and run #24 passed.
- After D3, review against the current Reader contract found that merely handling 429 was insufficient for a full library: unrestricted pagination could itself exceed the documented 20 LIST requests/minute ceiling. Proactive 3.1s request pacing was added before Gate 2.
- Cancellation was initially not forwarded into the per-page pacing call because the copied option was cleared; this was corrected before device testing.
- A synthetic 21-page pacing test then exposed a sub-millisecond floating-point residue loop in the simulated clock. The pacing guard now ignores <1ms residue; final run #31 passed.
- Phase C run #15 failed before tests because the workflow accidentally contained a literal `\\n` inside the apt command; the workflow was corrected.
- Phase C run #16 reached the storage tests and exposed a test-only `lsqlite3` compatibility bug: `get_values()` already returns an array. The shim was corrected; production schema code did not require a change.
- C1 then passed in run #17 and C2 passed in run #18.
- No B1/B2 implementation failure remains in CI.
- A single oversized Git-data connector request for the B2 commit was blocked by the connector before execution. Repository state was verified unchanged, and the exact work was safely retried as smaller Git object operations.
- Direct container Git/network access remains unavailable; repository operations use the GitHub connector. This is a tooling limitation, not a repository blocker.

## Technical decisions made

- Keep `main.lua` small: dependency construction/menu/lifecycle only.
- Keep token configuration in `config.lua`.
- Keep network transport in `api/http.lua`.
- Keep Readwise/Reader auth contract in `api/reader.lua`.
- Use KOReader's password input support rather than custom masking.
- Never prefill the token dialog with the stored secret.
- Do not expose a "show token" action.
- Persist config immediately on save/clear.
- Use `pcall` around low-level HTTP and reset socket timeout afterward.
- Treat all HTTP 2xx as transport success, while `validateToken()` requires the documented 204 specifically.
- Strip query parameters from request log URLs and never log request headers.
- Do not use KOReader network helpers that may toggle/connect Wi-Fi.
- Phase O: local Kindle/KOReader network booleans are advisory only on the target PW3. Remote writes require the worker's read-only Readwise auth probe to succeed after local annotation queueing.
- Phase O backlog discovery is broader than mutation scope: new create-highlight work is discovered across all locally-present managed Reader documents, but note update / optional remote delete remain bounded to the current document for this gate.
- Broad sidecar traversal is failure-isolated: one legacy/malformed sidecar, one malformed annotation, or one per-document queue exception must not abort the whole worker or authorize remote mutation.

## Spec deviations / deliberate canonical changes

No accidental implementation deviation remains open.

A deliberate roadmap/spec change was made on 2026-09-22 at the user's request: KOReader is no longer assumed to remain at 2025.04 through the whole V1. The canonical order now inserts **Phase F.5 / Gate 4A after Gate 4 and before Phase G**, migrating to official KOReader v2026.07.1 and then validating Bookshelf v5.1.4 coexistence. The reason is to establish a clean Phase F before/after compatibility baseline while avoiding implementing image/raw-format/sidecar internals twice. Full procedure is in `docs/KOREADER_UPGRADE.md`.

Gate 8 produced a deliberate canonical API-contract correction on 2026-09-23: physical evidence proved that Reader v3 highlight children accept `notes`/`tags` updates and reflect them in Reader, so normal note updates should prefer Reader v3 rather than treating Readwise v2 as mandatory. The same spike proved deterministic Reader-child ↔ numeric-v2-highlight mapping for later v2-only needs. Highlight-color synchronization is intentionally out of V1.

A pre-existing Phase K branch state had incorrectly grouped remote highlight creation/deduplication into “Gate 9”. This session restored the canonical order rather than accepting that deviation: **Gate 9 is matching-only and read-only remotely; Phase L / Gate 10 owns create + note + deduplication**. The old 0.1.23 upload implementation files remain available for later Phase L work but their menu entry is disabled in 0.1.24.

Gate 13 produced another deliberate canonical correction on 2026-09-23. The earlier preflight design assumed local KOReader/Kindle network state could determine whether remote work was safe to begin. Physical build 0.1.35 disproved that on the target PW3: native Airplane Mode properties were unavailable while KOReader still reported Wi-Fi/connected/online=true with no internet. The spec now requires local annotation queueing first and a **read-only Readwise auth GET inside the worker before any remote write**. This is a safety correction, not a scope expansion; Wi-Fi control remains forbidden.

A 2026-09-24 audit against the Phase L/N handoff found one non-device Phase O gap before retesting: create discovery was still current-document-only even though the canonical spec assigned broader offline/backlog discovery to Phase O. Build 0.1.37 corrected that by scanning only locally-present managed documents, skipping unsafe/non-authoritative sidecars without inferring deletion, and queueing reconciled candidates before the remote probe. This did **not** broaden note/delete mutation scope.

The first physical 0.1.37 run then exposed a robustness gap not represented in CI: the worker returned only the generic safe-failure UI instead of a report. The exact exception source is not inferred from that generic message. 0.1.38 therefore makes the broad backlog boundary exception-contained and adds coarse stage diagnostics. This is a robustness correction to the existing Phase O behavior, not a new feature or scope change.

## Blockers

Immediate blocker: **physical Gate 15 Q2 validation on build 0.1.46 using the already-pending Q1-A article revision**.

Everything possible without the target device is complete:
- Q1-A article safety passed physically;
- Q2 metadata-only acknowledgement implemented;
- reconciliation is bounded to 5 pending HTML articles per Sync;
- exact pending revision equality is required before clearing;
- visible-text comparison uses pure Lua and does not expose document text;
- same-text acknowledgement clears DB pending state only;
- changed/unverified/raced article revisions remain pending;
- raw PDF/EPUB revisions remain pending without replacement downloads;
- automatic content replacement remains hard-disabled;
- deterministic tests cover same-text acknowledge, changed retain, raw retain/no fetch, revision race, remote read failure, and per-Sync bound;
- Sync UI reports every Q2 bucket;
- CI/package/artifact validation passed.

### Bugs / failures found
- pre-Phase-Q deferral was not durable; schema v2 fixed it.
- 0.1.44 DB migration backup misread KOReader `copyFile` nil-success semantics; 0.1.45 fixed it.
- 0.1.44/0.1.45 diagnostic initially used unnecessary native hashing; 0.1.45 removed it.
- no current public Reader UPDATE request can deterministically mutate an existing document body, so the changed-body production branch is covered by deterministic tests + no-replacement invariant and may receive opportunistic physical evidence from a future server reparse.

### Technical decisions / spec deviations
- The earlier initial policy "safe replacement may proceed when no local annotations/progress" is superseded for V1: **no existing local document is auto-replaced**.
- Q2 acknowledges a metadata-only revision by clearing only `content_refresh_pending`; it deliberately does **not** rewrite `materialized_remote_updated_at` for a legacy file, because that field describes the Reader revision that literally produced its bytes.
- Future Reader revisions are still detected from metadata `remote_updated_at`, so an acknowledged legacy row can safely become pending again.
- Raw PDF/EPUB stays deferred until format-specific evidence supports anything less conservative.

## Exact next steps

### Q2 article acknowledgement
1. Install **0.1.46** preserving settings/database/documents/sidecars.
2. Do **not** change the already-pending Q1-A article, title, highlights, notes or reading position before the test.
3. Keep Wi-Fi/internet available.
4. Run ordinary **Sync now exactly once**.
5. Return the full Sync report.
6. Required for the Q1-A fixture:
   - `Refresh pending examined >= 1`;
   - `Refresh articles compared >= 1`;
   - `Metadata-only revisions acknowledged = 1`;
   - `Content refresh pending review = 0` unless unrelated pending rows already exist;
   - `Content pages = 0`;
   - changed/raw/unverified/race/remote-read-error counters = 0 for this fixture.
7. Reopen the article and verify progress/position, highlights and notes remain intact.
8. Do not alter anything; run one unchanged second Sync.
9. Require no repeated acknowledgement/work for the same revision and pending remains 0.

### Q1-B raw formats
10. If an already-managed original PDF and/or EPUB fixture exists locally, use a harmless Reader title-only revision.
11. Sync and require raw revision retained / no replacement download / local sidecar-position-annotations intact.
12. If no suitable raw fixture exists, record that physical coverage limitation explicitly rather than manufacturing a destructive fixture.

13. Gate 15 closes only after article Q2 idempotency and raw-format coverage/scope are resolved.
14. Do **not** begin Phase R / Gate 16 before Gate 15 closes.

## Existing architectural decisions still in force

- KOReader 2025.04 remains the compatibility baseline through Gate 4; official v2026.07.1 becomes the physical V1 baseline only after Gate 4A-1 passes.
- Manual sync only in V1.
- Plugin does not toggle Wi-Fi.
- Reader is the source for library content; Kindle/KOReader is the primary reading surface.
- Reader v3 is used for library and parent-linked highlight creation.
- Production note sync uses deterministic Readwise v2 mapping for remote note truth/update and Reader v3 for child identity plus end-to-end verification/repair. Do not collapse this back to a single-API assumption.
- Read `docs/ANNOTATION_SYNC_LESSONS.md` before future annotation work.
- SQLite will hold documents/annotation links/queue/watermarks.
- LuaSettings holds small user config/token.
- KOReader sidecar `annotations` is the annotation source of truth.
- Never use `My Clippings.txt` as source of truth.
- Preserve note text literally, including `[[wikilinks]]`.
- Deletion propagation is OFF by default.
- Remote archive does not delete local files in V1.
- Never blindly retry highlight creation after an ambiguous timeout.

Never rely on chat history alone for project state.


## Phase K — Gate 9 exact Reader-visible text matching

**Status: COMPLETE — build 0.1.24; GATE 9 PASSED PHYSICALLY on PW3 / KOReader v2026.07.1**

Implemented on branch `phase-k/annotation-sync`:
- visible-text extraction from Reader HTML instead of searching raw markup;
- inline-tag split handling;
- common/numeric HTML entity decoding;
- comments, `script` and `style` excluded from selectable text;
- staged unique matching: exact → NFC → whitespace/NBSP + soft-hyphen normalization → conservative quote/dash equivalence;
- source-span mapping returns the exact Reader-visible substring rather than the normalized search string;
- repeated exact or normalized candidates are blocked as `ambiguous`;
- no-match remains `unmatched`;
- Phase K originally used KOReader's bundled `ffi/utf8proc` for on-device NFC; Gate 13C evidence later superseded that implementation in 0.1.41 with a conservative pure-Lua normalization path because native FFI is incompatible with the queue's recoverable-failure requirement;
- new `sync/text_match_probe.lua`, isolated subprocess worker and `ui/text_match_diagnostics.lua`;
- diagnostic uses only local sidecar read + Reader GET/LIST and explicitly reports `Remote writes: none`;
- the old staged 0.1.23 upload action was removed from `main.lua` menu wiring until Gate 9 passes. Its implementation remains quarantined for later Phase L review, not as a current executable gate action.

Automated validation:
- run #390 on `d073ab250595c5391a00ad2c74d5d015813befb5`: **SUCCESS** — development/syntax checks, full Lua suite, ZIP build/layout and artifact;
- run #393 on `2d093ccc0a28002d00eaffa6cfc4c41b0903879c`: **SUCCESS** — includes Gate 9 diagnostic UI coverage;
- run #394 on build `49cefdd565a22a1c0ed697b8ce954c921ae7c02a`: **SUCCESS** — all development checks, Lua tests, package/layout and artifact upload;
- Gate 9 artifact ID: `10774135389`;
- artifact name: `readwisereader-koplugin-49cefdd565a22a1c0ed697b8ce954c921ae7c02a`;
- artifact digest: `sha256:d3c424b81495ec83069322195d1d56d6babbf37d4b1f34b2b8afa6fd05f84e32`.

### Files changed in this continuation session

Phase J closeout/integration:
- `IMPLEMENTATION_SPEC.md`;
- `STATUS.md`;
- PR #11 merged Phase J into `main` at `9010238a5683f7f4b8f2de21a87b93ad1953e4ea`.

Phase K:
- `CHANGELOG.md`;
- `IMPLEMENTATION_SPEC.md`;
- `STATUS.md`;
- `docs/DEVICE_TESTS.md`;
- `readwisereader.koplugin/constants.lua`;
- `readwisereader.koplugin/_meta.lua`;
- `readwisereader.koplugin/main.lua`;
- `readwisereader.koplugin/sync/text_match.lua`;
- `readwisereader.koplugin/sync/text_match_probe.lua`;
- `readwisereader.koplugin/sync/text_match_probe_worker.lua`;
- `readwisereader.koplugin/ui/text_match_diagnostics.lua`;
- `readwisereader.koplugin/tests/test_text_match.lua`;
- `readwisereader.koplugin/tests/test_text_match_probe.lua`;
- `readwisereader.koplugin/tests/test_text_match_diagnostics_ui.lua`;
- `readwisereader.koplugin/tests/run.lua`.

### Bugs / failures found in this session

- Phase J had physically passed Gate 8 but `main` did not contain that work yet: resolved through PR #11.
- The canonical spec still contained older pre-spike wording that made Readwise v2 mandatory for note updates: corrected from physical Gate 8 evidence.
- The Phase K 0.1.23 branch had conflated Gate 9 matching with Gate 10 remote creation/deduplication and exposed the create action too early: corrected by restoring a read-only Gate 9 and hiding upload from the menu.
- The 0.1.23 matcher searched raw HTML and covered only literal/whitespace cases, so inline tags/entities and required punctuation/Unicode cases were unsafe or incomplete: replaced by the visible-text mapped matcher.
- No CI failure remains open from this session.

### Gates

- Gate 8: **PASSED** physically and merged to `main`.
- Gate 9: **PASSED physically** on the target PW3 / KOReader v2026.07.1. All four documented matching cases passed, every diagnostic remained remotely read-only, and no crash/freeze was observed.
- Gate 10: **PASSED physically** on build 0.1.25 and merged to `main` through PR #13.
- Gate 11: **PREPARED / PENDING USER OBSIDIAN TEST**. No plugin-code change is required for the initial export proof.
- Gate 12 and later: **NOT STARTED in gate terms**.


## Phase L — Gate 10 highlight create + deduplication

**Status: COMPLETE — build 0.1.25; GATE 10 PASSED PHYSICALLY on PW3 / KOReader v2026.07.1**

Implemented on `phase-l/highlight-create-gate10`:
- Reader v3 parent-linked highlight creation from the currently-open managed KOReader document during normal **Sync now**;
- literal note preservation, including `[[wikilinks]]` and multiline text;
- stable queue identity `create_highlight:<local_annotation_id>`;
- durable queue write before POST and durable Reader child ID link immediately after confirmed create;
- stable unique per-annotation `saved_using` marker for ambiguous-outcome reconciliation;
- stale or previously-attempted creates are blocked/reconciled and are never blindly POSTed again;
- reconciliation adopts only one exact Reader child matching both parent and marker; zero/multiple matches remain blocked;
- second sync skips already-linked annotations;
- current-document-only sidecar discovery in this gate build to keep the PW3 responsive and avoid surprise bulk upload from the entire local library;
- Sync summary exposes created/reconciled/already-linked/unmatched/blocked/marker-verified counts.

Automated validation:
- run #400 on `ecdfebc05d7100f7498a7cf2c763315e41db1c6e`: **SUCCESS**;
- run #401 on `b8683bc8af3db6c505562aff818dbea3bdba0b53`: **SUCCESS**;
- run #402 on `d81fccc13e0a70226f46e73cf08b0c13b2e33017`: **SUCCESS**;
- run #403 on build `1a6f16011deae9c177b6ddcd40e875070a1e0b9a`: **SUCCESS** — development checks, full Lua suite, ZIP build/layout and artifact upload;
- Gate 10 artifact ID: `10774724925`;
- artifact name: `readwisereader-koplugin-1a6f16011deae9c177b6ddcd40e875070a1e0b9a`;
- artifact digest: `sha256:175b2d2d5748f3b466fe37bdd61c54daa2f6d3f23f6dcb20a02088cf6282a734`.

Physical Gate 10 **PASSED** on 2026-09-23. Phase M / Gate 11 is now unblocked.

## Phase M — Gate 11 Obsidian end-to-end

**Status: COMPLETE — GATE 11 PASSED in the user's real Obsidian vault; no new Kindle build was required**

Official behavior revalidated from current Readwise documentation on 2026-09-23:
- install/use the **Readwise Official** Obsidian community plugin;
- manual sync command: `Readwise Official: Sync your data now`;
- default highlight export template includes attached notes through `{{ highlight_note }}`;
- new highlights are appended to an existing exported document page;
- export is append-only and does not overwrite user edits;
- later edits to an already-exported highlight/note do not automatically propagate into the existing Obsidian file.

Gate design:
- use the exact Gate 10 Reader highlight/note already proven from KOReader;
- do not change the KOReader plugin or create a new Kindle build;
- preserve the user's real export template/config for the first observation;
- inspect source Markdown, not only rendered appearance;
- require literal `[[Foucault]]` to remain normal Markdown and resolve as an Obsidian internal link;
- document refresh/re-export only as recovery for already-exported/changed items, not as automatic update behavior.

Preparation commit: `48d4bfac6818151bb9b97ab4a8fd2a95dadae3ab`.
CI run #409: **SUCCESS**.
Handoff run #410 on `f8ff416262744facc342c8d843cac65e7f7aeba3`: **SUCCESS**.
Runbook: `docs/OBSIDIAN_GATE11.md`.

Physical/user result: **PASS** — real template exported notes, correct article/highlight appeared, note appeared, literal `[[Foucault]]` and `#pesquisar` were preserved, and the wikilink functioned in Obsidian.

## Phase N — Gate 12 note update / conflict / safe deletion

**Status: PARTIAL PHYSICAL PASS — build 0.1.31; NOTE UPDATE PASSED, CONFLICT + DELETE PENDING**

Implemented on `phase-n/note-update-delete-gate12`:
- shared stable annotation remote marker identity;
- linked Reader-child verification before any PATCH/DELETE;
- note update with post-PATCH GET verification;
- three-way conflict detection using `last_synced_note`; no silent overwrite;
- update-response reconciliation when remote already equals local;
- local text edits blocked from remote mutation;
- delete propagation default OFF;
- explicit confirmed Settings toggle;
- local tombstones retained while deletion is OFF;
- verified remote deletion and durable remote-link clearing while preserving tombstone history;
- current-document-only mutation scope;
- Sync summary counters for notes/conflicts/deletions.

Automated validation:
- run #415: **SUCCESS** — mutation engine/state tests;
- run #416: **SUCCESS** — Sync now/settings integration;
- run #417: **SUCCESS** — destructive opt-in UI coverage.
- run #418 on build `fe97378c76f92f2e4b5c79f0eb1c293d4f864965`: **SUCCESS** — development checks, full Lua suite, ZIP build/layout and artifact upload.
- Gate 12 artifact ID: `10777011478`.
- artifact name: `readwisereader-koplugin-fe97378c76f92f2e4b5c79f0eb1c293d4f864965`.
- artifact digest: `sha256:8f20886e44b96fb46dbc03bd968f536fd9ece7de203d092d446abb797caebd1e`.

Gate 12 physical attempt with build 0.1.26 exposed a real compatibility regression:
- the current document scanned one linked highlight;
- it was recognized as already linked;
- note update stayed at 0;
- mutation conflict/blocked counters stayed 0;
- one annotation remote error was reported;
- root cause: pre-Gate-10 linked highlights used the generic Reader source marker `KOReader Readwise Reader`, while 0.1.26 required only the newer per-annotation source marker.

Fixed in 0.1.27:
- note update accepts the legacy generic source only when durable Reader child ID + original parent ID + `category=highlight` all match;
- exact per-annotation marker remains preferred;
- remote DELETE does **not** accept the legacy generic marker;
- remote identity mismatches are surfaced as safe blocks instead of generic remote errors;
- run #420 on hotfix commit `5c22be3ebae3b95f67ba28fb5472011cb9f1cff8`: **SUCCESS**.

Gate 12 attempt 2 with build 0.1.27 still blocked the note update:
- 2 current-document highlights scanned;
- 2 already linked;
- 0 highlights created;
- 0 notes updated;
- 0 note conflicts;
- 1 annotation mutation blocked safely;
- 0 annotation remote errors;
- Reader note remained unchanged.

The same newly-created linked child had previously reported `Reconciliation markers verified: 0`, proving the Reader `source` marker is not reliable enough to be a mandatory identity component for non-destructive note updates.

Fixed in 0.1.28:
- note update requires the durable Reader child ID + original parent ID + `category=highlight`;
- exact/legacy source markers remain useful evidence when present, but are no longer mandatory for note PATCH;
- previously blocked/conflict items are re-evaluated while the local note still differs from `last_synced_note`, allowing recovery without recreating the highlight;
- DELETE remains unchanged and still requires the exact per-annotation ownership marker;
- run #422 on `209ef6504194f955dd424712474e5d7d90190d9d`: **SUCCESS**.

Physical Gate 12 remains required.

### Gate 12 attempt 3 — build 0.1.28 — FAIL / fixed in 0.1.29
- current-document highlights scanned: 2;
- highlights already linked: 2;
- notes updated: 0;
- note conflicts blocked: 2;
- annotation mutations blocked safely: 0;
- durable linked highlights accepted without marker: 2;
- annotation remote errors: 0.

Conclusion: identity resolution was fixed, but Reader v3 LIST `notes` produced false conflicts for both linked production highlights.

0.1.29 fix:
- resolve the exact Readwise v2 highlight by `external_id == Reader child id`;
- persist the numeric v2 highlight id after deterministic resolution;
- read the current remote note from v2 for three-way conflict detection;
- PATCH that exact v2 highlight when only the local note changed;
- verify returned v2 id/note before advancing the last-synced baseline;
- Reader v3 remains the child id/parent/category identity check;
- deletion behavior is unchanged and still strict.

Code CI #432 on `1f6ee715feaa294984e04b3bb7139fd7836acff0`: **SUCCESS**.
Physical Gate 12 remains required.

### Gate 12 attempt 4 — build 0.1.29 — FAIL / fixed in 0.1.30
- current-document highlights scanned: 2;
- highlights already linked: 2;
- notes updated: 0;
- note conflicts blocked: 2;
- durable linked highlights accepted without marker: 2;
- Readwise v2 annotation pages scanned: 3;
- Readwise v2 mappings resolved: 2;
- Readwise v2 remote-note reads: 2;
- Readwise v2 note updates: 0;
- annotation remote errors: 0.

Conclusion: identity and deterministic v2 mapping were correct; the remaining false conflict was in raw string comparison between the stored baseline and Readwise's normalized note representation.

0.1.30 fix:
- normalize CRLF/CR to LF for comparison;
- trim trailing spaces/tabs per line and surrounding whitespace for comparison only;
- preserve the exact local note as the update payload and persisted post-success baseline;
- conflict detection remains conservative for substantive text differences;
- CI #441 on `b53c40189d94200fdd0cc9677c797174aa778ccd`: **SUCCESS**.

Physical Gate 12 remains open.

### Gate 12 attempt 5 — build 0.1.30 — API success but Reader stale / fixed in 0.1.31
- highlights created: 0;
- notes updated: 1;
- note conflicts blocked: 0;
- durable linked highlights accepted without marker: 2;
- Readwise v2 remote-note reads: 2;
- Readwise v2 note updates: 1;
- annotation remote errors: 0;
- **Reader UI still showed the old note**.

Conclusion: 0.1.30 advanced `last_synced_note` after a successful v2 PATCH response without proving propagation to the Reader v3 child. This made the summary claim success too early.

0.1.31 fix:
- poll the exact linked Reader v3 child after a v2 note PATCH before marking success;
- if v2 has the desired note but Reader v3 is stale, issue a v3 repair PATCH to that same validated child;
- verify the Reader child again after repair;
- only after Reader visibility is proven does `last_synced_note` advance and `Notes updated` increment;
- recover the 0.1.30 premature baseline state when local + baseline + v2 agree but Reader v3 is stale;
- new diagnostics expose Reader verification reads, propagation misses, v3 repair PATCHes and completed repairs;
- functional CI #449 and worker integration CI #450 passed.

Physical Gate 12 remains open.


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
- Readwise v2 annotation pages scanned: **0** (numeric v2 IDs were already persisted);
- Readwise v2 mappings resolved: **0**;
- Readwise v2 remote-note reads: **2**;
- Readwise v2 note updates: **1**;
- Reader note verification reads: **6**;
- Reader propagation misses: **1**;
- Reader v3 repair PATCHes: **2**;
- Reader note repairs completed: **2**;
- annotation remote errors: **0**;
- user visually confirmed the edited note is now correct in Reader.

**Gate 12A note update: PASS.**

Canonical implementation lesson:
- remote conflict/update truth comes from the exact mapped Readwise v2 highlight;
- Reader v3 remains required for child identity and final user-visible verification;
- if v2 is correct but Reader is stale, repair the same validated Reader child via v3 and verify;
- never advance `last_synced_note` or report success before Reader visibility is proven;
- see `docs/ANNOTATION_SYNC_LESSONS.md` for the full reusable contract.

Gate 12 as a whole remains open until conflict and deletion tests pass.


### Gate 12B — conflict handling — PHYSICAL PASS

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
- deletions retained remotely: **0**;
- durable linked highlights accepted without marker: **1**;
- Readwise v2 annotation pages scanned: **3**;
- Readwise v2 mappings resolved: **1**;
- Readwise v2 remote-note reads: **1**;
- Readwise v2 note updates: **0**;
- Reader note verification reads: **0**;
- Reader v3 repair PATCHes: **0**;
- annotation remote errors: **0**;
- user confirmed Reader retained `gate12 REMOTE conflict`;
- user confirmed Kindle retained `gate12 LOCAL conflict`.

**Gate 12B conflict handling: PASS.**

This physically proves that the three-way conflict path blocks mutation before any remote note PATCH and preserves both divergent states.


### Gate 12C — local deletion with propagation OFF — PHYSICAL PASS

Physical result on target PW3 / KOReader v2026.07.1, build 0.1.31.

Fixture setup sync:
- current-document highlights scanned: **2**;
- highlights created: **2**;
- annotation remote errors: **0**.

After deleting only the target highlight locally with propagation OFF:
- current-document highlights scanned: **1**;
- highlights created: **0**;
- highlights already linked: **1**;
- local highlight deletions detected: **1**;
- remote highlight deletions: **0**;
- deletions retained remotely (propagation off): **1**;
- annotation mutations blocked safely: **0**;
- annotation remote errors: **0**;
- user confirmed **both remote highlights still exist** in Reader.

**Gate 12C deletion-OFF: PASS.**

This physically proves the default-safe tombstone behavior: local disappearance is detected and retained durably without destructive remote action while propagation is OFF.

Next: Gate 12D deliberate opt-in deletion of exactly that linked target; control highlight must remain.


### Gate 12D attempt 1 — build 0.1.31 — BLOCKED SAFELY / fixed in 0.1.32

Observed on target PW3 / KOReader v2026.07.1:
- current-document highlights scanned: **1**;
- highlights already linked: **1**;
- local highlight deletions detected: **1**;
- remote highlight deletions: **0**;
- deletion retained remotely (propagation off): **0**;
- annotation mutations blocked safely: **1**;
- annotation remote errors: **0**;
- the target remained in Reader.

Root cause:
- the destructive path still required the exact Reader `source/saved_using` marker;
- physical production Reader data did not expose that marker reliably, even for the legitimate target.

0.1.32 fix:
- destructive identity now requires the exact durable Reader child id;
- the child must belong to the expected parent and be `category=highlight`;
- the exact Readwise v2 highlight must map back with `external_id == Reader child id`;
- zero/ambiguous/mismatched cross-API identity blocks the DELETE;
- after Reader DELETE acknowledgement, the plugin polls the exact Reader child and clears the durable link only after the child is confirmed gone;
- new diagnostics expose cross-API identity verification and post-delete Reader verification;
- code CI #475 on `e6fca05b24f90254087b7111dc1346e255f76a8f`: **SUCCESS**.

Gate 12D remains physically pending on build 0.1.32.


### Gate 12D — deliberate opt-in deletion — PHYSICAL PASS

Physical result on target PW3 / KOReader v2026.07.1, build 0.1.32.

Observed destructive outcome:
- the exact tombstoned target disappeared from Reader;
- the control highlight remained in Reader;
- deletion propagation was turned OFF again immediately after the test.

Follow-up confirmation sync with deletion propagation OFF:
- current-document highlights scanned: **2**;
- highlights created: **0**;
- highlights already linked: **2**;
- local highlight deletions detected: **0**;
- remote highlight deletions: **0**;
- deletions retained remotely: **0**;
- annotation mutations blocked safely: **0**;
- delete cross-API identity verified: **0** (expected on the follow-up because no delete remained pending);
- Reader delete verification reads: **0**;
- Reader deletions verified: **0**;
- delete verification pending: **0**;
- annotation remote errors: **0**;
- user confirmed control remained and setting was OFF.

The destructive-run diagnostic screen itself was not captured after the successful 0.1.32 run, so no unobserved per-run counter is invented here. The end state and clean follow-up prove the tombstone was reconciled: the remote target was gone, control remained, and no local deletion remained pending.

**Gate 12D: PASS. Gate 12: PASS. Phase N: COMPLETE.**


## Phase O — offline queue hardening

**Status: IMPLEMENTED / READY FOR PHYSICAL TEST — build 0.1.33; GATE 13 IS NOT YET PASSED**

Implementation:
- local annotation discovery/queueing occurs before remote document sync;
- ordinary Sync now is allowed offline and performs no network request when the UI reports Wi-Fi unavailable;
- queue payload survives process/reboot boundaries and can be processed without the original in-memory document session;
- never-attempted retryable preflight failures enter `retry_wait` with durable `available_after`;
- due retry-wait rows promote back to pending;
- prior create attempts always reconcile before a later write;
- 429/auth rejections can retry only after full reconciliation finds no remote marker;
- timeout/offline/5xx/unknown POST outcomes remain reconciliation-only and never blind retry;
- stale in-flight creates remain reconciliation-only;
- queue/status diagnostics are visible in Sync now.

Gate 13 physical test remains required.


### Gate 13A attempts on build 0.1.33 — FAIL / fixed in 0.1.34

Physical behavior observed twice on target PW3 / KOReader 2026.07.1 after the user enabled Kindle Airplane Mode:
- sync still ran in incremental/online mode;
- metadata pages were fetched;
- the fresh annotation was queued and immediately processed;
- `Highlights created: 1`;
- `Create queue items processed: 1`;
- `Create queue waiting after sync: 0`.

Conclusion:
- the durable queue itself worked, but the offline/online decision was wrong;
- KOReader 2026.07.1 `NetworkMgr:isOnline()` is not an Airplane Mode check; official source shows it delegates to hostname resolution;
- the Kindle backend also advertises Wi-Fi restore, so user Airplane Mode intent cannot be inferred from generic online state alone.

0.1.34 correction:
- new `platform/network_state.lua`;
- on Kindle, read native `com.lab126.cmd airplaneMode` through liblipclua, with read-only shell fallback;
- if airplaneMode == 1, ordinary Sync now is forced to offline/local-queue mode even if KOReader otherwise reports online;
- otherwise refresh KOReader network state and require Wi-Fi/interface connectivity plus online state;
- the plugin still never turns Wi-Fi on/off;
- automated test reproduces `isOnline=true + airplaneMode=1` and requires `network_available=false`;
- CI #513 on `77192203fe62cd9b9c7adb90d215de690e3f56a2`: **SUCCESS**.

Gate 13A must be repeated on build 0.1.34 before reboot/reconnect testing.

### Gate 13A attempt on build 0.1.34 — FAIL / diagnostic spike required

Physical result on target PW3 / KOReader v2026.07.1:
- native Kindle Airplane Mode was enabled by the user;
- sync still ran in incremental/online mode;
- `Metadata pages: 1`;
- current-document highlights scanned: **3**;
- highlights created: **1**;
- highlights already linked: **2**;
- highlight creates queued durably: **1**;
- create queue items processed: **1**;
- create queue waiting after sync: **0**;
- no annotation block/error was reported.

Therefore the 0.1.34 assumption that `com.lab126.cmd airplaneMode` would reliably expose user Airplane Mode on this target is **not accepted**.

Next gate action is a read-only spike, not another sync:
- build **0.1.35** adds **Readwise Reader → Inspect network state (Gate 13)**;
- it reads native Kindle `airplaneMode`, `wirelessEnable`, `wifid enable`;
- it reads KOReader interface/Wi-Fi/connected/online and cached state;
- it shows the plugin's derived network decision;
- **Remote requests: none**;
- **Remote writes: none**.

Required physical observations:
1. run the diagnostic with native Kindle Airplane Mode **ON**;
2. run it again with Airplane Mode **OFF** and Wi-Fi connected;
3. compare the two screens before changing Gate 13 logic.

CI #526 on diagnostic functional HEAD `2848c239619d70ce8200ad254d18e016fd96d168`: **SUCCESS**.
- Diagnostic build 0.1.35 artifact run #530: **SUCCESS**
- artifact ID: `10786643587`
- artifact name: `readwisereader-koplugin-bb0b5a44498fc6737813d4223e82376b88bc10ba`
- artifact digest: `sha256:e56cb003c69ee59c30c224a3c0b753a3a465bacea549618f712e1a73ea35f44b`


### Gate 13 network-state spike — build 0.1.35 physical result

Target: PW3 / firmware 5.16.2.1.1 / KOReader v2026.07.1.
State under test: user reported **no internet / native Airplane Mode**.

Read-only diagnostic observed:
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
- plugin-derived local `network_available`: **true**;
- plugin reason: `online`;
- diagnostic remote requests: **none**;
- diagnostic remote writes: **none**.

Conclusion:
- none of the attempted native LIPC properties is usable as the authoritative Airplane Mode signal on this physical target;
- KOReader's local Wi-Fi/connected/online state is also insufficient as a write-safety authority on this target;
- this is the exact cause of the 0.1.33/0.1.34 false-online behavior;
- do not add another guessed device property before a new spike proves it.

### 0.1.36 reachability contract

Implementation changed after the physical 0.1.35 evidence:
- current managed sidecar is scanned and any create intent is persisted to SQLite **before any remote request**;
- local KOReader/Kindle network flags are now advisory only and do not authorize remote mutation;
- the cancellable worker performs the existing read-only `GET /api/v2/auth/` as the authoritative remote reachability/auth probe;
- only a successful 204 probe permits create-queue processing, note/delete mutation, or document sync;
- probe failure performs **zero remote writes**, keeps the durable queue waiting, does not advance the document watermark, and reports either `offline / local queue` for network-class failures or `local queue / remote unavailable` for auth/rate-limit/server-class failures;
- no Wi-Fi enable/disable action was added;
- the 0.1.35 local signal diagnostic remains available but is explicitly labeled advisory.

Files changed for 0.1.36:
- `readwisereader.koplugin/sync/worker.lua`;
- `readwisereader.koplugin/ui/sync.lua`;
- `readwisereader.koplugin/ui/network_diagnostics.lua`;
- `readwisereader.koplugin/tests/test_worker.lua`;
- `readwisereader.koplugin/tests/test_sync_ui.lua`;
- `readwisereader.koplugin/tests/test_network_diagnostics_ui.lua`;
- `readwisereader.koplugin/constants.lua`;
- `readwisereader.koplugin/_meta.lua`;
- `CHANGELOG.md`;
- `IMPLEMENTATION_SPEC.md`;
- `PLAN.md`;
- `docs/DEVICE_TESTS.md`;
- `STATUS.md`.

Gate 13 remains **OPEN**. Exact next physical step after CI/artifact:
1. install build 0.1.36;
2. with native Airplane Mode/no internet, create **one new unique** Gate 13 highlight/note;
3. close/reopen the article once;
4. run ordinary Sync now;
5. require: mode `offline / local queue`, remote preflight network failure, `Highlights created: 0`, `Create queue items processed: 0`, queued/waiting >=1, metadata/content pages 0;
6. only after that passes, restart KOReader while the same item remains pending;
7. reconnect Wi-Fi and prove exactly-once delivery + no-op second sync.

Do not advance to Phase P / Gate 14 until this Gate 13 persistence/reconnect sequence passes physically.


## Phase O 0.1.37 session handoff

### Files altered in this session
- `readwisereader.koplugin/sync/annotations.lua`
- `readwisereader.koplugin/sync/annotation_upload.lua`
- `readwisereader.koplugin/sync/annotation_backlog.lua` (new)
- `readwisereader.koplugin/sync/worker.lua`
- `readwisereader.koplugin/storage/documents.lua`
- `readwisereader.koplugin/ui/sync.lua`
- `readwisereader.koplugin/constants.lua`
- `readwisereader.koplugin/_meta.lua`
- `readwisereader.koplugin/tests/test_annotation_backlog.lua` (new)
- `readwisereader.koplugin/tests/test_annotation_sync.lua`
- `readwisereader.koplugin/tests/test_storage_repositories.lua`
- `readwisereader.koplugin/tests/test_sync_ui.lua`
- `readwisereader.koplugin/tests/run.lua`
- `CHANGELOG.md`
- `IMPLEMENTATION_SPEC.md`
- `PLAN.md`
- `docs/ANNOTATION_SYNC_LESSONS.md`
- `docs/DEVICE_TESTS.md`
- `STATUS.md`

### What was implemented
- closed Phase O's outstanding current-document-only create-discovery gap;
- all locally-present Reader-managed documents now participate in local create backlog discovery during manual Sync;
- current document is scanned first;
- remote-only documents are excluded in SQL before sidecar work;
- identity reconciliation and queue preparation share one authoritative sidecar scan;
- individual scan failures do not abort other managed documents and do not imply deletion;
- remote writes remain gated by the read-only Readwise auth probe;
- note/delete remote mutation remains current-document-only.

### Tests executed
- CI run #577 after initial backlog module: **SUCCESS**;
- CI run #584 after storage/identity/backlog regression additions progressed through dev checks/tests/package successfully before later commits superseded it;
- CI run #597 on the complete 0.1.37 code/package head: **SUCCESS**;
- CI run #599 after documentation-only follow-up: **SUCCESS**;
- latest validated artifact downloaded and checked locally:
  - outer SHA matches GitHub artifact digest;
  - inner installable ZIP SHA `771bfec4484f8d0654b717f1ae0029edd87fca8d842668c28c554485db864e53`;
  - `unzip -t` PASS;
  - package contains version 0.1.37;
  - no tests packaged.

### Gates
- Gates 0–12: remain **PASSED**.
- Gate 13: **OPEN / physical test required**.
- Gates 14+: **not started**; blocked by Gate 13.

### Bugs / failures found
- no new code failure remained after automated testing;
- documentation had one contradictory stale Gate 12 rule requiring Reader source marker for destructive delete; corrected to the physically-proven cross-API identity rule;
- implementation audit found Phase O create discovery still current-document-only; corrected in 0.1.37.

### Decisions / deviations
- no product-scope deviation;
- spec clarified to match its earlier Phase L/N handoff: broad discovery applies to create backlog, not to destructive mutation scope;
- no firmware/KOReader update;
- no Wi-Fi control added;
- no credentials/private content committed.

### Blocker
- only remaining blocker is the required physical PW3 Gate 13 sequence above.


## Phase O 0.1.38 physical-failure hardening handoff

### Physical evidence received
- build 0.1.37, Airplane Mode/no internet;
- ordinary Sync now returned only `Document sync failed safely`;
- expected Gate 13A report did not appear;
- Gate 13A therefore **did not pass**;
- no reboot/reconnect was attempted.

### Files altered for 0.1.38
- `readwisereader.koplugin/sync/annotation_backlog.lua`
- `readwisereader.koplugin/sync/worker.lua`
- `readwisereader.koplugin/koreader/annotations.lua`
- `readwisereader.koplugin/sync/annotations.lua`
- `readwisereader.koplugin/ui/sync.lua`
- `readwisereader.koplugin/tests/test_annotation_backlog.lua`
- `readwisereader.koplugin/tests/test_koreader_annotations.lua`
- `readwisereader.koplugin/tests/test_sync_ui.lua`
- `readwisereader.koplugin/tests/test_worker.lua`
- `readwisereader.koplugin/constants.lua`
- `readwisereader.koplugin/_meta.lua`
- `CHANGELOG.md`
- `IMPLEMENTATION_SPEC.md`
- `PLAN.md`
- `docs/DEVICE_TESTS.md`
- `docs/ANNOTATION_SYNC_LESSONS.md`
- `STATUS.md`

### What was implemented
- per-document sidecar-scan exception containment;
- per-document durable-queue preparation exception containment;
- one malformed annotation normalization no longer aborts an otherwise-readable sidecar;
- optimized `listManagedLocal()` failure falls back to `listManaged()`, then current-document lookup;
- backlog report exposes repository source/fallback and isolated exception counters;
- offline annotation status distinguishes partial discovery;
- outer worker safe-failure UI now includes a coarse stage without exposing tokens/payloads;
- all previous pre-write, idempotency, retry and destructive-safety invariants remain in force.

### Tests executed/results
- CI #611 after first exception-containment patch: **SUCCESS**;
- new deterministic tests cover:
  - optimized-query exception → managed-query fallback;
  - both repository queries failing → current-document fallback;
  - one sidecar scan raising while other documents continue;
  - one queue preparation raising while other documents continue;
  - cyclic/malformed annotation locator normalization raising while the rest of the sidecar continues;
  - worker-stage error text;
  - partial offline backlog status classification;
  - new UI diagnostic counters;
- CI #640 on complete 0.1.38 code/docs: **SUCCESS**;
- 0.1.38 artifact downloaded and independently checked:
  - outer digest matched GitHub;
  - inner ZIP SHA-256 `e7fbb5006d228d9ba5166e6265ed42c9464b0f1c9630f4d7dfe5324b5ed0e582`;
  - `unzip -t` PASS;
  - packaged version 0.1.38;
  - tests excluded from installable package.

### Gates
- Gates 0–12 remain **PASSED**.
- Gate 13: **OPEN / 0.1.37 failed safely / 0.1.38 physical retry required**.
- Gate 14+: not started and blocked by Gate 13.

### Bugs/failures
- confirmed: 0.1.37 physical Sync failed before producing a report;
- not proven: the exact Lua exception source, because 0.1.37 intentionally suppressed raw exception details;
- corrected risk boundary: any one historical sidecar/query/queue exception can no longer abort broad create discovery.

### Deviations/decisions
- no firmware or KOReader update;
- no Wi-Fi control;
- no credentials, signed URLs or private payloads committed;
- no destructive scope expansion;
- no gate marked complete without physical evidence.

### Blocker
- one physical action: retry Gate 13A on 0.1.38 using the **same existing fixture** and return the whole report (or the new worker stage if it still fails).


### Gate 13 offline-state persistence observation

New physical evidence on the target PW3:
- user enables native Kindle Airplane Mode;
- enters KOReader / Readwise Reader;
- after leaving the plugin, Wi-Fi is observed ON again, meaning native Airplane Mode is no longer effectively holding the radio offline.

Interpretation:
- do not assume this is a hardware defect;
- do not attribute it to Readwise Reader without isolation;
- current Readwise Reader code does not explicitly invoke KOReader Wi-Fi enable/restore helpers;
- KOReader Kindle networking itself supports Wi-Fi restoration and has separate restore/user-intent state;
- the next physical action is therefore an **offline-state isolation check** before retrying 0.1.38:
  1. disable KOReader Restore Wi-Fi connection on resume;
  2. turn Wi-Fi OFF from KOReader while already inside KOReader;
  3. open/close Readwise Reader without Sync;
  4. check whether Wi-Fi remains OFF.
- if it remains OFF, use that state for Gate 13A;
- if opening Readwise Reader alone turns it ON, stop and investigate eager NetworkMgr/plugin-load interaction before any further Gate 13 sync.


### Gate 13 offline-state isolation — PASS

Physical result on target PW3 / KOReader v2026.07.1:
- KOReader setting **Restore Wi-Fi connection on resume** disabled;
- Wi-Fi turned OFF from KOReader's own Network menu while already inside KOReader;
- Readwise Reader menu opened and closed without running Sync;
- Wi-Fi remained OFF.

Conclusion:
- the previous Airplane Mode instability is attributable to KOReader/Kindle restore-state behavior, not to a proven Readwise Reader explicit Wi-Fi-on action;
- current plugin load does not by itself reproduce Wi-Fi restoration under this controlled state;
- this controlled KOReader-offline state is now the required fixture for Gate 13A on build 0.1.38;
- no new highlight should be created: reuse the exact existing Gate 13 fixture from the failed 0.1.37 attempt.


### Gate 13A controlled-offline physical result — BEHAVIOR PASS / build identity requires confirmation

Physical setup:
- KOReader **Restore Wi-Fi connection on resume** disabled;
- Wi-Fi turned OFF from KOReader's own Network menu;
- controlled offline state remained stable;
- same existing Gate 13 fixture reused.

Observed report:
- Remote preflight: `unknown`;
- Annotation sync: `queued_offline`;
- Managed annotation documents scanned: **801**;
- Authoritative annotation sidecars: **13**;
- Annotation documents skipped safely: **788**;
- Annotation scan errors: **0**;
- Annotation queue errors: **0**;
- Managed-document highlights scanned: **12**;
- Highlights created: **0**;
- Highlights reconciled safely: **0**;
- Highlights already linked: **9**;
- Highlights unmatched/ambiguous: **0**;
- Highlight creates blocked safely: **0**;
- Highlight creates queued durably: **3**;
- Create queue items processed: **0**;
- Create retries deferred: **0**;
- Create auth waits: **0**;
- Create queue waiting after sync: **3**;
- Metadata pages: **0**;
- Content pages: **0**;
- Errors: **0**;
- Notes updated: **0**;
- Remote highlight deletions: **0**.

Behavioral conclusion:
- the controlled offline fixture works;
- no remote create/update/delete or document feed request progressed;
- durable create backlog exists and remains waiting;
- no document watermark work occurred;
- this satisfies the core Gate 13A offline-queue safety behavior.

Build-identity caveat before reboot:
- the photographed report does **not** show the 0.1.38-only diagnostic lines that should appear between scan/queue counters and managed-document highlight count:
  - isolated scan exceptions;
  - isolated normalization exceptions;
  - isolated queue exceptions;
  - repository source/fallback;
  - current annotation document status.
- therefore do not yet claim the physical run as definitively executed by 0.1.38;
- before Gate 13B reboot, reinstall/confirm the validated 0.1.38 package and repeat the same idempotent offline Sync using the same already-queued fixtures;
- this repeat must still create/process zero remote items and must show the 0.1.38 diagnostic fields.


### Gate 13A — PASS on build 0.1.38

Physical target: PW3 / KOReader v2026.07.1.

Controlled offline setup:
- KOReader **Restore Wi-Fi connection on resume** disabled;
- Wi-Fi turned OFF from KOReader's own Network menu;
- same existing Gate 13 fixture reused;
- validated 0.1.38 package reinstalled cleanly.

Observed 0.1.38 report:
- Remote preflight: `unknown`;
- Annotation sync: `queued_offline_partial`;
- Managed annotation documents scanned: **801**;
- Authoritative annotation sidecars: **13**;
- Annotation documents skipped safely: **788**;
- Annotation scan errors: **0**;
- Annotation scan exceptions isolated: **0**;
- Annotation normalize exceptions isolated: **0**;
- Annotation queue errors: **0**;
- Annotation queue exceptions isolated: **0**;
- Annotation repository source: `managed_local`;
- Annotation repository fallback: **no**;
- Current annotation document status: **ok**;
- Managed-document highlights scanned: **12**;
- Highlights created: **0**;
- Highlights reconciled safely: **0**;
- Highlights already linked: **9**;
- Highlights unmatched/ambiguous: **0**;
- Highlight creates blocked safely: **0**;
- Highlight creates queued durably: **3**;
- Create queue items processed: **0**;
- Create retries deferred: **0**;
- Create auth waits: **0**;
- Create queue waiting after sync: **3**;
- Reconciliation markers verified: **0**;
- Notes updated: **0**;
- Note updates reconciled: **0**;
- Note conflicts blocked: **0**;
- Annotation mutations blocked safely: **0**;
- Local highlight deletions detected: **0**;
- Remote highlight deletions: **0**;
- Metadata pages: **0**;
- Content pages: **0**;
- Errors: **0**.

Conclusion:
- **Gate 13A PASSED**.
- build identity is confirmed by the 0.1.38-only diagnostic fields;
- controlled KOReader-offline state is stable;
- local create intents are durably queued before any remote request;
- no remote create/update/delete or document sync progressed while offline;
- no document watermark work occurred;
- partial status is expected because 788 managed rows had no authoritative local sidecar; current target document remained authoritative and `ok`;
- next required proof is queue/local-annotation survival across a KOReader restart while still offline.

### Gate 13B next physical action — reboot persistence only

1. Keep **Restore Wi-Fi connection on resume = OFF**.
2. Keep Wi-Fi **OFF**.
3. Fully restart KOReader.
4. Reopen the same article and confirm the existing Gate 13 highlight + note are still present locally.
5. Without enabling Wi-Fi, run ordinary **Sync now** once.
6. Require:
   - Remote preflight remains offline-class (`unknown` acceptable);
   - Highlights created = **0**;
   - Create queue items processed = **0**;
   - Create queue waiting after sync = **3**;
   - Current annotation document status = `ok`;
   - Metadata pages = **0**;
   - Content pages = **0**.
7. Return the whole report and whether the local highlight/note survived.
8. Do **not** reconnect Wi-Fi until Gate 13B is confirmed.


### Gate 13B reboot-persistence report — queue persistence PASS / local annotation visibility pending user confirmation

Physical target: PW3 / KOReader v2026.07.1 / build 0.1.38.

After a full KOReader restart with Wi-Fi still OFF, ordinary Sync now reported:
- Remote preflight: `unknown`;
- Annotation sync: `queued_offline_partial`;
- Managed annotation documents scanned: **801**;
- Authoritative annotation sidecars: **13**;
- Annotation documents skipped safely: **788**;
- Annotation scan errors: **0**;
- Annotation scan exceptions isolated: **0**;
- Annotation normalize exceptions isolated: **0**;
- Annotation queue errors: **0**;
- Annotation queue exceptions isolated: **0**;
- Annotation repository source: `managed_local`;
- Annotation repository fallback: **no**;
- Current annotation document status: `ok`;
- Managed-document highlights scanned: **12**;
- Highlights created: **0**;
- Highlights reconciled safely: **0**;
- Highlights already linked: **9**;
- Highlights unmatched/ambiguous: **0**;
- Highlight creates blocked safely: **0**;
- Highlight creates queued durably: **3**;
- Create queue items processed: **0**;
- Create retries deferred: **0**;
- Create auth waits: **0**;
- Create queue waiting after sync: **3**;
- Reconciliation markers verified: **0**;
- Notes updated: **0**;
- Remote highlight deletions: **0**;
- Metadata pages: **0**;
- Content pages: **0**;
- Errors: **0**.

Conclusion from the report:
- durable create queue **survived the KOReader process restart**;
- no queued create was processed while offline;
- no remote document work progressed;
- no duplicate/reconciliation side effect occurred;
- current document remained authoritative after restart.

Remaining Gate 13B evidence:
- user confirmation that the same local highlight + note were still visible after restart.

If local annotation visibility is confirmed, Gate 13B passes and the next physical step is Gate 13C:
1. enable Wi-Fi from KOReader outside the plugin;
2. keep the same queue/fixtures; create nothing new;
3. run Sync now once;
4. require exactly the pending creates/reconciliations to drain the queue without duplicates;
5. verify Reader contains exactly one copy of each expected new highlight/note;
6. then run one unchanged second Sync and require created=0, waiting=0.


### Gate 13B — PASS

Physical confirmation received:
- same local Gate 13 highlight survived the KOReader restart;
- same local note survived the KOReader restart;
- durable create queue remained at **3 waiting** after restart;
- offline post-reboot Sync created **0** remote highlights;
- queue processed **0** items;
- metadata/content pages remained **0**;
- current annotation document remained `ok`.

Conclusion:
- **Gate 13B PASSED**;
- local sidecar annotation state and durable queue both survive a KOReader process restart while offline;
- no duplicate or remote side effect occurred during the persistence check.

### Gate 13C — reconnect / exactly-once delivery

Next physical action:
1. keep build **0.1.38** installed;
2. do not create, edit, or delete any Gate 13 fixture;
3. enable Wi-Fi **outside the plugin**, from KOReader's Network menu;
4. confirm KOReader has internet;
5. run ordinary **Sync now** exactly once;
6. require:
   - remote preflight = `passed`;
   - create queue items processed > 0;
   - create queue waiting after sync = **0**;
   - no create remains blocked/ambiguous;
   - each previously-pending local highlight/note appears under the correct original Reader document exactly once;
   - no local highlight/note disappears.
7. return the full report and verify Reader-side copy count.
8. then run **Sync now** a second time with no changes:
   - Highlights created = **0**;
   - Create queue waiting after sync = **0**;
   - exactly one Reader copy of each expected highlight/note;
   - local highlight/note still present.
9. Gate 13 closes only after both reconnect sync and unchanged second sync pass.


### Gate 13C attempt 1 — FAIL SAFE on 0.1.38

After Gate 13A/B passed physically:
- Wi-Fi was re-enabled from KOReader outside Readwise Reader;
- ordinary Sync now was run once;
- UI showed only `Document sync failed safely`;
- no normal report was returned;
- no second Sync was run.

Important interpretation:
- KOReader v2026.07.1 `Trapper:dismissableRunInSubprocess` serializes multiple task returns and returns them to the parent when the child exits normally;
- therefore the generic no-report result is **not** explained by losing the worker's second `err` return;
- the observed UI is consistent with the child ending without usable serialized output (for example hard process exit or serialization failure);
- the exact failure stage is not yet proven;
- because create operations may have side effects before a child dies, **do not retry Sync blindly**.

### 0.1.39 read-only reconnect spike

Implemented before any additional remote mutation:
- `storage/queue.lua` adds read-only create-queue snapshot/status queries that do not promote or mutate queue rows;
- new `sync/reconnect_probe_worker.lua`;
- new `ui/reconnect_diagnostics.lua`;
- menu action: **Inspect reconnect queue (Gate 13)**;
- worker stages are persisted as one non-sensitive local string:
  - `queue_snapshot`;
  - `auth_probe`;
  - `marker_scan`;
  - `parent_reads`;
  - `done`;
- diagnostic runs Reader auth in the same child-process model as Sync;
- diagnostic scans remote Reader highlights for exact KOReader ownership markers for active queue rows;
- diagnostic fetches parent documents and performs matching read-only;
- no POST/PATCH/DELETE;
- displayed queue items contain status/attempt/error/marker/match metadata only — no token, note text, selected text, Reader IDs or signed URLs.

Files changed for 0.1.39:
- `readwisereader.koplugin/storage/queue.lua`;
- `readwisereader.koplugin/sync/reconnect_probe_worker.lua` (new);
- `readwisereader.koplugin/ui/reconnect_diagnostics.lua` (new);
- `readwisereader.koplugin/main.lua`;
- `readwisereader.koplugin/tests/test_storage_repositories.lua`;
- `readwisereader.koplugin/tests/test_reconnect_probe_worker.lua` (new);
- `readwisereader.koplugin/tests/test_reconnect_diagnostics_ui.lua` (new);
- `readwisereader.koplugin/tests/run.lua`;
- `readwisereader.koplugin/constants.lua`;
- `readwisereader.koplugin/_meta.lua`;
- `CHANGELOG.md`;
- `IMPLEMENTATION_SPEC.md`;
- `PLAN.md`;
- `docs/DEVICE_TESTS.md`;
- `STATUS.md`.

Exact next physical action:
1. install 0.1.39 preserving DB/settings/documents/sidecars;
2. keep Wi-Fi ON;
3. do not create/edit/delete Gate 13 fixtures;
4. **do not run Sync now**;
5. run **Readwise Reader → Inspect reconnect queue (Gate 13)** once;
6. return the whole screen;
7. only then decide whether reconnect resumes with reconciliation, a code fix, or another narrower spike.


## Phase O 0.1.39 reconnect-diagnostic handoff

### Physical evidence that triggered this work
- Gate 13A passed offline on 0.1.38.
- Gate 13B passed after full KOReader restart while still offline; queue remained 3 waiting and local highlight/note survived.
- Gate 13C reconnect attempt 1 on 0.1.38 returned only `Document sync failed safely` after Wi-Fi was enabled.
- No second Sync was run, preserving the ambiguous create boundary.

### Files altered
- `readwisereader.koplugin/storage/queue.lua`
- `readwisereader.koplugin/sync/reconnect_probe_worker.lua` (new)
- `readwisereader.koplugin/ui/reconnect_diagnostics.lua` (new)
- `readwisereader.koplugin/main.lua`
- `readwisereader.koplugin/tests/test_storage_repositories.lua`
- `readwisereader.koplugin/tests/test_reconnect_probe_worker.lua` (new)
- `readwisereader.koplugin/tests/test_reconnect_diagnostics_ui.lua` (new)
- `readwisereader.koplugin/tests/run.lua`
- `readwisereader.koplugin/constants.lua`
- `readwisereader.koplugin/_meta.lua`
- `CHANGELOG.md`
- `IMPLEMENTATION_SPEC.md`
- `PLAN.md`
- `docs/DEVICE_TESTS.md`
- `docs/ANNOTATION_SYNC_LESSONS.md`
- `STATUS.md`

### What was implemented
- a remotely read-only Gate 13 reconnect diagnostic;
- local queue snapshot/status counts without promotion/mutation;
- auth GET inside the same subprocess model used by Sync;
- exact remote marker scan for active create items;
- read-only parent GET + text-match readiness;
- recent queue item diagnostics without exposing payload contents or IDs;
- durable coarse stage breadcrumb so a hard child exit still reports the last stage;
- no normal Sync retry and no remote mutation added.

### Tests executed/results
- deterministic queue repository tests verify diagnostics do not mutate state;
- worker helper tests cover durable stage breadcrumbs and safe item summaries;
- UI tests cover successful diagnostics and no-result stage fallback;
- CI run #691: **SUCCESS** for dev checks, full Lua suite, ZIP build/layout, artifact upload;
- downloaded artifact independently verified:
  - outer SHA matches GitHub digest;
  - inner ZIP SHA `90e21fc2dc8da2e66e5edee21a37285172d71890fc2b3dd727460ce196e6ec0a`;
  - `unzip -t` PASS;
  - version 0.1.39;
  - reconnect diagnostic files packaged;
  - tests excluded.

### Gates
- Gates 0–12: **PASSED**.
- Gate 13A: **PASSED**.
- Gate 13B: **PASSED**.
- Gate 13C: **OPEN / mutation frozen pending 0.1.39 read-only diagnostic**.
- Gate 14+: not started; blocked by Gate 13.

### Bugs / decisions
- generic no-report reconnect failure is treated as an ambiguous side-effect boundary, not as proof of no POST;
- inspection of KOReader v2026.07.1 Trapper confirms normal multiple task returns are serialized/restored, so the generic result is not explained by dropping the second return value;
- no blind retry is allowed;
- no firmware/KOReader update;
- no Wi-Fi control added;
- no credentials, notes, selected text, Reader IDs, signed URLs or private response bodies added to diagnostics/logs.

### Blocker / exact next physical action
Install 0.1.39, keep Wi-Fi ON, do not run Sync, and run **Inspect reconnect queue (Gate 13)** exactly once. Return the full diagnostic screen.


### Gate 13C 0.1.39 read-only diagnostic result — HARD EXIT AT PARENT READS

Physical result with Wi-Fi ON:
- user did **not** run ordinary Sync;
- user ran **Inspect reconnect queue (Gate 13)** exactly once;
- UI returned:
  - `Gate 13 diagnostic ended without a report`;
  - `Last durable stage: parent_reads`;
  - `Remote writes: none`.

Interpretation:
- local queue snapshot stage completed;
- child-process auth probe completed far enough to advance beyond `auth_probe`;
- remote exact-marker scan completed far enough to advance beyond `marker_scan`;
- the subprocess ended without a serialized report after entering parent-content reads;
- the 0.1.39 diagnostic itself performed no POST/PATCH/DELETE, so this diagnostic introduced no new remote mutation;
- this sharply narrows the reconnect crash boundary to Reader parent-content fetch and/or subsequent text matching;
- exact queue/marker counts from the 0.1.39 child were lost with the missing serialized report, so mutation remains frozen.

Strong implementation lead:
- the normal reconnect path requests `withHtmlContent=true` for each queued parent and then calls `TextMatch.findExactSubstring`;
- current `TextMatch.visibleText` constructs a full lowercase copy of HTML and appends most text **one byte at a time** into a Lua table; normalized matching can additionally create one mapping table per UTF-8 unit;
- on a memory-constrained PW3 this is a credible hard-exit/OOM risk for a sufficiently large parent, but the 0.1.39 stage alone does **not** prove whether the hard exit occurs during HTTP/JSON parent fetch or during matching.

Next build must split those boundaries read-only before changing production mutation logic.


## Phase O 0.1.40 bounded-parent diagnostic handoff

### Milestone
- Phase O / Gate 13.
- Gate 13A PASS.
- Gate 13B PASS.
- Gate 13C mutation frozen after reconnect hard exit.
- Next physical gate action is the 0.1.40 read-only bounded parent probe.

### Physical evidence
- 0.1.39 diagnostic returned no report.
- durable last stage: `parent_reads`.
- 0.1.39 diagnostic performed no remote writes.
- queue/auth/marker phases were passed before entering parent reads.
- fetch-vs-matcher cause remained ambiguous.

### Files altered for 0.1.40
- `readwisereader.koplugin/api/reader.lua`
- `readwisereader.koplugin/constants.lua`
- `readwisereader.koplugin/sync/reconnect_probe_worker.lua`
- `readwisereader.koplugin/ui/reconnect_diagnostics.lua`
- `readwisereader.koplugin/tests/test_reader.lua`
- `readwisereader.koplugin/tests/test_reconnect_probe_worker.lua`
- `readwisereader.koplugin/tests/test_reconnect_diagnostics_ui.lua`
- `readwisereader.koplugin/_meta.lua`
- `CHANGELOG.md`
- `IMPLEMENTATION_SPEC.md`
- `PLAN.md`
- `docs/DEVICE_TESTS.md`
- `docs/ANNOTATION_SYNC_LESSONS.md`
- `STATUS.md`

### What was implemented
- optional HTTP body cap passed through Reader LIST/getDocument;
- diagnostic cap fixed at 1 MiB;
- parent metadata fetch separated from parent HTML fetch;
- text matching disabled in the diagnostic;
- sanitized partial snapshot persisted after every diagnostic stage;
- parent UI can recover snapshot even when child returns no serialized result;
- no queue mutation/promotion and no remote write.

### Tests
- #720: syntax/dev checks passed; unit test harness failed on missing KOReader-only `json` runtime module;
- scoped test stub added; no production behavior changed by that fix;
- #727: **SUCCESS** — dev checks, all Lua tests, package, layout, artifact;
- artifact independently unzipped/validated;
- installable SHA-256: `683340446507b9084f8190af7a7e4db91cbf49a779fd54218fd9a0637e927ce4`.

### Bugs / decisions
- do not label 0.1.39 as proof of OOM: only parent-phase hard exit is proven;
- current matcher has a credible high-allocation design, but it will not be changed as the asserted root cause until fetch survival is measured;
- no blind retry;
- no firmware/KOReader update;
- no Wi-Fi control;
- no credentials/private payloads committed or displayed.

### Blocker
- physical 0.1.40 **Inspect reconnect queue (Gate 13)** screen.


### Gate 13C 0.1.40 bounded parent-fetch result — PASS

Physical diagnostic result with Wi-Fi ON and **no Sync now**:
- Stage: `done_fetch_only`;
- Auth probe: `passed`;
- Queue pending: **3**;
- Queue retry_wait: **0**;
- Queue in_flight: **0**;
- Queue blocked: **0**;
- Queue succeeded: **11**;
- Marker scan: `passed`;
- Marker scan pages: **11**;
- Active marker matches: **0**;
- Parent probe body cap: **1,048,576 bytes**;
- Parent probe mode: `bounded_fetch_only`;
- active item #1: parent metadata `ok`, parent HTML `ok`, HTML **9,851 bytes**;
- active item #2: parent metadata `ok`, parent HTML `ok`, HTML **27,477 bytes**;
- active item #3: parent metadata `ok`, parent HTML `ok`, HTML **8,564 bytes**;
- Text matching: not run;
- Remote writes: none.

Conclusion:
- **bounded parent fetch passes for all 3 pending items**;
- the 0.1.39 hard exit at `parent_reads` is therefore isolated to the work that 0.1.40 removed: text matching / its normalization path;
- parent response size is not the trigger for these three fixtures;
- active exact-marker matches are currently 0, so the read-only marker scan did not find evidence that the failed 0.1.38 reconnect attempt already created any of these 3 marker-owned remote highlights;
- mutation remains frozen until the matcher boundary is corrected and physically validated read-only.


## Phase O 0.1.41 pure-Lua matcher handoff

### Physical evidence received
- 0.1.40 read-only diagnostic completed normally.
- Queue: pending 3, in_flight 0, blocked 0, succeeded 11.
- Exact marker scan: passed, 11 pages, active marker matches 0.
- Parent #1 metadata/html: ok / ok, 9,851 bytes.
- Parent #2 metadata/html: ok / ok, 27,477 bytes.
- Parent #3 metadata/html: ok / ok, 8,564 bytes.
- Remote writes: none.

### Technical conclusion
- the 0.1.39 hard exit is downstream of parent fetch for these three items;
- remaining boundary is the matcher;
- native `ffi/utf8proc` is a credible unrecoverable-failure mechanism but is **not yet claimed as physically proven root cause**;
- production-safe direction is to avoid native FFI in annotation matching and prefer conservative false negatives.

### Files altered for 0.1.41
- `readwisereader.koplugin/sync/text_match.lua`
- `readwisereader.koplugin/sync/reconnect_probe_worker.lua`
- `readwisereader.koplugin/ui/reconnect_diagnostics.lua`
- `readwisereader.koplugin/tests/test_text_match.lua`
- `readwisereader.koplugin/tests/test_reconnect_diagnostics_ui.lua`
- `readwisereader.koplugin/constants.lua`
- `readwisereader.koplugin/_meta.lua`
- `CHANGELOG.md`
- `IMPLEMENTATION_SPEC.md`
- `PLAN.md`
- `docs/DEVICE_TESTS.md`
- `docs/ANNOTATION_SYNC_LESSONS.md`
- `STATUS.md`

### What was implemented
- native NFC FFI removed from annotation matcher;
- pure-Lua Latin canonical composition retained for supported decomposed accents;
- exact/whitespace/punctuation safety semantics retained;
- granular matcher stage callback added;
- reconnect diagnostic now exercises the real matcher read-only;
- sanitized snapshots and bounded parent HTML remain in place.

### Tests/results
- deterministic matcher tests cover:
  - decomposed/composed Latin normalization;
  - exact → unicode → whitespace stage ordering;
  - invalid/non-Latin byte remains in Lua without native FFI;
  - diagnostic match status/mode rendering;
- CI #758: **SUCCESS**;
- installable ZIP integrity/version/layout independently validated;
- inner ZIP SHA-256: `77b6d0b109a63916e400155259794f7c147ec600d08d9d084bbd5072e0e59252`.

### Gates
- Gates 0–12: PASSED.
- Gate 13A: PASSED.
- Gate 13B: PASSED.
- Gate 13C: OPEN; mutation frozen pending 0.1.41 matcher probe.
- Gate 14+: blocked.

### Blocker
- one physical read-only action: install 0.1.41 and run **Inspect reconnect queue (Gate 13)** once.


## Phase O 0.1.41 matcher-diagnostic handoff

### Physical evidence
- 0.1.40 reconnect diagnostic completed normally.
- queue: pending 3 / retry_wait 0 / in_flight 0 / blocked 0 / succeeded 11.
- active exact-marker matches: 0.
- parent metadata + HTML fetch passed for all 3 pending items.
- HTML sizes: 9,851 / 27,477 / 8,564 bytes.
- remote writes: none.

Conclusion: parent HTTP/JSON/HTML retrieval is not the physical hard-exit boundary for these three fixtures. The remaining boundary is annotation text matching/normalization.

### Files altered for 0.1.41
- `readwisereader.koplugin/sync/text_match.lua`
- `readwisereader.koplugin/sync/reconnect_probe_worker.lua`
- `readwisereader.koplugin/ui/reconnect_diagnostics.lua`
- `readwisereader.koplugin/tests/test_text_match.lua`
- `readwisereader.koplugin/tests/test_reconnect_probe_worker.lua`
- `readwisereader.koplugin/tests/test_reconnect_diagnostics_ui.lua`
- `readwisereader.koplugin/constants.lua`
- `readwisereader.koplugin/_meta.lua`
- `CHANGELOG.md`
- `IMPLEMENTATION_SPEC.md`
- `PLAN.md`
- `docs/DEVICE_TESTS.md`
- `STATUS.md`

### What was implemented
- native utf8proc NFC removed from production annotation matcher;
- pure-Lua conservative NFC composition for explicitly supported Latin combining sequences;
- visible-text extraction changed from byte-by-byte accumulation to contiguous text chunks;
- normalized matching avoids eager per-character source maps;
- source offsets recovered with a second linear scan only after a unique normalized match;
- real matcher executed in the reconnect diagnostic with granular durable stages;
- no remote write or queue mutation added.

### Tests / artifact
- CI #758: **SUCCESS** — dev checks, complete Lua suite, package/layout, artifact.
- outer artifact SHA-256: `83444d6b99770b2d6c843647c0a7ee5e4dae29631bbf93137159ee764a5c8153`.
- installable ZIP SHA-256: `77b6d0b109a63916e400155259794f7c147ec600d08d9d084bbd5072e0e59252`.
- `unzip -t`: PASS.
- packaged version: 0.1.41.
- package contains the optimized matcher and no tests.

### Gates
- Gates 0–12: PASSED.
- Gate 13A: PASSED.
- Gate 13B: PASSED.
- Gate 13C: OPEN / mutation frozen pending 0.1.41 matcher diagnostic.
- Gate 14+: blocked.

### Blocker
- one physical read-only action: run **Inspect reconnect queue (Gate 13)** on 0.1.41 and return the full screen.


### Gate 13C 0.1.41 matcher diagnostic — PASS

Physical target: PW3 / KOReader v2026.07.1 / build 0.1.41.

Read-only reconnect diagnostic completed normally:
- Stage: `done_match_probe`;
- Auth probe: `passed`;
- Queue pending: **3**;
- Queue retry_wait: **0**;
- Queue in_flight: **0**;
- Queue blocked: **0**;
- Queue succeeded: **11**;
- Marker scan: `passed`;
- Marker scan pages: **11**;
- Active marker matches: **0**;
- Parent probe body cap: **1,048,576 bytes**;
- Parent probe mode: `bounded_fetch_and_pure_lua_match`;
- pending item #1:
  - attempts 0;
  - remote_id no;
  - marker_matches 0;
  - parent metadata ok;
  - parent HTML ok;
  - HTML bytes 9,851;
  - match **matched / exact**;
- pending item #2:
  - attempts 0;
  - remote_id no;
  - marker_matches 0;
  - parent metadata ok;
  - parent HTML ok;
  - HTML bytes 27,477;
  - match **matched / whitespace**;
- pending item #3:
  - attempts 0;
  - remote_id no;
  - marker_matches 0;
  - parent metadata ok;
  - parent HTML ok;
  - HTML bytes 8,564;
  - match **matched / whitespace**;
- Remote writes: none.

Conclusion:
- **0.1.41 matcher diagnostic PASSED physically**;
- all three queued selections can be matched safely by the same production matcher used by create processing;
- the previous reconnect hard exit is resolved for these real fixtures;
- all three queue rows remain pristine for first delivery: pending, attempts=0, no remote id, no active exact marker match;
- therefore a controlled Gate 13C mutation retry is now safe: it is not a blind retry of an ambiguous prior POST because physical evidence shows no attempt was durably started and no marker-owned remote child exists.

Next Gate 13C action:
1. keep build 0.1.41 installed and Wi-Fi ON;
2. do not change/create/delete annotations;
3. run ordinary **Sync now exactly once**;
4. return the full report before running any second Sync;
5. then verify in Reader that the three expected pending highlights/notes exist exactly once under their original documents;
6. only after reviewing that first report run the unchanged second Sync to prove idempotency.


### Gate 13C controlled delivery — plugin PASS on 0.1.41 / Reader-side verification pending

Physical target: PW3 / KOReader v2026.07.1 / build 0.1.41.

First controlled ordinary Sync after the matcher fix:
- Metadata updated: **3**;
- Content refresh deferred safely: **3**;
- Metadata documents seen: **3**;
- Metadata pages: **1**;
- Content pages: **0**;
- Remote preflight: `passed`;
- Annotation sync: `scan_partial`;
- Managed annotation documents scanned: **801**;
- Authoritative annotation sidecars: **13**;
- Annotation documents skipped safely: **788**;
- Annotation scan errors: **0**;
- Annotation scan exceptions isolated: **0**;
- Annotation normalize exceptions isolated: **0**;
- Annotation queue errors: **0**;
- Annotation queue exceptions isolated: **0**;
- Annotation repository source: `managed_local`;
- Annotation repository fallback: **no**;
- Current annotation document status: `current_document_not_managed`;
- Managed-document highlights scanned: **12**;
- Highlights created: **3**;
- Highlights reconciled safely: **0**;
- Highlights already linked: **9**;
- Highlights unmatched/ambiguous: **0**;
- Highlight creates blocked safely: **0**;
- Highlight creates queued durably: **3**;
- Create queue items processed: **3**;
- Create retries deferred: **0**;
- Create auth waits: **0**;
- Create queue waiting after sync: **0**;
- Reconciliation markers verified: **0**;
- Notes updated: **0**;
- Note updates reconciled: **0**;
- Note conflicts blocked: **0**;
- Annotation mutations blocked safely: **0**;
- Local highlight deletions detected: **0**;
- Remote highlight deletions: **0**;
- Errors: **0**;
- Metadata write errors: **0**;
- Collection write errors: **0**.

Interpretation:
- **plugin-side first reconnect delivery PASSED**;
- exactly the three pending creates were processed;
- queue drained from 3 waiting to 0;
- no retry, auth wait, blocked create, ambiguity, deletion or error occurred;
- `current_document_not_managed` is acceptable here because Phase O create backlog processing is intentionally global across locally-present managed documents and does not require the currently-open document to be managed;
- `Notes updated: 0` does not imply create-note loss: note content for a new highlight is carried in the create payload; the separate note-update counter only covers PATCH/reconciliation of already-existing Reader highlights.

Remaining evidence before the second Sync:
1. verify in Reader that the three newly-created highlights are under the correct original documents;
2. verify each appears **exactly once**;
3. verify the expected note is attached to the relevant created highlight(s);
4. only after that verification, run one unchanged second Sync to prove idempotency.

Gate 13C is **not yet closed** until Reader-side exactly-one delivery and the unchanged second Sync both pass.


### Gate 13C Reader-side exactly-once verification — PASS

User verified after the first controlled reconnect Sync on build 0.1.41:
- all **3** pending highlights appeared in the correct original Reader documents;
- each appeared **exactly once**;
- expected notes were present on the corresponding highlights;
- no duplicate was observed.

Conclusion:
- first reconnect delivery is physically proven end-to-end;
- plugin-side queue drain and Reader-side exactly-one result agree;
- Gate 13C now has only one remaining requirement: an unchanged second Sync must be a no-op for creates.

Final Gate 13C step:
1. do not create/edit/delete any annotation;
2. keep Wi-Fi ON;
3. run ordinary **Sync now** once more;
4. require:
   - Highlights created = **0**;
   - Create queue items processed = **0**;
   - Create queue waiting after sync = **0**;
   - Highlights unmatched/ambiguous = **0**;
   - no blocked create/retry/auth wait;
   - errors = **0**;
   - Reader still contains exactly one copy of each of the 3 Gate 13 highlights/notes.
5. return the full report.
6. If this passes, Gate 13 / Phase O can be closed and the branch may advance toward merge before Phase P / Gate 14.


### Gate 13C final unchanged Sync — PASS

User confirmed the required unchanged second Sync on build 0.1.41 completed cleanly after the first exactly-once reconnect delivery:
- no new annotation changes were made before the second Sync;
- Highlights created: **0**;
- Create queue items processed: **0**;
- Create queue waiting after sync: **0**;
- Highlights unmatched/ambiguous: **0**;
- no create retry/auth wait/blocker remained;
- Errors: **0**;
- Reader still contained exactly one copy of each of the three Gate 13 highlights/notes.

### Gate 13 — PASS / Phase O complete

Physical end-to-end proof now covers:
1. stable controlled offline state without plugin Wi-Fi control;
2. local highlight/note persisted into durable queue before remote access;
3. offline Sync performed no remote mutation and no document-watermark advance;
4. queue + sidecar highlight/note survived full KOReader restart;
5. reconnect matcher path was hardened and physically validated on the target PW3;
6. first reconnect delivered exactly the three pending highlights/notes to the correct original Reader documents;
7. Reader verification found exactly one copy of each with expected note content;
8. unchanged second Sync created zero new highlights and left queue waiting at zero.

Conclusion:
- **Gate 13 PASSED**;
- **Phase O COMPLETE**;
- no known Phase O blocker remains;
- PR #16 can be moved out of draft and merged through the normal repository flow;
- next canonical work is **Phase P / Gate 14 — Finished → Archive exactly once while local file/sidecar/progress/annotations remain intact**.


## Phase P 0.1.42 finished-signal spike handoff

### Milestone
- Phase O merged to main at `b7c8977b89cf572bec1280e3490a033341af4375`.
- Phase P / Gate 14 started.
- Archive mutation intentionally not implemented before finished-signal proof.

### Technical evidence
Official KOReader v2026.07.1 source:
- BookStatusWidget Finished argument = `complete`;
- ReaderStatus `markBook()` mutates `summary.status` to `complete` and updates `summary.modified`;
- BookList considers `complete` the Finished status and traces status to `doc_settings.summary.status`.

This is strong source evidence, but the canonical spec requires an experimental target-device spike before production dependence.

### Files altered
- `readwisereader.koplugin/koreader/status.lua` (new)
- `readwisereader.koplugin/ui/finished_diagnostics.lua` (new)
- `readwisereader.koplugin/main.lua`
- `readwisereader.koplugin/tests/test_koreader_status.lua` (new)
- `readwisereader.koplugin/tests/test_finished_diagnostics_ui.lua` (new)
- `readwisereader.koplugin/tests/run.lua`
- `readwisereader.koplugin/constants.lua`
- `readwisereader.koplugin/_meta.lua`
- `CHANGELOG.md`
- `IMPLEMENTATION_SPEC.md`
- `PLAN.md`
- `docs/DEVICE_TESTS.md`
- `STATUS.md`

### What was implemented
- local-only KOReader status adapter;
- safe sidecar open/read;
- known status classification (`reading`, `abandoned`, `complete`);
- candidate finished predicate only for diagnostics;
- current managed-document guard;
- persisted/runtime/BookList comparison UI;
- no network and no writes.

### Gates
- Gates 0–13: **PASSED**.
- Gate 14: **OPEN — source candidate identified, physical signal spike required**.
- Gates 15–16 and V1 acceptance: blocked.

### Blocker
- physical before/after Finished diagnostic on the PW3.


### 0.1.42 automated/package validation

- PR #17 remains draft.
- CI #810: FAIL at dev-check due solely to an unterminated `_meta.lua` long string introduced while changing the experimental description.
- Fix commit: `84afff1d5fec69dcf42e55554aa90af778d58e05`.
- CI #812: PASS across development checks, complete Lua suite, package build/layout and artifact upload.
- artifact outer digest matched after download.
- inner installable ZIP digest: `df37908276eb9938a87d3d401a01bbe607bf295cc477288b25e48bbddbfd2a7a`.
- installable ZIP integrity: PASS.
- version inside package: 0.1.42.
- no test files packaged.

Physical blocker remains the before/after Finished signal spike; no later Phase P mutation is authorized yet.


### Remaining V1 path after Gate 14

Numbered gates:
- Gates 0–14: **15 of 17 numbered gates passed**.
- Gate 15: current Phase Q / content-refresh safety.
- Gate 16: release-candidate hardening.
- After Gate 16: execute the complete V1 acceptance script and tag `v1.0.0` only if it passes.

The main remaining technical uncertainty is Gate 15 raw-format coverage. Article Q1-A passed physically and 0.1.46 Q2 is ready for exact metadata-only acknowledgement testing; replacement remains disabled.

## Phase P 0.1.43 archive implementation handoff

### Physical P0 evidence
Before Finished:
- managed Reader document: yes;
- local file: yes;
- Reader location local DB: new;
- sidecar: yes;
- sidecar summary.status: reading;
- sidecar summary.modified: 2026-09-23;
- sidecar percent_finished: 0.1538;
- BookList status: reading;
- runtime summary.status: reading;
- candidate: no;
- remote requests/writes: none;
- local writes: none.

After KOReader Book status → Finished:
- Reader location local DB still new;
- sidecar still present;
- sidecar summary.status: **complete**;
- sidecar summary.modified: 2026-09-24;
- sidecar percent_finished: **0.1538**;
- BookList status: **complete**;
- runtime summary.status: **complete**;
- candidate: yes;
- remote requests/writes: none;
- local writes: none.

Conclusion: Gate 14 P0 **PASS**. `summary.status == "complete"` is canonical; reading percentage is not.

### Files altered for P1 / 0.1.43
- `readwisereader.koplugin/sync/archive.lua` (new)
- `readwisereader.koplugin/koreader/status.lua`
- `readwisereader.koplugin/storage/queue.lua`
- `readwisereader.koplugin/storage/documents.lua`
- `readwisereader.koplugin/sync/worker.lua`
- `readwisereader.koplugin/config.lua`
- `readwisereader.koplugin/ui/settings.lua`
- `readwisereader.koplugin/ui/sync.lua`
- `readwisereader.koplugin/main.lua` (diagnostic remains available)
- `readwisereader.koplugin/tests/test_archive.lua` (new)
- `readwisereader.koplugin/tests/test_config.lua`
- `readwisereader.koplugin/tests/test_settings_ui.lua`
- `readwisereader.koplugin/tests/test_storage_repositories.lua`
- `readwisereader.koplugin/tests/test_sync_ui.lua`
- `readwisereader.koplugin/tests/test_koreader_status.lua`
- `readwisereader.koplugin/tests/test_finished_diagnostics_ui.lua`
- `readwisereader.koplugin/tests/run.lua`
- `readwisereader.koplugin/constants.lua`
- `readwisereader.koplugin/_meta.lua`
- `CHANGELOG.md`
- `IMPLEMENTATION_SPEC.md`
- `PLAN.md`
- `docs/DEVICE_TESTS.md`
- `STATUS.md`

### What was implemented
- default-ON archive-finished user setting;
- canonical local Finished discovery;
- durable archive queue operation using stable Reader document identity;
- safe cancellation when local Finished is reverted before confirmed archive;
- unknown sidecar status never treated as unfinished;
- Reader GET reconciliation before mutation/retry;
- individual idempotent archive PATCH;
- ambiguous timeout/server outcome is durable and GET-reconciled before retry;
- stale in-flight generic recovery is safe because archive PATCH is idempotent and prechecked;
- confirmed remote archive persists local DB location first, then closes queue item;
- successful archive feeds parent-side Collection projection to `Readwise: Archive`;
- local file missing blocks remote archive instead of violating local-keep contract;
- no local file/sidecar/content mutation in archive module.

### Tests / validation
- deterministic archive tests:
  - first Finished archive;
  - unchanged second pass no duplicate PATCH;
  - already-remote archive adoption;
  - timeout where remote PATCH actually succeeded → next GET reconciles, no second PATCH;
  - local Finished reverted before mutation → safe cancel;
  - missing local file → safe block/no PATCH.
- config/UI/storage/sync-report tests updated.
- CI #865: **SUCCESS**.
- artifact outer SHA-256: `694cd120f8de707c4e38403806c993553ed0efc49526e7cdba8fe8a1a083f0e4`.
- installable ZIP SHA-256: `479358fa86d85dcde16e22aee2e1195521366a205e14f3708c754a16299bd067`.
- ZIP integrity/version/layout: PASS.

### Bugs / failures found
- 0.1.42 preparation previously had one transient unterminated `_meta.lua` long-string failure; CI caught it before packaging and it was fixed before P0 testing.
- During P1 review, success-persistence ordering was hardened: local document-row location is written before queue success so a process death cannot strand a succeeded queue row with stale local location.
- Unknown/missing KOReader summary status was hardened to safe skip/block, not interpreted as `reading`.

### Gates
- Gates 0–13: PASSED.
- Gate 14 P0: **PASSED physically**.
- Gate 14 P1: **IMPLEMENTED / PHYSICAL TEST PENDING**.
- Gate 15+: blocked.

### Blocker
- one physical first Sync + Reader/local preservation verification on 0.1.43; then one unchanged second Sync.


### Gate 14 P1 first archive Sync — REMOTE PASS / local preservation check pending

Physical target: PW3 / KOReader v2026.07.1 / build 0.1.43.

User ran the required first ordinary Sync with the previously-proven managed document still marked Finished.

Visible Sync-report evidence:
- Errors: **0**;
- Remote preflight: **passed**;
- Metadata documents seen: **4**;
- Metadata pages: **1**;
- Content pages: **0**;
- Duplicate API records ignored: **0**;
- Managed annotation documents scanned: **801**;
- Authoritative annotation sidecars: **13**;
- Annotation scan errors: **0**;
- Annotation queue errors: **0**;
- Managed-document highlights scanned: **12**;
- Highlights created: **0**;
- Highlights already linked: **12**;
- Highlights unmatched/ambiguous: **0**;
- Create queue items processed: **0**;
- Create queue waiting after sync: **0**;
- Notes updated: **0**;
- annotation remote errors: **0**.

Reader-side verification:
- the target Finished document **moved to Archive successfully**.

Conclusion so far:
- first Gate 14 remote archive effect **PASSED**;
- no annotation duplicate/error regression is visible;
- the photographed report crop does not include the later archive-specific counters, so do not infer their exact numeric values from this image;
- Gate 14 is still open until local preservation is checked and the unchanged second Sync proves idempotency.

Required local preservation check before second Sync:
1. confirm the same archived document still exists locally and opens;
2. confirm its reading position/progress is still preserved;
3. confirm its existing highlights are still present;
4. confirm its existing notes are still present;
5. preferably run **Inspect finished status (Gate 14)** on that document and confirm sidecar is still present / status remains complete.

Only after all of the above pass:
- run one unchanged second **Sync now**;
- require no repeated archive mutation and archive queue waiting = 0.


### Gate 14 P1 local preservation after first archive — PASS

After the first 0.1.43 archive Sync moved the target Finished document to Reader Archive, the user verified on the Kindle:
- the same local document still exists;
- the document still opens normally;
- reading position/progress is preserved;
- existing highlights are preserved;
- existing notes are preserved.

Combined with the first-Sync Reader verification:
- remote archive effect: PASS;
- local keep contract: PASS;
- annotation/progress preservation: PASS.

No destructive local side effect was observed.

Gate 14 now has only one remaining physical requirement: the unchanged second Sync must prove idempotency.

Final Gate 14 action:
1. make no document/annotation/status changes;
2. keep Wi-Fi ON;
3. run ordinary **Sync now** once;
4. return the full Sync report;
5. require:
   - Reader documents archived = **0**;
   - Archive queue items processed = **0**;
   - Archive queue waiting after sync = **0**;
   - Archive remote errors = **0**;
   - no new annotation create/update/delete;
   - Reader document remains in Archive;
   - local file/sidecar/progress/highlights/notes remain intact.
6. If this passes, Gate 14 / Phase P is complete and PR #17 can move toward merge before Phase Q / Gate 15.


### Gate 14 final unchanged second Sync — PASS

User confirmed the unchanged second Sync after the first successful Finished → Archive transition passed the required idempotency checks.

Visible second-Sync evidence:
- Errors: **0**;
- Remote preflight: **passed**;
- Metadata pages: **1**;
- Content pages: **0**;
- Duplicate API records ignored: **0**;
- Annotation sync: `scan_partial`;
- Managed annotation documents scanned: **802**;
- Authoritative annotation sidecars: **13**;
- Annotation documents skipped safely: **789**;
- annotation scan/normalize/queue exceptions: **0**;
- Current annotation document status: **ok**;
- Managed-document highlights scanned: **12**;
- Highlights created: **0**;
- Highlights already linked: **12**;
- Highlights unmatched/ambiguous: **0**;
- Create queue items processed: **0**;
- Create queue waiting after sync: **0**;
- Notes updated: **0**;
- remote highlight deletions: **0**;
- annotation remote errors: **0**.

User confirmation for the Gate 14-specific second-sync criteria:
- no repeated archive mutation;
- archive queue remained empty;
- Reader document remained in Archive;
- local document still existed/opened;
- sidecar/progress/highlights/notes remained intact.

### Gate 14 — PASS / Phase P complete

Physical proof covers:
1. canonical KOReader Finished signal `summary.status == "complete"`;
2. durable Finished archive intent;
3. Reader archive transition;
4. preservation of local file, sidecar, progress, highlights and notes;
5. unchanged second Sync idempotency with no repeated archive effect.

Conclusion:
- **Gate 14 PASSED**;
- **Phase P COMPLETE**;
- PR #17 can be moved out of draft and merged through the normal repository flow;
- next canonical work is **Phase Q / Gate 15 — content refresh safety**.


## Phase Q 0.1.44 content-refresh safety handoff

### Milestone
- Phase P / Gate 14: **PASSED and merged** at `5d7c954d051e491c1b11344057c59df7e2cf9656`.
- Phase Q / Gate 15 Q1: **IMPLEMENTED / PHYSICAL TEST PENDING**.
- Phase Q Q2 and Phase R are blocked.

### Files altered
- `readwisereader.koplugin/storage/migrations.lua`
- `readwisereader.koplugin/storage/documents.lua`
- `readwisereader.koplugin/sync/first_article.lua`
- `readwisereader.koplugin/sync/documents.lua`
- `readwisereader.koplugin/sync/worker.lua`
- `readwisereader.koplugin/sync/content_refresh.lua` (new)
- `readwisereader.koplugin/sync/content_refresh_probe_worker.lua` (new)
- `readwisereader.koplugin/koreader/status.lua`
- `readwisereader.koplugin/ui/content_refresh_diagnostics.lua` (new)
- `readwisereader.koplugin/ui/sync.lua`
- `readwisereader.koplugin/main.lua`
- `readwisereader.koplugin/constants.lua`
- `readwisereader.koplugin/_meta.lua`
- `readwisereader.koplugin/tests/test_content_refresh.lua` (new)
- `readwisereader.koplugin/tests/test_content_refresh_probe_worker.lua` (new)
- `readwisereader.koplugin/tests/test_content_refresh_diagnostics_ui.lua` (new)
- `readwisereader.koplugin/tests/test_document_sync.lua`
- `readwisereader.koplugin/tests/test_first_article.lua`
- `readwisereader.koplugin/tests/test_storage_db.lua`
- `readwisereader.koplugin/tests/test_storage_repositories.lua`
- `readwisereader.koplugin/tests/test_koreader_status.lua`
- `readwisereader.koplugin/tests/test_sync_ui.lua`
- `readwisereader.koplugin/tests/run.lua`
- `CHANGELOG.md`
- `IMPLEMENTATION_SPEC.md`
- `PLAN.md`
- `docs/DEVICE_TESTS.md`
- `STATUS.md`

### What was implemented
- safe schema v2 migration and migration test;
- materialized-remote-revision baseline for new local downloads;
- durable refresh-pending revision state for existing local documents;
- no-op Sync persistence of pending state;
- hard no-replacement invariant for existing local bytes;
- KOReader reading-state risk detection;
- bounded, read-only article visible-text comparison;
- raw PDF/EPUB no-download deferral policy;
- Gate 15 diagnostic UI;
- Sync summary pending count.

### Tests executed / results
- unit coverage added for:
  - v1→v2 migration;
  - legacy baseline remains unknown;
  - storage pending mark/list/count/clear;
  - initial materialized revision;
  - remote revision → durable pending;
  - pending survives subsequent no-op Sync;
  - KOReader progress/annotation/XPointer/page/checksum signals;
  - conservative refresh decisions;
  - bounded local-file reads;
  - Gate 15 diagnostic UI;
  - Sync pending-count output.
- CI #917 on `e491c7ed6096513d623f6ac6129e4ad73de56705`: **SUCCESS**.
- artifact outer SHA-256: `c73318305a728292e4b1c90c0c9da5c86c66de1899a37ad6b02601fc60b77459`.
- installable ZIP SHA-256: `6371f5d49656bb7fad201494a81f29bdc6df2e60cb895e39750a103ef84828b6`.
- ZIP integrity/version/layout: PASS.
- no test files in installable package.

### Gate status
- Gates 0–14: **PASSED**.
- Gate 15: **OPEN — Q1 physical spike required**.
- Gate 16: blocked.
- V1 acceptance: blocked.

### Physical blocker
Run the 0.1.44 article before/title-change/Sync/after diagnostic sequence. Raw PDF/EPUB coverage follows only when suitable already-local original-format fixtures exist.


### Session closeout — Gate 15 Q1 ready for device

- Phase P / PR #17 merged successfully to main at `5d7c954d051e491c1b11344057c59df7e2cf9656`.
- Phase Q branch/PR created: `phase-q/content-refresh-gate15` / draft PR #18.
- 0.1.44 implementation, tests, canonical spec, PLAN and device runbook are synchronized.
- validated package remains the #917 artifact with installable SHA-256 `6371f5d49656bb7fad201494a81f29bdc6df2e60cb895e39750a103ef84828b6`.
- final pre-handoff CI #921 is green.
- no Gate 15 Q2 content acknowledgement or replacement code has been implemented ahead of the required PW3 evidence.
- next action is exactly the Q1-A article baseline → Reader title-only revision → Sync → preservation → post-revision diagnostic sequence documented above.


### Gate 15 Q1 attempt 1 — 0.1.44 physical FAIL

User tapped **Inspect content refresh safety (Gate 15)** and KOReader exited back to the launcher before any diagnostic result appeared.

Root cause was identified without requiring another device action:
- 0.1.44 was the first build to trigger DB schema v1→v2 migration;
- the diagnostic's parent preflight lazily opens the DB;
- KOReader `ffiUtil.copyFile` returns **nil on successful copy**;
- `DB:_backupBeforeMigration` incorrectly treated that nil as a failed backup;
- the resulting Lua error escaped the menu callback;
- migration SQL had not started yet, so the original v1 DB should remain unchanged;
- a valid `readwisereader.sqlite3.bak` may have been created before the erroneous failure.

0.1.45 fixes/hardens:
- nil from KOReader copyFile = success;
- non-nil string = copy error;
- regression coverage models the real KOReader contract;
- parent DB/sidecar preflight errors are contained with `pcall`;
- normalized visible text comparison no longer uses `ffi/sha2`; it uses direct Lua string equality;
- existing local content replacement remains hard-disabled.

Next physical action: install 0.1.45, open the same managed article, tap Gate 15 once, and return the full diagnostic screen. If KOReader exits again, stop immediately and preserve the newest `koreader/crash.log`.


### Gate 15 Q1-A baseline on 0.1.45 — PASS

Physical PW3 result after installing corrected build 0.1.45:
- Gate 15 diagnostic opened normally; no KOReader/KUAL exit;
- category: `article`;
- local format: `html`;
- download strategy: `reader_html`;
- local file present: **yes**;
- sidecar present: **yes**;
- `percent_finished = 0.1538`;
- sidecar annotations: **6**;
- last XPointer present: **yes**;
- last page present: **no**;
- partial file checksum present: **yes**;
- reading state at risk: **yes**;
- DB remote revision: `2026-09-24T16:36:08.800974+00:00`;
- materialized remote revision: **unavailable** (expected for legacy pre-v2 materialization);
- refresh pending: **no**;
- pending remote revision: unavailable;
- current Reader revision equals DB remote revision;
- remote revision state: `materialized_baseline_unknown`;
- remote probe: **passed**;
- visible-text comparison: **same**;
- local HTML bytes: **27733**;
- remote HTML bytes: **27477**;
- V1 refresh decision: `same_visible_text_keep_local`;
- automatic replacement allowed: **no**;
- remote writes: **none**;
- local writes: **none**.

Interpretation:
- 0.1.45 fixes the 0.1.44 crash path on the target;
- schema migration/open path is now functional;
- legacy materialization baseline being unknown is expected and safe;
- the article has real progress + annotations and therefore is a valid Q1-A preservation fixture;
- baseline text comparison is stable despite wrapper/markup byte-count differences;
- no replacement/write occurred.

Next physical action:
1. in Reader, change **only the title** of this same document;
2. do not delete/re-save or edit body content;
3. after Reader persists the rename, run ordinary **Sync now** once on Kindle;
4. return the complete Sync report;
5. do not run a second Sync yet;
6. then reopen the article and verify progress/position + highlights/notes remain before the post-revision Gate 15 diagnostic.


### Gate 15 Q1-A title-only revision Sync — PASS PARTIAL

Physical target: PW3 / KOReader v2026.07.1 / build 0.1.45.

After the user changed **only the Reader document title** for the baseline article, one ordinary Sync was run.

Visible report evidence:
- Content refresh pending review: **1**;
- Metadata documents seen: **1**;
- Filtered out: **0**;
- Retryable item errors: **0**;
- Retryable stages: none;
- Errors: **0**;
- Metadata write errors: **0**;
- Collection write errors: **0**;
- Metadata pages: **1**;
- Content pages: **0**;
- Duplicate API records ignored: **0**;
- Remote preflight: **passed**;
- Annotation sync: `scan_partial`;
- Managed annotation documents scanned: **802**;
- Authoritative annotation sidecars: **13**;
- Annotation documents skipped safely: **789**;
- Annotation scan/normalize/queue exceptions: **0**;
- Current annotation document status: **ok**;
- Managed-document highlights scanned: **12**;
- Highlights created: **0**;
- Highlights already linked: **12**;
- Highlights unmatched/ambiguous: **0**;
- Create queue items processed: **0**;
- Create queue waiting after sync: **0**;
- Notes updated: **0**;
- remote highlight deletions: **0**;
- annotation remote errors: **0**.

Interpretation:
- the title-only same-ID Reader revision was detected and is now durably pending review;
- no content page/download was performed for the existing local document;
- no annotation duplication/regression is visible in the Sync report;
- no remote/content replacement error occurred;
- this proves the 0.1.45 no-replacement path is active for the deterministic metadata-only revision.

Gate 15 Q1-A is not complete yet. Required next evidence:
1. reopen the same local article;
2. verify reading position/progress unchanged;
3. verify its existing highlight(s) remain;
4. verify note(s) remain;
5. run **Inspect content refresh safety (Gate 15)** again;
6. require:
   - Refresh pending: yes;
   - remote probe: passed;
   - Visible-text comparison: same;
   - Reading state at risk: yes;
   - decision: `same_visible_text_keep_local`;
   - Automatic replacement allowed: no;
   - remote writes none / local writes none.
7. Do not run another ordinary Sync until this post-revision diagnostic is reviewed.


### Gate 15 Q1-A post-revision diagnostic — PASS

After the title-only Reader revision and first Sync, the user verified:
- local article still opens;
- reading position/progress unchanged;
- existing highlights unchanged;
- existing notes unchanged.

Post-revision Gate 15 diagnostic on build 0.1.45:
- category: article;
- local format: html;
- download strategy: reader_html;
- local file present: yes;
- sidecar present: yes;
- percent_finished: **0.1538**;
- sidecar annotations: **6**;
- last XPointer present: **yes**;
- last page present: no;
- partial file checksum present: yes;
- reading state at risk: **yes**;
- DB remote revision: `2026-09-24T18:00:45.318557+00:00`;
- materialized remote revision: unavailable (legacy baseline, expected);
- refresh pending: **yes**;
- pending remote revision equals current Reader revision;
- remote revision state: `materialized_baseline_unknown`;
- remote probe: **passed**;
- visible-text comparison: **same**;
- local HTML bytes: **27733**;
- remote HTML bytes: **27477**;
- V1 refresh decision: **`same_visible_text_keep_local`**;
- automatic replacement allowed: **no**;
- remote writes: none;
- local writes: none.

Conclusion:
- Q1-A article safety **PASSED physically**;
- a real same-ID metadata-only Reader revision was detected durably;
- local bytes were not replaced;
- KOReader progress/highlights/notes survived;
- normalized visible content remained equivalent;
- Q2 is now authorized to acknowledge/clear only these proven same-visible-text article revisions without touching local bytes or sidecar.


## Phase Q 0.1.46 Q2 implementation handoff

### Physical evidence carried forward
Q1-A on 0.1.45 passed:
- title-only Reader revision;
- durable pending = 1;
- content pages = 0;
- local progress/highlights/notes preserved;
- post-revision visible text = same;
- replacement = no.

### Files altered for Q2
- `readwisereader.koplugin/sync/content_refresh_reconcile.lua` (new)
- `readwisereader.koplugin/sync/worker.lua`
- `readwisereader.koplugin/ui/sync.lua`
- `readwisereader.koplugin/constants.lua`
- `readwisereader.koplugin/tests/test_content_refresh_reconcile.lua` (new)
- `readwisereader.koplugin/tests/test_sync_ui.lua`
- `readwisereader.koplugin/tests/run.lua`
- `readwisereader.koplugin/_meta.lua`
- `CHANGELOG.md`
- `IMPLEMENTATION_SPEC.md`
- `PLAN.md`
- `docs/DEVICE_TESTS.md`
- `STATUS.md`

### What was implemented
- max 5 pending HTML comparisons per normal Sync;
- bounded local + Reader HTML reads;
- exact durable revision equality check;
- same visible text → clear pending marker only;
- different/unverified/race/error → retain pending;
- raw PDF/EPUB → retain pending without remote replacement fetch;
- detailed Sync report counters;
- no content/sidecar replacement path.

### Tests executed
Deterministic Q2 tests cover:
- same-text metadata-only acknowledgement;
- changed text retained;
- PDF/EPUB retained and no GET issued;
- newer Reader revision race retained;
- Reader timeout retained;
- per-Sync article comparison cap;
- Q2 Sync summary fields.

Automated/package validation:
- CI #984: **SUCCESS**;
- outer artifact SHA-256: `4149d57aa00b6500c6b6ec96a39b85977df2d3109f3cfb5c4785506bb97716cf`;
- installable ZIP SHA-256: `9e9b0d61eb2d13911c80d4a937524679d9f11a935a23cafa624ac6e0cacc9c1f`;
- ZIP integrity/version/layout: PASS.

### Gates
- Gates 0–14: PASSED.
- Gate 15 Q1-A: **PASSED physically**.
- Gate 15 Q2: **IMPLEMENTED / PHYSICAL TEST PENDING**.
- Gate 15 Q1-B raw coverage: pending when suitable fixtures are available.
- Gate 16: blocked.
- V1 acceptance: blocked.

### Blocker
One 0.1.46 ordinary Sync on the existing pending Q1-A article, preservation verification, then one unchanged Sync.


### Gate 15 Q2 0.1.46 first physical Sync — PARTIAL PASS / top counters cropped

User ran the required first ordinary Sync on build 0.1.46 using the already-pending Q1-A article revision.

Visible report evidence:
- Raw PDF/EPUB revisions retained: **0**;
- Unverified refresh revisions retained: **0**;
- Refresh local files missing: **0**;
- Refresh revision races retained: **0**;
- Refresh remote read errors: **0**;
- Filtered out: **0**;
- Metadata documents seen: **1**;
- Retryable item errors: **0**;
- Retryable stages: none;
- Errors: **0**;
- Metadata write errors: **0**;
- Collection write errors: **0**;
- Metadata pages: **1**;
- Content pages: **0**;
- Duplicate API records ignored: **0**;
- Remote preflight: **passed**;
- Annotation sync: `scan_partial`;
- Managed annotation documents scanned: **802**;
- Authoritative annotation sidecars: **13**;
- Annotation documents skipped safely: **789**;
- annotation scan/normalize/queue exceptions: **0**;
- Current annotation document status shown as `current_document_not_managed` for this Sync context;
- Managed-document highlights scanned: **12**;
- Highlights created: **0**;
- Highlights already linked: **12**;
- Highlights unmatched/ambiguous: **0**;
- Create queue items processed: **0**;
- Create queue waiting after sync: **0**;
- Notes updated: **0**;
- local/remote highlight deletions: **0**.

Interpretation:
- Q2 Sync completed without content download/replacement and without visible annotation regression;
- all visible safety/error buckets are zero;
- however the photograph starts at `Raw PDF/EPUB revisions retained` and crops the decisive Q2 counters immediately above it.

Still required before marking this first Q2 Sync PASS:
- `Content refresh pending review`;
- `Refresh pending examined`;
- `Refresh articles compared`;
- `Metadata-only revisions acknowledged`;
- `Changed-content revisions retained`.

Do not run a second Sync until those counters from this same first Q2 report are captured/reviewed.


## 2026-09-24 continuation audit — Gate 15 Q2 physical blocker

### Current milestone
- Phase Q / Gate 15 remains **OPEN**.
- Q1-A article safety remains **PASSED physically**.
- The first 0.1.46 Q2 Sync has already run once and all visible safety/error counters passed, but the five acknowledgement counters at the top of that same report were cropped.
- Phase R / Gate 16 remains blocked.

### Branch / HEAD
- Branch: `phase-q/content-refresh-gate15`.
- Base `main`: `5d7c954d051e491c1b11344057c59df7e2cf9656`.
- Draft PR: #18; still draft and mergeable.
- Production 0.1.46 code/package head remains `2fe649de11ed4acb5b3914386e7f98e52f81646b`.
- Test head before this documentation closeout: `bfa7af39cebfd3f3470ddea4ce03503d78bba55d`.
- No production plugin file changed after the validated 0.1.46 code/package head; the later diff contains only canonical docs/device-test notes and `tests/test_content_refresh_reconcile.lua`.
- This documentation-only closeout commit follows `bfa7af39...`.

### Files altered in this continuation
- `readwisereader.koplugin/tests/test_content_refresh_reconcile.lua`;
- `IMPLEMENTATION_SPEC.md`;
- `docs/DEVICE_TESTS.md`;
- `STATUS.md`.
- `PLAN.md` was read completely and did not require a scope change.

### What was implemented / verified
- re-read `STATUS.md`, `IMPLEMENTATION_SPEC.md` and `PLAN.md` completely before changing the repository;
- re-inspected PR #18, current branch/base and the actual Q2 production path;
- verified Q2 production still requires exact pending Reader revision equality, clears only the pending marker for same visible text, retains changed/unverified/raced/raw revisions, and never replaces local bytes/sidecars;
- added explicit automated idempotency coverage proving that after one metadata-only acknowledgement a second reconcile sees zero pending work, issues no extra Reader GET and acknowledges nothing;
- added automated coverage proving repeated raw reconciliation keeps raw revisions pending and performs no replacement GET;
- added automated coverage proving a missing local article remains pending and performs no remote comparison;
- corrected the test harness so `listContentRefreshPending()` models the real SQL query and returns only pending rows;
- documented a read-only recovery path for the already-cropped first Q2 report so the fixture is not mutated merely to recreate evidence.

### Tests executed / results
- pre-change branch HEAD `376e6dd...`: workflow #998 **SUCCESS**; development checks, full Lua suite, ZIP build, package layout and artifact upload all passed;
- first expanded-test run #1002: **FAILED only in the new test harness** because the fake pending-list method returned an acknowledged row that the real SQL query filters out; production code was unchanged;
- harness corrected in `bfa7af39...`;
- workflow #1004 on `bfa7af39...`: **SUCCESS**; development checks, full Lua suite, ZIP build, package layout and artifact upload all passed;
- compare from production head `2fe649de...` through `bfa7af39...` shows no production plugin-file changes after 0.1.46.

### Gates
- Gates 0–14: **PASSED**.
- Gate 15 Q1-A: **PASSED physically**.
- Gate 15 Q2: **first Sync executed; visible safety portion passed; acknowledgement proof still pending because the top counters were cropped**.
- Gate 15 Q1-B raw coverage: still pending when/if suitable already-local original PDF/EPUB fixtures remain available.
- Gate 16: **BLOCKED by Gate 15**.

### Physical tests pending
1. **Do not run another ordinary Sync yet.**
2. If the first Q2 report is still available, capture the five acknowledgement counters at its top.
3. If that report is gone/cannot be recovered, open the same Q1-A article and run **Inspect content refresh safety (Gate 15)** once. Require pending=no, current Reader revision=DB revision, remote probe passed, visible text same, replacement no, remote writes none, local writes none.
4. If that diagnostic says pending=yes, stop; do not run a second Sync.
5. Confirm the article still has the same progress/position, highlights and notes.
6. Only after the first acknowledgement is established, run one unchanged second Sync and require zero acknowledgement/work for the same revision and pending=0.
7. Then use already-local original PDF/EPUB fixtures for harmless title-only Q1-B revisions if they still exist; do not manufacture a destructive fixture.

### Bugs / failures found
- No production Q2 defect was found in this continuation.
- The only new automated failure was the deliberately-added test harness semantics; CI exposed it and the harness was corrected.
- The physical report layout/capture can hide the Q2 acknowledgement lines. This is a test-evidence problem, not evidence of a Q2 content-safety failure.

### Technical decisions / spec deviations
- No product-scope change and no production behavior change.
- Gate 15 validation now explicitly permits a read-only diagnostic recovery when the one authorized first Q2 report was cropped/dismissed. This avoids mutating the fixture merely to recreate a report.
- This is a validation-procedure refinement from physical UI evidence, not a relaxation of Gate 15: pending must still be proven cleared, local state must remain intact, and the unchanged second Sync must still be idempotent.
- No firmware/KOReader update, Wi-Fi control, credential handling change, destructive remote behavior or replacement path was added.

### Blocker
The only immediate blocker is **physical first-acknowledgement evidence for the Q2 Sync that already happened**. No further code or Gate 16 work is authorized before that evidence is resolved.

### Exact next steps
1. Recover the five counters from the existing first Q2 report if possible; otherwise use the read-only Gate 15 diagnostic fallback above.
2. Verify local progress/position/highlights/notes.
3. Run the unchanged second Sync only after steps 1–2 pass.
4. Resolve Q1-B original PDF/EPUB coverage/scope.
5. Close Gate 15 only when article Q2 idempotency and raw-format evidence/scope are both documented.
6. Only then start Phase R / Gate 16.


### Gate 15 Q2 first-report lower-half photo — safety evidence confirmed, acknowledgement lines still above viewport

New physical photo received from the same already-authorized first 0.1.46 Q2 Sync report.

Visible lower-half evidence:
- annotation documents skipped safely: 789;
- annotation scan errors: 0;
- annotation scan exceptions isolated: 0;
- annotation normalize exceptions isolated: 0;
- annotation queue errors: 0;
- annotation queue exceptions isolated: 0;
- annotation repository source: managed_local;
- annotation repository fallback: no;
- current annotation document status: current_document_not_managed;
- managed-document highlights scanned: 12;
- highlights created/reconciled/unmatched/blocked/queued: 0;
- highlights already linked: 12;
- create queue processed/waiting: 0;
- notes updated/conflicts/mutation blocks: 0;
- local/remote highlight deletions: 0;
- annotation remote errors: 0;
- finished documents scanned: 802;
- finished status detected: 0;
- archive intents queued/processed: 0;
- Reader documents archived: 0;
- archive queue waiting after sync: 0;
- archive remote errors: 0;
- incremental watermark updated.

Interpretation:
- this strengthens the already-recorded first-Q2 safety evidence: no annotation or archive side effect/regression is visible and the Sync completed successfully;
- it still does **not** expose the five decisive Q2 acknowledgement counters because the viewport is lower in the report;
- do not run another Sync;
- keep the existing report open and scroll upward to capture:
  - Content refresh pending review;
  - Refresh pending examined;
  - Refresh articles compared;
  - Metadata-only revisions acknowledged;
  - Changed-content revisions retained.
- if the existing report can no longer be recovered, use the read-only Gate 15 diagnostic fallback already recorded in this STATUS/spec.


### Gate 15 Q2 first acknowledgement — PASS via read-only recovery diagnostic

Physical recovery diagnostic was run on the same Q1-A article after the already-authorized first 0.1.46 Q2 Sync, without running another Sync.

Observed:
- category: article;
- local format: html;
- download strategy: reader_html;
- local file present: yes;
- sidecar present: yes;
- sidecar percent_finished: **0.1538**;
- sidecar annotations: **6**;
- last XPointer present: **yes**;
- partial file checksum present: yes;
- reading state at risk: yes;
- DB remote revision: `2026-09-24T18:00:45.318557+00:00`;
- materialized remote revision: unavailable (expected legacy baseline);
- **Refresh pending: no**;
- pending remote revision: unavailable;
- current Reader revision: `2026-09-24T18:00:45.318557+00:00`;
- current Reader revision equals DB remote revision;
- remote revision state: `materialized_baseline_unknown`;
- **Remote probe: passed**;
- **Visible-text comparison: same**;
- local HTML bytes: 27733;
- remote HTML bytes: 27477;
- V1 refresh decision: `same_visible_text_keep_local`;
- **Automatic replacement allowed: no**;
- **Remote writes: none**;
- **Local writes: none**.

Interpretation:
- the exact pending Q1-A metadata-only revision is no longer pending after the first Q2 Sync;
- because 0.1.46 only clears that durable marker on exact-revision + same-visible-text reconciliation, the cropped first-report acknowledgement is now recovered without mutating the fixture again;
- local document bytes were not replaced;
- sidecar reading state remains present with the same 0.1538 progress, 6 annotations and XPointer evidence;
- first Q2 acknowledgement is therefore **PASSED**;
- Gate 15 remains open only for the unchanged second-Sync idempotency proof and raw PDF/EPUB coverage/scope resolution.

Immediate next physical action:
1. make no changes to the article/title/highlights/notes/reading position;
2. run ordinary **Sync now exactly once**;
3. require for this Q1-A revision:
   - Content refresh pending review = 0;
   - Refresh pending examined = 0;
   - Refresh articles compared = 0;
   - Metadata-only revisions acknowledged = 0;
   - Changed-content revisions retained = 0;
   - Raw PDF/EPUB revisions retained = 0 unless an unrelated raw fixture is already pending;
   - Unverified/race/remote-read-error refresh counters = 0;
   - Content pages = 0;
   - Errors = 0;
4. verify the same article still preserves progress/position, highlights and notes;
5. return the full Sync report before making any raw-format test changes.


## Gate 15 Q2 article idempotency — PHYSICAL PASS

User confirmed the required unchanged second ordinary Sync on build 0.1.46 passed all requested Q2 criteria and the article remained intact.

Accepted physical result:
- no repeated content-refresh work for the acknowledged Q1-A revision;
- content-refresh pending for that article remained cleared;
- no repeated metadata-only acknowledgement;
- no changed/unverified/race/remote-read-error refresh result for that fixture;
- content pages remained zero;
- Sync completed without errors;
- the same local article preserved reading position/progress, highlights and notes.

Combined with the preceding read-only recovery diagnostic (pending=no, exact Reader revision=DB revision, visible text same, replacement no, remote/local writes none), **Q2 article acknowledgement + idempotency are PASSED**.

### Off-device raw hardening in this continuation
- `test_content_refresh_reconcile.lua` already proves both original PDF and EPUB pending revisions are retained across repeated reconciliation and issue zero replacement GETs;
- missing-local article retention remains covered without remote comparison;
- `test_content_refresh.lua` now explicitly covers both `pdf/pdf` and `epub/epub` returning `defer_raw_keep_local`;
- CI #1012 on `49bbfd1a359aaa3b5f36b2d9145db912bcf44edf`: **SUCCESS** across development checks, full Lua suite, package/layout and artifact upload;
- no production plugin file changed after the validated 0.1.46 production head.

### Current branch / HEAD
- Branch: `phase-q/content-refresh-gate15`.
- Base/integrated `main`: `5d7c954d051e491c1b11344057c59df7e2cf9656`.
- Draft PR: #18.
- Production 0.1.46 code/package head: `2fe649de11ed4acb5b3914386e7f98e52f81646b`.
- Test hardening head: `49bbfd1a359aaa3b5f36b2d9145db912bcf44edf`.
- This documentation closeout commit follows that test head.

### Gates
- Gates 0–14: PASSED.
- Gate 15 Q1-A article safety: PASSED physically.
- Gate 15 Q2 article acknowledgement/idempotency: **PASSED physically**.
- Gate 15 Q1-B raw PDF/EPUB: **PENDING PHYSICAL COVERAGE**.
- Gate 16: blocked until Gate 15 closes.

### Physical blocker / exact next steps
1. Do not change firmware, KOReader or plugin build.
2. Use an **already-local, plugin-managed original PDF** from the earlier Gate 6 proof if it still exists.
3. Open that PDF in KOReader and run **Inspect content refresh safety (Gate 15)** before making any Reader change.
4. Required baseline: category=pdf, local format=pdf, local file present=yes, remote probe=passed, visible-text comparison=`not_attempted_raw`, decision=`defer_raw_keep_local`, replacement=no, remote/local writes=none. Record sidecar/progress/annotation evidence shown.
5. Only after that baseline is confirmed, change **only the title** of that same PDF in Reader, Sync once, and require the raw revision to remain pending with no replacement download/content page and local state intact.
6. Repeat the same sequence for an already-local original EPUB if it still exists.
7. If one or both original Gate 6 fixtures no longer exist locally, record that limitation rather than creating a destructive replacement fixture.
8. Gate 15 closes only after raw coverage/scope is resolved; only then may Phase R / Gate 16 begin.

### Bugs / decisions
- No production defect was found by the Q2 idempotency closeout.
- No scope deviation: V1 still forbids automatic existing-document replacement.
- No secrets/private content were added to tests/docs.
- No firmware/KOReader update, Wi-Fi control or destructive remote behavior was introduced.


### Gate 15 Q1-B original PDF baseline — PHYSICAL PASS

User confirmed the already-local plugin-managed original PDF passed the complete pre-revision Gate 15 diagnostic baseline.

Accepted criteria:
- category: pdf;
- local format: pdf;
- local file present: yes;
- remote probe: passed;
- visible-text comparison: `not_attempted_raw`;
- V1 refresh decision: `defer_raw_keep_local`;
- automatic replacement allowed: no;
- remote writes: none;
- local writes: none;
- no local preservation problem was reported.

Conclusion:
- Q1-B PDF baseline is **PASSED**;
- the raw diagnostic does not fetch/compare replacement body bytes;
- the same PDF is now authorized for a harmless same-ID metadata-only revision test;
- Gate 15 remains open; no Gate 16 work is authorized yet.

### Exact next physical action — PDF metadata-only revision
1. In Readwise Reader, change **only the title** of this exact same PDF.
2. Do not re-save, delete/re-add, move, annotate, or otherwise alter the PDF.
3. Return to Kindle with Wi-Fi ON.
4. Run ordinary **Sync now exactly once**.
5. Require:
   - `Content refresh pending review >= 1` for the PDF revision;
   - `Raw PDF/EPUB revisions retained >= 1`;
   - `Refresh articles compared = 0` for this raw fixture;
   - `Metadata-only revisions acknowledged = 0` for this raw fixture;
   - `Content pages = 0`;
   - `Refresh remote read errors = 0`;
   - `Errors = 0`;
   - no replacement download/content install.
6. Reopen the same PDF and confirm local file opens and its sidecar/progress/annotations remain intact.
7. Run **Inspect content refresh safety (Gate 15)** again and require:
   - refresh pending: yes;
   - current Reader revision = DB remote revision;
   - comparison: `not_attempted_raw`;
   - decision: `defer_raw_keep_local`;
   - automatic replacement allowed: no;
   - remote/local writes: none.
8. Return the Sync report + diagnostic result before changing the EPUB fixture.


## Gate 15 Q1-B original PDF metadata revision — PHYSICAL PASS

User confirmed the complete PDF Q1-B sequence passed on the already-local plugin-managed original PDF using build 0.1.46.

Accepted result against the previously documented criteria:
- only the Reader title was changed for the same PDF identity;
- one ordinary Sync completed successfully;
- the raw PDF revision was retained/deferred rather than acknowledged as an HTML metadata-only revision;
- no replacement content page/download/install occurred;
- no refresh remote-read error or fatal Sync error was reported;
- the same local PDF remained openable;
- local sidecar/progress/annotations remained intact;
- post-Sync Gate 15 diagnostic remained on raw semantics (`not_attempted_raw` / `defer_raw_keep_local`);
- automatic replacement remained disabled;
- diagnostic remote/local writes remained none.

Conclusion:
- **Q1-B PDF is COMPLETE / PASSED physically**;
- article Q1-A + Q2 and raw PDF coverage are now closed;
- the only remaining Gate 15 blocker is equivalent physical coverage for an already-local original EPUB, if the Gate 6 EPUB fixture still exists;
- Phase R / Gate 16 remains blocked until this is resolved.

### Files altered in this continuation
- `STATUS.md`;
- `IMPLEMENTATION_SPEC.md`;
- `PLAN.md`;
- `docs/DEVICE_TESTS.md`.
- no production plugin Lua file changed.

### Implementation / tests
- no production implementation change was necessary after the PDF pass;
- existing automated raw reconciler tests already cover both PDF and EPUB retention across repeated reconciliation with zero replacement GETs;
- explicit `defer_raw_keep_local` decision coverage exists for both PDF and EPUB;
- CI #1012 passed after EPUB decision coverage was added;
- CI #1014 passed after the Q2 article closeout;
- CI #1016 passed after the PDF-baseline documentation update;
- a final documentation-only CI is required after this handoff commit.

### Gates
- Gates 0–14: PASSED.
- Gate 15 Q1-A article safety: PASSED physically.
- Gate 15 Q2 article acknowledgement/idempotency: PASSED physically.
- Gate 15 Q1-B PDF: **PASSED physically**.
- Gate 15 Q1-B EPUB: **PENDING physical coverage**.
- Gate 16: BLOCKED by Gate 15.

### Bugs / failures / decisions
- no new production bug was found;
- raw PDF retention behaved exactly as the conservative V1 policy requires;
- no spec deviation: automatic replacement of an existing raw document remains disabled;
- no firmware/KOReader/plugin upgrade is required for the EPUB test;
- no credentials, signed URLs or private document content were added to Git.

### Blocker / exact next steps
1. Use the **already-local plugin-managed original EPUB** from Gate 6 if it still exists.
2. Open it in KOReader and run **Inspect content refresh safety (Gate 15)** before changing Reader metadata.
3. Baseline must show: category=epub, local format=epub, local file present=yes, remote probe=passed, comparison=`not_attempted_raw`, decision=`defer_raw_keep_local`, replacement=no, remote/local writes=none.
4. If baseline passes, change **only the title** of that same EPUB in Reader.
5. Run ordinary **Sync now exactly once**.
6. Require the EPUB revision to remain raw/pending with no replacement content page/download/install and no Sync error.
7. Reopen the EPUB; verify reflow/open, sidecar/progress/highlights/notes remain intact.
8. Run Gate 15 diagnostic again; require refresh pending=yes, current Reader revision=DB revision, comparison=`not_attempted_raw`, decision=`defer_raw_keep_local`, replacement=no, remote/local writes=none.
9. Return the Sync report + diagnostic result.
10. If the original Gate 6 EPUB fixture no longer exists locally, report that fact instead of downloading/re-saving a new destructive fixture; the scope decision must then be recorded before closing Gate 15.


### Final CI for this handoff
- workflow #1018 on `198ee0e562d8c96c5679ef8827ab44287e6ed474`: **SUCCESS**;
- development checks: PASS;
- full Lua unit suite: PASS;
- installable ZIP build: PASS;
- package layout verification: PASS;
- artifact upload: PASS;
- no production plugin file changed in the PDF-closeout / EPUB-handoff documentation commit.


## Gate 15 Q1-B original EPUB baseline — PHYSICAL PASS

User confirmed the already-local plugin-managed original EPUB passed the complete pre-revision Gate 15 diagnostic baseline.

Accepted criteria:
- category: epub;
- local format: epub;
- local file present: yes;
- remote probe: passed;
- visible-text comparison: `not_attempted_raw`;
- V1 refresh decision: `defer_raw_keep_local`;
- automatic replacement allowed: no;
- remote writes: none;
- local writes: none;
- no local preservation problem was reported.

Conclusion:
- Q1-B EPUB baseline is **PASSED**;
- article Q1-A/Q2 and PDF Q1-B remain closed;
- only the EPUB title-only same-ID revision + post-Sync preservation proof remains before Gate 15 can close;
- Phase R / Gate 16 remains blocked.

### Work completed off-device in this continuation
- re-inspected actual branch/PR HEAD and canonical STATUS/spec/plan before changing anything;
- confirmed CI #1020 on prior handoff was SUCCESS;
- re-verified automated Q1-B raw coverage already includes both PDF and EPUB retention across repeated reconciliation with zero replacement GETs;
- re-verified explicit `defer_raw_keep_local` decision coverage exists for both `pdf/pdf` and `epub/epub`;
- no production code change is warranted before the remaining physical EPUB revision test.

### Files altered
- `STATUS.md`;
- `IMPLEMENTATION_SPEC.md`;
- `PLAN.md`;
- `docs/DEVICE_TESTS.md`.
- no production plugin Lua file changed.

### Exact next physical action — EPUB metadata-only revision
1. In Readwise Reader, change **only the title** of this exact same EPUB.
2. Do not delete/re-add, re-save, move, replace, annotate, or otherwise alter the EPUB.
3. Return to Kindle with Wi-Fi ON.
4. Run ordinary **Sync now exactly once**.
5. Require for this EPUB revision:
   - `Content refresh pending review >= 1`;
   - `Raw PDF/EPUB revisions retained >= 1`;
   - `Refresh articles compared = 0` for this raw fixture;
   - `Metadata-only revisions acknowledged = 0` for this raw fixture;
   - `Content pages = 0`;
   - `Refresh remote read errors = 0`;
   - `Errors = 0`;
   - no replacement content download/install.
6. Reopen the same EPUB and verify it still opens/reflows and sidecar/progress/highlights/notes remain intact.
7. Run **Inspect content refresh safety (Gate 15)** again and require:
   - refresh pending: yes;
   - current Reader revision = DB remote revision;
   - comparison: `not_attempted_raw`;
   - decision: `defer_raw_keep_local`;
   - automatic replacement allowed: no;
   - remote/local writes: none.
8. Return the Sync report + diagnostic result.

### Gate status
- Gates 0–14: PASSED.
- Gate 15 Q1-A article: PASSED.
- Gate 15 Q2 article: PASSED.
- Gate 15 Q1-B PDF: PASSED.
- Gate 15 Q1-B EPUB baseline: PASSED.
- Gate 15 Q1-B EPUB revision preservation: PENDING.
- Gate 16: BLOCKED by Gate 15.


## Session handoff — EPUB baseline closeout

### Milestone atual
- Phase Q / Gate 15.
- Article Q1-A/Q2: PASS.
- Raw PDF Q1-B: PASS complete.
- Raw EPUB Q1-B baseline: PASS.
- Remaining Gate 15 work: one title-only same-ID EPUB revision + preservation proof.

### Branch / implementation HEAD
- Branch: `phase-q/content-refresh-gate15`.
- Implementation/documentation HEAD validated by CI in this session: `c36e5bed6b6a10de04ff1c33e0078dd521af0295`.
- Base `main`: Gate 14 merge `5d7c954d051e491c1b11344057c59df7e2cf9656`.
- PR #18 remains draft and mergeable.
- Production plugin code remains build 0.1.46; no production Lua file changed in this session.
- This STATUS-only handoff commit follows the validated head above.

### Arquivos alterados nesta sessão
- `STATUS.md`;
- `IMPLEMENTATION_SPEC.md`;
- `PLAN.md`;
- `docs/DEVICE_TESTS.md`.
- No production plugin Lua file changed.

### Implementado / registrado
- recorded the physical PASS of the already-local original EPUB baseline;
- aligned canonical spec, V1 plan, device-test ledger and resumability status to the same Gate 15 state;
- preserved the conservative V1 rule: raw PDF/EPUB revisions remain pending/deferred and existing bytes are never auto-replaced;
- confirmed no legitimate Phase R implementation may begin before the remaining EPUB physical revision proof closes Gate 15.

### Testes executados / resultados
- prior full CI #1020 on the PDF closeout/handoff: SUCCESS;
- full CI #1022 on `c36e5bed6b6a10de04ff1c33e0078dd521af0295`: SUCCESS;
- development checks: PASS;
- full Lua unit suite: PASS;
- installable ZIP build: PASS;
- package layout verification: PASS;
- artifact upload: PASS;
- automated raw reconciliation coverage includes both PDF and EPUB retention across repeated runs with zero replacement GETs;
- explicit raw decision coverage includes both `pdf/pdf` and `epub/epub` -> `defer_raw_keep_local`.

### Gates concluídos
- Gates 0–14: PASS.
- Gate 15 Q1-A article safety: PASS.
- Gate 15 Q2 article acknowledgement/idempotency: PASS.
- Gate 15 Q1-B PDF: PASS complete.
- Gate 15 Q1-B EPUB baseline: PASS.
- Gate 15 overall: OPEN.

### Teste físico pendente
Only one Gate 15 physical sequence remains:
1. change only the title of the same already-local original EPUB in Reader;
2. ordinary Sync once;
3. require raw EPUB revision retained/pending, no article comparison/acknowledgement for that raw item, content pages 0, no replacement install and no Sync error;
4. reopen and verify reflow + sidecar/progress/highlights/notes intact;
5. run Gate 15 diagnostic again and require pending=yes, Reader revision=DB revision, `not_attempted_raw`, `defer_raw_keep_local`, replacement=no, remote/local writes none.

### Bugs / falhas encontrados
- No new production bug in this session.
- No failed automated test.
- No loss/duplication/replacement behavior observed.

### Decisões técnicas
- No production change before the EPUB revision proof because the exact raw path already has deterministic automated coverage and PDF physical evidence.
- Do not manufacture/re-download a replacement EPUB fixture; use the existing managed original already proven in Gate 6/baseline.
- Automatic replacement remains disabled.

### Desvios da spec
- None.

### Blocker
- Physical EPUB title-only revision/preservation proof.
- Gate 16 remains blocked until Gate 15 is explicitly closed after that result.

### Próximos passos exatos
1. run the EPUB title-only revision sequence above;
2. record the Sync report and post-Sync diagnostic;
3. if PASS, close Gate 15 in STATUS/spec/plan/device tests;
4. merge/close Phase Q as appropriate;
5. only then begin Phase R / Gate 16 hardening in canonical order.


## Gate 15 Q1-B original EPUB metadata revision — PHYSICAL PASS

User confirmed the final EPUB title-only same-ID revision sequence passed all required criteria on build 0.1.46.

Accepted physical result:
- only the Reader title was changed for the same already-local original EPUB;
- one ordinary Sync completed successfully;
- the raw EPUB revision remained pending/deferred rather than being treated as an HTML metadata-only acknowledgement;
- no replacement content page/download/install occurred;
- no refresh remote-read error or fatal Sync error occurred;
- the same local EPUB reopened/reflowed normally;
- sidecar/progress/highlights/notes remained intact;
- post-Sync diagnostic remained raw: refresh pending=yes, current Reader revision=DB revision, comparison `not_attempted_raw`, decision `defer_raw_keep_local`, automatic replacement=no, remote/local writes=none.

### Gate 15 final result
- Q1-A article safety: PASS.
- Q2 article metadata-only acknowledgement + idempotency: PASS.
- Q1-B original PDF preservation: PASS.
- Q1-B original EPUB preservation: PASS.
- Existing local content bytes/sidecars were never auto-replaced.
- **Gate 15 / Phase Q is PASSED COMPLETE.**
- Phase R / Gate 16 is now unblocked.

### Next implementation state
- close/merge Phase Q PR #18 after final CI;
- branch Phase R from merged `main`;
- harden in spec order: large library, low disk, malformed document, huge document, Unicode, 429, intermittent Wi-Fi, force-close, reboot, migration, rollback, debug-log secret review;
- do all deterministic/off-device tests first; stop only when the next item genuinely requires a PW3 physical test.


## 2026-09-25 — v1.1.0-rc.1 release freeze prepared; one final PW3 acceptance remains

User requested that no further intermediate device checkpoints be required. That changes test cadence, **not gate truth**: missing physical observations remain pending until the single final RC acceptance session.

### Scope / gate state
- Gate 17A rolling EPUB locator: **PASSED physically**.
- Gate 17B one-item import, note, first reopen and outbound dedupe: **PASSED physically**.
- Gate 17B redundant post-Sync reopen: **deferred into final RC acceptance; not separately marked PASS**.
- Gate 17C bounded/idempotent Sync integration: **implementation + deterministic hardening complete; final PW3 acceptance pending**.
- Gate 17D PDF/paging historical import: **explicitly deferred outside v1.1.0**. Existing V1 PDF/EPUB reading and Kindle → Reader sync remain unchanged.

### Architecture correction after alpha.3 audit
The early alpha.3 design ran Reader → KOReader import after ordinary Sync. Audit found a duplicate-risk ordering: a local-only annotation could be POSTed before the plugin reconciled an already-existing Reader highlight at the same passage.

The canonical RC order is now:
1. parent-process Reader → KOReader reconciliation for the currently-open managed rolling document;
2. cancellable child refresh of the remote-highlight cache;
3. bounded local import/link/collision analysis;
4. explicit suppression set for unsafe local create candidates;
5. only then the ordinary child Sync worker, which keeps suppressed create intents pending with attempts unchanged and performs zero POST for them.

Cancellation during reconciliation aborts Sync before outbound writes. Non-cancelled reconciliation failure suppresses current-document highlight creates rather than authorizing a blind POST.

### Remote-highlight cache / deletion safety
- schema v3 adds global `remote_highlights`, keyed by exact Reader highlight child ID and indexed by parent;
- first build atomically replaces the historical snapshot;
- cache semantics are separately versioned, so an old alpha cache forces rebuild even without another SQL migration;
- historical baseline also checks a bounded 5-minute Readwise v2 EXPORT `includeDeleted=true` window before publishing, closing a deletion race during pagination;
- later refreshes use Reader v3 `updatedAfter` + Readwise v2 deletion tombstones with the same overlap;
- tombstones are applied by exact `external_id`, not an unstable source label;
- failed/malformed/repeated-cursor deletion verification does not mutate/advance the cache;
- full cached rows for the current parent are returned every run, so old ambiguous/collision candidates remain visible to the guard without a full Reader traversal.

### Local safety hardening
- max 20 new local annotations / 30 locators per run;
- per-document cursor prevents starvation behind repeated ambiguous passages;
- exact unique XPointer + literal round-trip remains mandatory;
- existing exact-position local highlight with compatible note may be linked instead of duplicated;
- note/identity conflict is not merged; its local create is suppressed;
- conservative equivalent-text detection only suppresses risky outbound creates; text alone never assigns durable identity;
- local annotation ↔ Reader child rebinding is rejected transactionally;
- each new import remains saveHighlight → saveSettings → authoritative sidecar re-read → durable remote-ID link, with just-created-local rollback on failure.

### Migration / rollback hardening
v1.1 moves the DB from schema v2 to v3. Before migration:
- SQLite WAL is checkpointed when active;
- the v2 database is copied to `readwisereader.sqlite3.bak`;
- migration remains transactional.

Tests cover fresh schema, v1→current, v2→v3 data preservation, interrupted-v3 rollback, WAL checkpoint-before-copy, copy failure, and cache repository replacement/deletion.

Downgrade contract: an older schema-v2 plugin must be paired with the pre-migration `.bak`; do not run v1.0 against the schema-v3 DB.

### CI / testing state at release-freeze preparation
The hardening sequence has repeatedly passed full syntax/dev checks and the complete Lua suite. A new final CI/package run is required on the release-freeze commit that changes version/docs to `1.1.0-rc.1`. Stable v1.1.0 is **not** authorized before both that CI and the consolidated PW3 acceptance pass.

### Single final physical acceptance
Follow the v1.1.0-rc.1 section in `docs/DEVICE_TESTS.md`: install once, open the same Gate 17 EPUB, Sync/import bounded batches until no items are deferred, close/reopen to verify old/new highlights + notes, then run one unchanged Sync and require zero new imports/duplicates/fatal errors with document state intact.

No further intermediate device request should be inserted before that final RC handoff unless off-device work uncovers a new safety blocker.


## 2026-09-25 — v1.1.0-rc.1 code freeze CI + package audit PASS

Release-freeze commit: `4b32aaafe34fc61e335ce5aafa52c2d0d0121776`.

CI workflow `36142931148`: **SUCCESS**.
- development/syntax checks: PASS;
- complete Lua unit suite: PASS;
- installable ZIP build: PASS;
- package-layout verification: PASS;
- artifact upload: PASS.

GitHub Actions artifact:
- artifact id: `10868286043`;
- artifact name: `readwisereader-koplugin-4b32aaafe34fc61e335ce5aafa52c2d0d0121776`;
- outer artifact digest: `sha256:bd38616732cfacaabed744edad5815dd8396fd889573366ecca729a4284c9724`.

The uploaded artifact was downloaded and the actual installable inner `readwisereader.koplugin.zip` was audited:
- inner ZIP SHA-256: `06dd37ab92540cd2adf7fa4188456583e1faf6fa889ab18da05286856b87bd7b`;
- root contains exactly `readwisereader.koplugin/`;
- package contains 78 entries;
- packaged `constants.lua` and `_meta.lua` both identify `1.1.0-rc.1`;
- no tests/scripts/.github/dist content is packaged;
- no SQLite DB, settings file, migration backup, sidecar or crash log is packaged;
- Authorization strings in the package are only the expected runtime header construction; no real credential/token is present.

The code freeze includes the final safety hardening added after alpha.3:
- pre-Sync Reader → KOReader reconciliation before outbound highlight creates;
- exact outbound suppression for unresolved collisions;
- global versioned historical/incremental Reader highlight cache;
- v2 EXPORT deletion tombstones by exact external ID, including a bounded overlap tombstone pass during historical baseline;
- stale experimental cache rebuild;
- schema-v3 migration coverage and WAL checkpoint before pre-migration DB backup;
- exact local/remote link rebinding rejection;
- starvation-safe bounded cursor;
- normalized-text collision suppression without using text as durable identity.

Current release state:
- **off-device RC is complete and packaged**;
- **one consolidated PW3 acceptance remains** per `docs/DEVICE_TESTS.md`;
- Gate 17B's deferred final reopen and Gate 17C physical acceptance will both be closed by that one session if it passes;
- Gate 17D PDF/paging historical import remains outside v1.1.0;
- do not merge/tag stable `v1.1.0` before the final PW3 acceptance.


## 2026-09-25 — v1.1.0 final PW3 acceptance PASS; stable release authorized

User reported the complete consolidated `1.1.0-rc.1` physical acceptance succeeded on the target PW3.

Accepted physical evidence:
- migration/install/startup completed normally;
- historical Reader → KOReader import completed on the managed rolling EPUB;
- imported highlights/notes survived close/reopen;
- the prior Gate 17B linked highlight remained deduplicated;
- bounded continuation completed as required;
- final unchanged Sync imported no additional historical highlights, created no duplicate remote highlight, and preserved existing reading/annotation state;
- no fatal import/sync error was reported.

Gate closure:
- Gate 17A: PASS COMPLETE;
- Gate 17B: PASS COMPLETE, including the formerly-deferred post-Sync reopen criterion;
- Gate 17C: PASS COMPLETE;
- Phase T / v1.1 rolling EPUB/HTML historical highlight import: **PASS COMPLETE**;
- Gate 17D PDF/paging: remains separate and OPEN for post-v1.1 work.

Stable release action authorized:
1. promote plugin version from `1.1.0-rc.1` to `1.1.0`;
2. run final full CI/package validation;
3. merge PR #21 if green;
4. tag the resulting green `main` commit as `v1.1.0`.

Usage clarification recorded:
- Settings Locations controls document download/document sync selection;
- historical highlight import in v1.1 is current-open-document scoped, not bulk-library scoped;
- to import all highlights today, open each managed rolling EPUB/HTML and Sync until its deferred-import counter reaches 0.

After the stable tag, resume exactly at Gate 17D with a read-only PDF/paging locator spike. Do not infer PDF locator semantics from EPUB XPointers.


## 2026-09-25 — v1.1.0 merged green; Gate 17D read-only implementation started

- PR #21 merged to `main` as `d3d23e8f70dddad009a76a30a4c143303429b1f5`.
- Final `main` workflow `36145328585`: SUCCESS.
- Stable plugin code on `main` reports version `1.1.0`.
- The available GitHub connector can merge/branch/update files but exposes no Git-tag creation action; therefore the requested `v1.1.0` Git tag could not be created from this session and is not falsely recorded as created.
- New branch: `feature/v1.2-pdf-highlight-probe`, based exactly on green stable `main`.

Gate 17D source validation against KOReader v2026.07.1 established:
- PDF is a paging document;
- PDF `findAllText()` returns page + word boxes rather than XPointers;
- PDF `getTextFromPositions()` consumes page/x/y positions and returns text + page boxes;
- `ReaderHighlight:saveHighlight()` persists paging highlights using `pos0/pos1` and `pboxes`;
- existing KOReader code itself switches to native (`text_wrap=0`) positions for paging/PDF position work.

Implementation decision:
- Gate 17D first step is read-only only;
- single-page, unique, literal text round-trip is the only accepted success;
- multi-page/OCR/repeated/fuzzy cases are measured, not guessed;
- no PDF annotation creation until PW3 proof.

Build under implementation: `1.2.0-alpha.1`.


## 2026-09-25 — Gate 17D alpha.1 off-device green; physical PDF probe next

Implementation/package HEAD before this STATUS-only closeout: `9f8fdf080a2f0b674652e9612bed93511af164e6`.

Implemented:
- paging/PDF locator using KOReader's native `findAllText()` page/box results;
- native single-page `pos0/pos1` reconstruction from interior first/last word-box coordinates;
- `getTextFromPositions()` literal round-trip with `text_wrap=0` temporarily and restoration on success/error;
- unique/missing/ambiguous/text-different/invalid classification;
- exact Reader parent filtering for managed original PDFs;
- cancellable read-only Gate 17D UI;
- no annotation create/link path enabled.

Deterministic coverage:
- unique paging match;
- repeated text ambiguity;
- missing text;
- literal round-trip difference;
- invalid boxes;
- engine exception with `text_wrap` restoration;
- exact PDF parent filtering and note retention;
- non-PDF rejection;
- UI result counters and explicit no-write report.

CI:
- workflow `36146267184` on `9f8fdf080a2f0b674652e9612bed93511af164e6`: **SUCCESS**;
- development checks: PASS;
- complete Lua suite: PASS;
- installable ZIP: PASS;
- package layout: PASS;
- artifact upload: PASS.

Package audit:
- artifact id: `10869274874`;
- outer artifact digest: `sha256:5607da769c92b28c52de60b6d9bf1279f89427979934efec17fd208f188b08bc`;
- installable inner ZIP SHA-256: `f0f10e0f765303a36d30079937c4b4a8acb8077b1703181f643b8743c5afcbf5`;
- package root: exactly `readwisereader.koplugin/`;
- 82 entries;
- packaged version: `1.2.0-alpha.1`;
- no tests/scripts/settings/SQLite DB/backups/sidecars/logs packaged.

Gate state:
- Gate 17D implementation is OFF-DEVICE GREEN;
- PDF historical annotation creation remains disabled;
- exact blocker is one real PW3 read-only PDF locator probe.

Next physical checkpoint:
1. install `1.2.0-alpha.1` preserving settings/DB/documents/sidecars;
2. open an already-local plugin-managed original PDF that already has at least one Reader highlight;
3. Wi-Fi ON;
4. run **Readwise Reader → Inspect PDF Reader highlights (Gate 17D)** exactly once;
5. return the complete result screen.

PASS requires at least one `Unique exact paging matches`, no crash, and both remote/local annotation writes reported none.


## 2026-09-25 — Gate 17D alpha.1 physical FAIL explained; alpha.2 locator correction

Physical result reported from `1.2.0-alpha.1` on the target PW3:
- Reader highlight pages scanned: 11;
- Reader highlight records scanned: 1088;
- highlights for this PDF: 2;
- highlights with text: 2;
- local PDF probes run: 2;
- unique exact paging matches: 0;
- ambiguous: 0;
- missing: 0;
- text round-trip differences: 2;
- other/invalid: 0;
- remote writes: none;
- local annotation/sidecar writes: none.

Gate 17D is **NOT PASSED** by alpha.1.

Diagnosis:
- both samples reached `text_diff`, which means `findAllText()` had already returned exactly one match for each Reader highlight;
- KOReader v2026.07.1 `KoptInterface.all_matches()` intentionally matches the first query token against the **suffix** of a PDF word and the last token against the **prefix** of a PDF word;
- KOReader explicitly notes that paging search returns a **full word box even if only a substring matched**;
- the alpha.1 probe incorrectly treated the independently reconstructed `getTextFromPositions()` string as the identity proof;
- the photographed samples visibly begin with partial-word-looking boundaries (for example `…hecimento…` / `…ergunta…`), consistent with this KOPT behavior.

Alpha.2 correction:
- native first/last word-box centers are still derived from the unique search result;
- `text_wrap=0` is used only temporarily and restored on all paths;
- `getWordFromPosition()` must map each derived endpoint back to the exact first/last PDF words returned by search;
- the query/search relation is exact-token or the precise KOReader first-suffix/last-prefix boundary rule only;
- full-text round-trip is retained as diagnostic and may differ due to complete boundary words, whitespace or line-hyphen reconstruction;
- no fuzzy matching, annotation creation, sidecar write, DB link or Reader mutation is enabled.

Build version is advanced to `1.2.0-alpha.2`. Next blocker remains one read-only physical PDF probe.


## 2026-09-25 — Gate 17D alpha.2 off-device green; corrected PDF probe ready

Final alpha.2 implementation head: `139f67b38f38e29a767507f614f1ecefa2b83a47`.

The alpha.2 locator now:
- treats `findAllText()` as the authoritative unique-search result;
- validates derived native box-center positions by mapping them back through `getWordFromPosition()` to the exact first/last PDF words;
- classifies exact token sequences as `unique_exact`;
- classifies only KOReader's explicit first-word-suffix / last-word-prefix behavior as `unique_boundary`;
- keeps `getTextFromPositions()` full-text reconstruction diagnostic-only;
- restores `text_wrap` after endpoint or diagnostic exceptions;
- still performs zero local annotation/sidecar/link writes and zero Reader mutations.

CI workflow `36148802751`: **SUCCESS**.
- development checks: PASS;
- complete Lua suite: PASS;
- installable ZIP: PASS;
- package-layout verification: PASS;
- artifact upload: PASS.

Artifact/package:
- artifact id: `10870269607`;
- outer artifact digest: `sha256:9cc934a6088ca090d7f98002c01eb2bdcae521d8bb8744c7d04004cb2640a1c5`;
- installable inner ZIP SHA-256: `b985dd4e5845fac85c6f08c2cad9a717bf626d22e93bcd573764a0f591fbd6cc`;
- root: exactly `readwisereader.koplugin/`;
- 82 package entries;
- packaged version/meta: `1.2.0-alpha.2`;
- PDF probe/locator files present;
- no test suite, SQLite DB, migration backup, sidecar or crash-log data packaged. The packaged `ui/settings.lua` is plugin source code, not user settings data.

Next and only blocker:
- repeat the same read-only Gate 17D probe on the same PDF with alpha.2;
- PASS requires `Validated paging positions total >= 1`, `Native endpoint geometry mismatches: 0`, no crash, and both write counters none;
- a non-zero full-text round-trip diagnostic counter is allowed.


## 2026-09-25 — Gate 17D locator alpha.2 PHYSICAL PASS

Target PW3 / KOReader v2026.07.1 physical result:
- Reader highlight pages scanned: 11;
- Reader highlight records scanned: 1088;
- highlights for this PDF: 2;
- highlights with text: 2;
- local PDF probes run: 2;
- unique exact paging matches: 0;
- unique word-boundary paging matches: 2;
- **validated paging positions total: 2**;
- ambiguous matches: 0;
- missing matches: 0;
- **native endpoint geometry mismatches: 0**;
- **search-text relation mismatches: 0**;
- full-text round-trip differences (diagnostic): 1;
- other/invalid matches: 0;
- remote writes: none;
- local annotation/sidecar writes: none.

Interpretation:
- both Reader highlights resolve to unique KOReader paging search geometry;
- both use KOReader's documented first-word-suffix / last-word-prefix boundary behavior;
- native derived positions map back to the exact PDF endpoint words;
- the remaining full-text round-trip difference is diagnostic-only and was explicitly allowed by the corrected Gate 17D contract.

**Gate 17D read-only PDF locator is PASSED COMPLETE.**

Next gate: Gate 17D-2, create exactly one Reader PDF highlight through KOReader's native annotation path, sidecar-only, prove the PDF file itself remains unchanged, prove sidecar persistence, link the existing Reader child ID durably, and prove the next ordinary Sync does not create a duplicate remote highlight.


## 2026-09-25 — Gate 17D-2 one-item PDF import implemented off-device

Build advanced to `1.2.0-alpha.3`.

Implementation:
- explicit **Import one Reader PDF highlight (Gate 17D)** action;
- uses the physically-passed paging locator (`unique_exact` / `unique_boundary`);
- prefers note-bearing unlinked Reader children;
- imports at most one safe item per action;
- local annotation text follows the full native PDF words represented by the KOReader search boxes; Reader child ID remains identity;
- includes page/rotation/zoom/native pos0/pos1/pboxes;
- detects existing local PDF geometry primarily by native pboxes, so a different current zoom/rotation cannot create a stacked duplicate;
- temporarily forces `highlight.highlight_write_into_pdf=false` only around `saveHighlight()` / rollback `deleteHighlight()`;
- restores the user's previous PDF-embedding preference before every `saveSettings()`;
- computes a full PDF digest before and after sidecar creation; digest mismatch is a hard stop before durable Reader linking and rolls back the sidecar item;
- sidecar persistence + imported Reader child ID link reuse the already-proven `RemoteHighlightImport:linkPersisted()` contract;
- link failure rolls back only the just-created local PDF sidecar annotation;
- action performs zero Reader POST/PATCH/DELETE;
- normal Sync is **not yet** changed to bulk-import PDF historical highlights.

Additional hardening:
- remote highlight cache worker now accepts managed PDF documents for the explicit Gate action;
- paging locator now carries current PDF rotation/zoom context into persisted pos0/pos1 when KOReader exposes it;
- tests cover sidecar-only save, preference restoration before saveSettings, note preservation, full-word boundary text, PDF digest integrity failure, durable-link failure rollback, already-linked skip, and native-pbox collision across differing zoom state.

Exact blocker: CI/package must pass on the alpha.3 versioned head before one physical one-item import is authorized.


## 2026-09-25 — Gate 17D-2 alpha.3 off-device green; one-item PDF import ready

Validated implementation/test head: `8f8230360887998c619176d00a9db9460fdbb939`.

CI workflow `36150715913`: **SUCCESS**.
- development checks: PASS;
- complete Lua unit suite: PASS;
- installable ZIP: PASS;
- package-layout verification: PASS;
- artifact upload: PASS.

Artifact/package audit:
- artifact id: `10871337473`;
- outer artifact digest: `sha256:0f3ef3899bbd77c650e4861f5561a98fa3d6a3abbdc2e14c45f8c992ab1fb8fd`;
- installable ZIP SHA-256: `873a30cfc888d617adcdad21eabf6c0b5e9821dc0d03ea053151f3ce9b9e34cb`;
- root exactly `readwisereader.koplugin/`;
- 83 entries;
- packaged version/meta: `1.2.0-alpha.3`;
- required PDF locator/import/cache-worker files present;
- no tests/scripts/.github/dist, SQLite DB/backups, sidecars or crash logs packaged.

Gate 17D-2 is now blocked only on physical one-item proof.

Exact next device sequence:
1. install `1.2.0-alpha.3` preserving DB/settings/documents/sidecars;
2. open the same managed PDF whose alpha.2 locator passed;
3. run **Import one Reader PDF highlight (Gate 17D)** exactly once;
4. require imported=1, PDF digest unchanged=yes, embed preference restored=yes, Reader writes none;
5. close/reopen the PDF before ordinary Sync and verify the imported highlight remains visible; if it carried a Reader note, verify the note;
6. do not run the explicit PDF import action a second time before reporting this persistence result.

Only after 17D-2 persistence passes may ordinary Sync be used to prove outbound dedupe and then bulk PDF integration be implemented.


## 2026-09-25 — Gate 17D-2 alpha.3 physical preflight FAIL; alpha.4 fix

Physical alpha.3 result:
- user selected the explicit PDF import action;
- UI displayed: `Reader highlight import currently supports EPUB/HTML only.`;
- the action stopped during preflight before PDF digesting, local annotation creation, sidecar write, durable link or any Reader mutation.

Root cause:
- `ui/pdf_highlight_import.lua` correctly allowed a paging PDF;
- `sync/remote_highlight_import_worker.lua` had already been widened to EPUB/HTML/PDF;
- but the shared durable importer `sync/remote_highlight_import.lua:getDocument()` still rejected every format except EPUB/HTML;
- the alpha.3 PDF UI test used a mocked importer whose `getDocument()` already returned a PDF, so that cross-module regression was not covered.

Fix:
- shared `Import:getDocument()` now accepts managed local `epub`, `html` and `pdf`;
- unsupported formats remain rejected;
- added direct real-importer regression coverage proving PDF acceptance and unsupported-format rejection;
- no sidecar-only, digest-integrity, note, rollback, remote-link or no-Reader-write invariant was relaxed.

Build advanced to `1.2.0-alpha.4`.

Next physical checkpoint remains the same one-item Gate 17D-2 sequence, but **do not retest alpha.3**.


## 2026-09-25 — Gate 17D-2 alpha.4 preflight hotfix off-device green

Final alpha.4 handoff head before this STATUS-only record: `13eb9d30555bd6cb86772c2f06137fa5924ded9f`.

Regression fixed:
- shared `RemoteHighlightImport:getDocument()` now accepts managed local `pdf` in addition to `epub/html`;
- unsupported formats remain rejected;
- a direct non-mocked regression test covers PDF acceptance so this cannot be hidden by the PDF UI mock again.

CI:
- push workflow `36151804852`: **SUCCESS** on the alpha.4 handoff head;
- implementation fix/test workflows also passed on `dca1fba3...` / `c3e66470...`;
- full development checks, Lua suite, package build/layout and artifact upload passed.

Artifact/package:
- artifact id: `10871219502`;
- outer artifact digest: `sha256:7e642a33e200988a9df9b99928ba3e1d08e44220b633be71ece9c0cc1dbabf3b`;
- installable ZIP SHA-256: `461d9f87872e24375153561aed692019e79e5ae94569c68125a18c92a15ec747`;
- root exactly `readwisereader.koplugin/`;
- 83 entries;
- packaged version/meta: `1.2.0-alpha.4`;
- packaged shared importer explicitly contains the PDF allow-path;
- no tests/scripts/.github/dist, SQLite DB/backups, sidecars or crash logs packaged.

Physical blocker remains unchanged: run the explicit one-item PDF import once, then close/reopen before ordinary Sync.


## 2026-09-25 — Gate 17D-2 alpha.4 physical durable-link FAIL; alpha.5 fix

Physical alpha.4 result:
- explicit one-item PDF import passed the PDF format preflight;
- local sidecar annotation creation proceeded;
- PDF integrity guard did not report a changed PDF;
- durable Reader/PDF identity linking failed;
- UI reported: `The Reader/PDF identity link could not be persisted; the local sidecar item was rolled back.`;
- rollback succeeded, so no unlinked local annotation was left behind and no Reader mutation occurred.

The alpha.4 UI accidentally discarded the specific second return from `linkPersisted()`, so the exact failing substage was hidden.

Hardening/fix in alpha.5:
- KOReader annotation normalization now exposes PDF `pboxes` without changing the existing deterministic ID formula;
- `linkPersisted()` still requires the normal exact local annotation ID first;
- if and only if that lookup fails for a PDF, it may recover the persisted sidecar item by requiring **exactly one** candidate with:
  - same page;
  - exact native pbox sequence/geometry;
  - exact normalized text hash;
  - exact normalized note hash;
- this fallback handles PDF sidecar serialization differences in native pos0/pos1 context without changing old PDF annotation IDs and without fuzzy matching;
- multiple matching sidecar candidates fail closed as `sidecar_ambiguous`;
- no matching persisted candidate fails as `sidecar_lookup`;
- DB link failures remain a separate `db` stage;
- PDF UI now propagates the specific `linkPersisted()` error message before rolling back the just-created local item.

Regression coverage added:
- adapter exposes PDF pboxes;
- in-memory PDF ID differing from persisted sidecar ID is linked through unique exact pbox/text/note evidence;
- ambiguous duplicate geometry never links;
- existing EPUB exact-ID behavior remains the primary path.

Build advanced to `1.2.0-alpha.5`.

Next device test remains one explicit PDF import once, then close/reopen before ordinary Sync.


## 2026-09-25 — Gate 17D-2 alpha.5 off-device green; persisted-sidecar fallback ready

Final alpha.5 CI/package head before this STATUS-only record: `fff07a19fac47044ec778e965f28f8ccdbf2f1a6`.

CI workflow `36154942769`: **SUCCESS**.
- development checks: PASS;
- complete Lua suite: PASS;
- installable ZIP build: PASS;
- package-layout verification: PASS;
- artifact upload: PASS.

Artifact/package audit:
- artifact id: `10872654507`;
- outer artifact digest: `sha256:36b1f01dee3ea0d65a36693305a288e56d9fe4b9e2cec24459d5af893ae32de4`;
- installable ZIP SHA-256: `c817fd5dff0a4cce44b6759f6686824cc25ddd680cde18aa646943ae2ca6767d`;
- root exactly `readwisereader.koplugin/`;
- packaged version: `1.2.0-alpha.5`;
- shared importer includes PDF allow-path plus exact pbox/text/note persisted-sidecar fallback;
- no tests/scripts/.github/dist, SQLite DB/backups, sidecars or crash logs packaged.

Physical blocker:
1. install alpha.5;
2. same managed PDF;
3. run explicit PDF import exactly once;
4. if success, close/reopen before Sync and verify highlight/note;
5. if failure, report the complete message: alpha.5 now preserves the exact sidecar/DB failure stage.


## 2026-09-25 — Gate 17D-2 alpha.5 physical sidecar_lookup FAIL; alpha.6 current-sidecar fix

Physical alpha.5 result:
- PDF preflight passed;
- local sidecar item was created;
- PDF integrity/no-embed guards passed far enough to attempt durable linking;
- specific failure surfaced correctly as:
  `Created PDF highlight was not found uniquely in the persisted sidecar.`;
- rollback succeeded and the just-created local item was removed;
- no Reader mutation occurred.

Diagnosis after KOReader v2026.07.1 source audit:
- `ReaderUI:saveSettings()` is synchronous: it dispatches `SaveSettings`, writes `annotations`, calls `DocSettings.saveSettingsArcFile(...)`, then `doc_settings:flush()`;
- `DocSettings:flush()` backs up the existing sidecar to `metadata.*.lua.old` before writing the current sidecar;
- the generic `DocSettings:open()` intentionally considers both current and `.old` candidates and orders candidates by recency for recovery;
- that recovery behavior is valid generally but unsafe as proof of a **just-flushed** PDF annotation, because an immediate verification may select the previous backup that necessarily lacks the new item.

Alpha.6 fix:
- annotation adapter gains `scanFlushed(local_path, reader_document_id)`;
- it resolves only the current non-legacy sidecar via `DocSettings:findSidecarFile(local_path, true)`;
- it opens that exact current file with `DocSettings.openSettingsFile(sidecar_file)`;
- it normalizes the same `annotations` setting using the existing canonical adapter logic;
- PDF `linkPersisted()` now uses `scanFlushed()`; EPUB/HTML keep the established generic scan path;
- exact deterministic ID remains the first lookup;
- PDF exact pbox/page/text/note fallback remains second;
- no identity, collision, digest, rollback or no-Reader-write rule is relaxed.

Regression coverage:
- fixture where generic `DocSettings.open()` returns a stale `.old` sidecar with no new annotation;
- `scanFlushed()` must ignore that path, locate/open the current metadata file directly, and see the new PDF highlight;
- PDF importer tests fail if the generic scan is used for post-save verification.

Build advanced to `1.2.0-alpha.6`.

Next physical checkpoint remains one explicit PDF import once, followed by close/reopen before ordinary Sync.


## 2026-09-25 — Gate 17D-2 alpha.6 off-device green; current-sidecar verification ready

Final alpha.6 package head before this STATUS-only record: `969c45b9f9b6d35fd853ae9b2c6b5c055e6290fa`.

CI workflow `36156449788`: **SUCCESS**.
- development checks: PASS;
- complete Lua suite: PASS;
- installable ZIP build: PASS;
- package-layout verification: PASS;
- artifact upload: PASS.

Artifact/package audit:
- artifact id: `10873443327`;
- outer artifact digest: `sha256:e5ad74f79927eeb5c56a67f41adb69dd1a416dde2c9c8ad2322b0cf98402e000`;
- installable ZIP SHA-256: `a74c8eecf24b804600286674e521d613e00a2317dadf9367d51ce9a760e0eb1f`;
- root exactly `readwisereader.koplugin/`;
- packaged version/meta: `1.2.0-alpha.6`;
- packaged adapter contains `scanFlushed()`, `findSidecarFile()`, and `openSettingsFile()`;
- PDF durable import path explicitly selects `scanFlushed()`;
- no tests/scripts/.github/dist, SQLite DB/backups, sidecars or crash logs packaged.

Physical blocker:
1. install alpha.6;
2. same managed PDF;
3. run explicit PDF import exactly once;
4. if success, close/reopen before Sync and verify highlight/note;
5. if failure, report the complete specific message.


## 2026-09-25 — Gate 17D-2 alpha.6 physical sidecar_lookup FAIL; alpha.7 native-paging identity fix

Physical alpha.6 result:
- explicit PDF import again reached post-save durable-link verification;
- failure remained:
  `Created PDF highlight was not found uniquely in the persisted sidecar. The local sidecar item was rolled back.`;
- rollback succeeded;
- no Reader mutation occurred;
- therefore the .old/current-sidecar selection fix alone was insufficient.

KOReader v2026.07.1 source audit established the missing contract:
- `ReaderAnnotation:getMatchFunc()` defines paging annotation matching by:
  - datetime equality when both items carry datetime;
  - same page;
  - same pos0.x/y;
  - same pos1.x/y;
- KOReader does **not** use pboxes/text/note as its paging annotation identity matcher;
- pboxes are rendering geometry and may differ/normalize independently.

Alpha.7 correction:
- deterministic local annotation ID remains the first persisted lookup;
- PDF-only fallback now mirrors KOReader native paging identity exactly:
  - datetime when present on both;
  - page;
  - pos0.x/y;
  - pos1.x/y;
- exactly one persisted candidate is required;
- after a positional match, exact normalized text hash + note hash are still required before binding the Reader child ID;
- no fuzzy text, pbox tolerance or approximate coordinate matching is introduced;
- current-sidecar-only `scanFlushed()` from alpha.6 remains in force;
- sidecar diagnostics now expose:
  - raw annotation count;
  - normalized annotation count;
  - malformed/normalization-exception count;
  - scanned/same-page/same-datetime/same-pos0/same-pos1 counts.

Regression coverage:
- persisted PDF item may have different pboxes/rotation/zoom context but same KOReader native paging identity and still link safely;
- multiple native paging matches fail closed;
- missing pos0/pos1 match reports exact stage counters;
- generic sidecar scan remains forbidden for PDF post-save verification.

Implementation/diagnostic head `2fb9e274a2342434c3a485a4a99bea30ad4fa315` workflow `36157868966`: **SUCCESS**.

Build advanced to `1.2.0-alpha.7`.

Next physical checkpoint remains one explicit PDF import once, then close/reopen before ordinary Sync. If lookup still fails, the new error counters identify the exact divergent field.


## 2026-09-25 — Gate 17D-2 alpha.7 off-device green; KOReader-native PDF identity handoff ready

Final alpha.7 package head before this STATUS-only record: `115fa779bbd785da9b2d859413117416a83fbe04`.

CI workflow `36158082771`: **SUCCESS**.
- development checks: PASS;
- complete Lua suite: PASS;
- installable ZIP build: PASS;
- package-layout verification: PASS;
- artifact upload: PASS.

Artifact/package audit:
- artifact id: `10874166672`;
- outer artifact digest: `sha256:c53434aeb116ab530239ffebd2535d1276059b43ad72204879926d27f5028fc7`;
- installable ZIP SHA-256: `0e0fe02e45125be05f095068796883af76e70fb85bb705a43b2357afd2cfadfb`;
- root exactly `readwisereader.koplugin/`;
- 75 packaged files;
- packaged version/meta: `1.2.0-alpha.7`;
- packaged shared importer contains `pdfNativeMatch()`, `samePagingPos()`, staged sidecar counters and exact text/note post-match validation;
- packaged annotation adapter reports raw normalization counts;
- no tests/scripts/.github/dist, SQLite DB/backups, sidecars or crash logs packaged.

Physical blocker:
1. install alpha.7;
2. use the same managed PDF;
3. run explicit PDF import exactly once;
4. if success, close/reopen before ordinary Sync and verify highlight/note;
5. if failure, report the full structural counter message. No further blind matcher changes should be made without those counters.


## 2026-09-25 — Gate 17D-2 alpha.7 physical precision mismatch; alpha.8 persistence fix

Physical alpha.7 result:
- current sidecar contained exactly one raw annotation;
- normalization succeeded: `raw=1, normalized=1, malformed=0, normalize_exceptions=0`;
- exactly one candidate scanned;
- same page: 1;
- same datetime: 1;
- same pos0: 0;
- same pos1: 0;
- local item was rolled back successfully;
- no Reader mutation occurred.

This isolates the item as the newly-created annotation itself: sidecar presence, page and timestamp all agree; only the numeric endpoint coordinates differ.

KOReader v2026.07.1 persistence audit:
- `ReaderHighlight:saveHighlight()` copies `selected_text.pos0/pos1` directly;
- `ReaderAnnotation:addItem()` only adds datetime/pageno/pageref and does not change endpoints;
- `AnnotationsModified` handlers do not change endpoints;
- `SaveSettings` annotation path does not change endpoints;
- KOReader `dump.lua` serializes Lua numbers with `tostring(number)`;
- the plugin annotation identity canonicalizer uses `string.format("%.17g", value)`.

Therefore an engine float with more precision than KOReader's textual sidecar representation can have:
- one binary value in memory before save;
- a shorter decimal representation written by KOReader;
- a slightly different binary value after `dofile` reload;
- different deterministic 17-digit locator identity and failed exact x/y comparison,
while still being the same annotation.

Alpha.8 fix:
- every generated PDF paging `page/rotation/zoom/x/y` value in pos0/pos1 is converted through `tonumber(tostring(value))` before native endpoint validation and before `saveHighlight()`;
- this is not tolerance/fuzzy matching: it pre-applies KOReader's exact on-disk numeric round-trip;
- persisted sidecar values should therefore reload bit-equivalent to the in-memory values used for deterministic identity;
- pboxes remain rendering geometry and are not promoted to identity;
- alpha.7 native paging fallback + structural diagnostics remain as secondary safety.

Rollback hardening:
- capture the created annotation table immediately after `saveHighlight()`;
- use that object reference for durable linking;
- on failure, re-find its current list index by table identity before deletion;
- verify the exact target reference is absent before/after sidecar save;
- prevents a shifted index from deleting a neighboring annotation or falsely reporting rollback success.

Implementation/test head `b1ae635447bb553f7da3a9e5ffb99083ebe555cf` workflow `36160586054`: **SUCCESS**.

Build advanced to `1.2.0-alpha.8`.

Next physical checkpoint: one explicit PDF import once, then close/reopen before ordinary Sync. If lookup still fails, retain and report the alpha.7 structural counter message.


## 2026-09-25 — Gate 17D-2 alpha.8 off-device green; persisted-number fix ready

Final alpha.8 package head before this STATUS-only record: `36022dc22d63a7c43d99c42f06907e750908d217`.

CI workflow `36160817481`: **SUCCESS**.
- development checks: PASS;
- complete Lua suite: PASS;
- installable ZIP build: PASS;
- package-layout verification: PASS;
- artifact upload: PASS.

Artifact/package audit:
- artifact id: `10875328920`;
- outer artifact digest: `sha256:896d4bed987a10216d8cf8298a9b61cb45000b7bd681d49958597f8680ca2c54`;
- installable ZIP SHA-256: `74b908d7d9e27ef98ea07228295e47eaf842ed259d2e6390ce4ef2911d03da09`;
- root exactly `readwisereader.koplugin/`;
- 83 entries;
- packaged version/meta: `1.2.0-alpha.8`;
- packaged paging locator contains persisted-number normalization via `tonumber(tostring(value))`;
- packaged PDF import UI captures the created annotation reference immediately and rollback re-resolves its current index;
- alpha.7 structural sidecar diagnostics remain packaged;
- no tests/scripts/.github/dist, SQLite DB/backups, sidecars or crash logs packaged.

Physical blocker:
1. install alpha.8;
2. same managed PDF;
3. run explicit PDF import exactly once;
4. if success, close/reopen before ordinary Sync and verify highlight/note;
5. if failure, report the complete structural counter message.


## 2026-09-25 — Gate 17D-2 alpha.8 physical one-item import PASS; reopen persistence next

Target PW3 physical result on `1.2.0-alpha.8`:
- Reader highlights for this PDF: 2;
- already-linked Reader highlights skipped: 0;
- local position collisions skipped: 0;
- ambiguous locators skipped: 0;
- missing locators skipped: 0;
- invalid locators skipped: 0;
- **imported local PDF highlights: 1**;
- imported Reader note: no;
- locator class: `unique_boundary`;
- **PDF file digest unchanged: yes**;
- **PDF embed preference restored: yes**;
- **Reader writes from import: none**;
- UI confirmed: one PDF highlight was saved to the KOReader sidecar and linked to its existing Reader child ID.

This proves on the target device:
- alpha.8 persisted-number normalization fixed the prior durable-link failure;
- one Reader PDF child can be created locally through KOReader's native paging annotation path;
- the original PDF bytes remain unchanged;
- the user's PDF-embedding preference is restored;
- the existing Reader child ID is linked durably with zero Reader mutation from the import action.

Gate 17D-2 is not yet fully closed because sidecar survival across a real document reopen has not yet been reported.

Next and only physical checkpoint:
1. do **not** run the explicit PDF import action again;
2. do **not** run ordinary Sync yet;
3. close the same PDF and reopen it normally;
4. verify that the imported highlight is still visible;
5. no note check is required for this imported item because the selected Reader highlight had no note;
6. report only whether the highlight survived the reopen.

If reopen persistence passes, the next gate is one ordinary Sync to prove the linked PDF annotation does not create a duplicate Reader child.
