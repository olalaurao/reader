# Implementation Status

> This file is the resumability ledger for implementation. Update it after every meaningful work session.  
> Canonical design: `IMPLEMENTATION_SPEC.md`  
> Roadmap/product intent: `PLAN.md`

## Current milestone

**Phase G COMPLETE — Gate 5 PASSED on PW3 / KOReader 2026.07.1; Phase H raw PDF/EPUB formats is next**

Phase F was merged normally to `main` through PR #6 as `21dd64719ca248dd7706895fab1651751edf8844` after Gate 4 passed on the target PW3 / KOReader 2025.04.

Current work is **Phase F.5 / Gate 4A**:

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





- freeze/back up the known-good 2025.04 state;
- upgrade KOReader only to official `v2026.07.1` using the PW3 `kindlepw2` package;
- run the shorter Gate 4A-1 compatibility regression for Readwise Reader;
- only then install/test Bookshelf `v5.1.4` and validate Reader location Collections + Reader tags metadata;
- Phase G remains blocked until Gate 4A-1 and Gate 4A-2 pass.

The KOReader upgrade does **not** require replaying Gates 0–4 from scratch. Gate 4A-1 deliberately samples only the KOReader-internal contracts that could regress across the version jump.

## Current branch / commit

- Branch: `phase-g/images-gate5`
- Base `main`: `268388dca4f115890a491d557fa81d08f325979e` (PR #7 merge / Phase F.5 + Gate 4A passed)
- Phase F historical merge: `21dd64719ca248dd7706895fab1651751edf8844` (Gate 4 passed on KOReader 2025.04)
- F1 settings/root ownership: `a57da9980d1b77a16bf2a0b8fbaa09327b1691d9`
- F1/F2 incremental sync engine: `265405a479ab538ed4fbdde9223ca97c28aaad07`
- canonical watermark overlap fixes/tests: `e2669755be705686a13977f0b99aa9ccf472b46c`, `e2d97fd8002fc26847243073457b91b70876df86`
- path validation fixes/tests: `d5d219c42ddd08a3997095e5d69f099699d217a6`, `0a73e69e92f69b57250f0261f8f2d1dd553a7e5c`
- F3 cancellable sync UI: `0fa4fa29cb160baedace4b978a6faab477c87af0`
- menu/settings wiring: `029e0caea35fe5a86c8fe26c852b71696bf6ac4b`
- Trapper parent/child safety refactor: `84b356c1c7757c56ea66624e117a63ad2b4c4a68`
- Phase F.5 canonical planning: `13e7537cf97dba68b5119d1910348b1e188c28c9`
- atomic parent watermark commit: `1fe9b5d2b4456405d282240e8171fc0abba4be4c`
- corrected parent-failure test fixture: `6d4a8d5499f52c8f2bc2985e0707183fe1d288dc`
- Run #66 on `84b356c...`: **SUCCESS**
- Run #67 on `13e7537...`: **SUCCESS**
- Run #68 failed only in the newly-edited `test_sync_ui.lua` fixture because the simulated metadata result was accidentally inserted into the Trapper stub; production code was not implicated.
- Run #69 on `6d4a8d5...`: **SUCCESS** — Lua syntax, all unit tests, ZIP build/layout and artifact upload.
- Run #70 on Gate 4 prep tip `5fb309774d8d4442b17251d582e475b21688a331`: **SUCCESS** — development checks, all Lua tests, package/layout and artifact upload.
- Gate 4 CI artifact ID: `10723390104`; artifact digest: `sha256:fdbd74728a74c41d8649e4c3930fc843bb0acc0921910f54507c44e910d88344`.
- Installable inner ZIP `readwisereader.koplugin.zip` verified with `unzip -t`; SHA-256: `ab055261fd54f48936e603f342310b5957ca000e717dca15e6e3fd44eca5afe9`.

## Target environment

- Kindle Paperwhite 3 / 7th generation
- Serial prefix: `G090KB`
- Firmware: `5.16.2.1.1 (4097470002)`
- Jailbreak/KUAL functional
- KOReader historical Gate 0–4 baseline: `2025.04`
- canonical physical V1 baseline from Gate 4A-1 onward: official KOReader `v2026.07.1`, `kindlepw2` package
- Bookshelf `v5.1.4` coexistence: Gate 4A-2 PASSED; current target is Phase G / Gate 5 images

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

- Gate 0: **PASSED**.
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

## Spec deviations / deliberate canonical changes

No accidental implementation deviation is open.

A deliberate roadmap/spec change was made on 2026-09-22 at the user's request: KOReader is no longer assumed to remain at 2025.04 through the whole V1. The canonical order now inserts **Phase F.5 / Gate 4A after Gate 4 and before Phase G**, migrating to official KOReader v2026.07.1 and then validating Bookshelf v5.1.4 coexistence. The reason is to establish a clean Phase F before/after compatibility baseline while avoiding implementing image/raw-format/sidecar internals twice. Full procedure is in `docs/KOREADER_UPGRADE.md`.

## Blockers

Immediate blocker: **merge Phase F, then Gate 4A on the target PW3**. Phase G is blocked until Gate 4A-1 and Gate 4A-2 pass.

**Gate 4A is now the next blocker:** Readwise Reader regression on official KOReader v2026.07.1, then Bookshelf v5.1.4 coexistence.

Later hard gates remain:
- Reader v3 ↔ Readwise v2 highlight ID mapping;
- safe note-update path;
- safe highlight-delete path;
- exact-content matching edge cases;
- relative image assets on CRengine;
- content replacement vs existing KOReader positions/sidecars.

## Exact next steps

1. Run final Phase F CI on the current branch tip.
2. Open/merge the normal Phase F PR into `main`; record the exact merge commit/package as the known-good KOReader 2025.04 baseline.
3. Before changing KOReader, back up `/mnt/us/koreader/` (or at minimum settings/plugins/Readwise DB) plus `/mnt/us/documents/Readwise/` and sidecars.
4. Upgrade **KOReader only** to official v2026.07.1 using `koreader-kindlepw2-v2026.07.1.zip`; do not update Kindle firmware/jailbreak.
5. Run Gate 4A-1 — a targeted compatibility regression, **not a full replay of Gates 0–4**:
   - KOReader/plugin loads;
   - token/test connection;
   - open an existing downloaded article and verify progress/highlight/note;
   - normal sync + no-op second sync;
   - cancel one full rescan and verify watermark safety;
   - one managed Reader move/rename on the same file.
6. If Gate 4A-1 passes, install Bookshelf v5.1.4 with Cover browser enabled.
7. Run Gate 4A-2 coexistence, including Reader location -> Collections and Reader tags -> Bookshelf-compatible metadata.
8. **Do not begin Phase G until Gate 4A-1 and Gate 4A-2 pass.**

## Existing architectural decisions still in force

- KOReader 2025.04 remains the compatibility baseline through Gate 4; official v2026.07.1 becomes the physical V1 baseline only after Gate 4A-1 passes.
- Manual sync only in V1.
- Plugin does not toggle Wi-Fi.
- Reader is the source for library content; Kindle/KOReader is the primary reading surface.
- Reader v3 is used for library and parent-linked highlight creation.
- Readwise v2 is used only where later interoperability testing proves it required/reliable.
- SQLite will hold documents/annotation links/queue/watermarks.
- LuaSettings holds small user config/token.
- KOReader sidecar `annotations` is the annotation source of truth.
- Never use `My Clippings.txt` as source of truth.
- Preserve note text literally, including `[[wikilinks]]`.
- Deletion propagation is OFF by default.
- Remote archive does not delete local files in V1.
- Never blindly retry highlight creation after an ambiguous timeout.

Never rely on chat history alone for project state.
