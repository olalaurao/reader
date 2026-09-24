# Implementation Status

> This file is the resumability ledger for implementation. Update it after every meaningful work session.  
> Canonical design: `IMPLEMENTATION_SPEC.md`  
> Roadmap/product intent: `PLAN.md`

## Current milestone

**Phase P / Gate 14 — P0 FINISHED SIGNAL PASSED PHYSICALLY; P1 Finished → Archive IMPLEMENTED in build 0.1.43; physical archive validation pending**

Phase O / Gate 13 is complete and merged to `main` through PR #16 as `b7c8977b89cf572bec1280e3490a033341af4375`.

Gate 14 P0 physically proved the canonical KOReader Finished signal on the target PW3 / KOReader v2026.07.1:
- before: sidecar/BookList/runtime status = `reading`;
- after **Book status → Finished**: sidecar/BookList/runtime status = `complete`;
- persisted `summary.modified` advanced from 2026-09-23 to 2026-09-24;
- persisted `percent_finished` remained **0.1538**, proving percentage is not the Finished authority;
- sidecar remained present;
- diagnostic performed no plugin network request, remote write, or local write.

Canonical V1 rule: **Finished iff persisted KOReader `summary.status == "complete"`**. Do not infer from reading percentage/end position.

Build 0.1.43 implements the production archive path:
- **Finished documents → Archive in Reader** setting, default ON;
- local canonical finished discovery across Reader-managed locally-present documents;
- durable `archive_document:<reader_id>` intent before remote reachability/mutation;
- read-only Reader GET reconciliation before every PATCH/retry;
- individual Reader PATCH `{"location":"archive"}`;
- idempotent recovery after timeout/process death;
- local document-row location persisted to `archive` before queue success for crash safety;
- parent-side move to plugin-managed `Readwise: Archive` Collection;
- local file, sidecar, progress, highlights and notes are never deleted/rewritten by archive;
- no reverse/unarchive behavior in V1.

Gate 14 remains **OPEN** until the 0.1.43 physical first Sync + local/Reader preservation check + unchanged second Sync pass.

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

- Branch: `phase-p/finished-archive-gate14`
- Draft PR: **#17** — keep draft / do not merge until Gate 14 passes physically.
- Base/integrated `main`: `b7c8977b89cf572bec1280e3490a033341af4375` (PR #16 merge / Phase O + Gate 13 passed)
- Validated 0.1.43 code/package state: `bf3698a0ef1e6368aa6081d3ad499c6d676506c0`.
- Pre-final documentation/status HEAD: `9066f96f133e590cd8343eca3e25812cbd5197e7`; this final STATUS-only handoff commit follows it.
- Build version for physical Gate 14 P1: **0.1.43**.
- Gate 14 P0 signal spike: **PASSED physically**.
- CI run **#865** on the validated 0.1.43 code/package state: **SUCCESS**.
  - development checks: SUCCESS;
  - full Lua unit suite: SUCCESS;
  - installable ZIP build: SUCCESS;
  - package layout validation: SUCCESS;
  - artifact upload: SUCCESS.
- Validated 0.1.43 artifact:
  - workflow run: `36025625389` / run #865;
  - artifact ID: `10819258366`;
  - artifact name: `readwisereader-koplugin-d62120d76d0f9e7455e04b07434047ca03a5a6a7`;
  - outer artifact SHA-256: `694cd120f8de707c4e38403806c993553ed0efc49526e7cdba8fe8a1a083f0e4`;
  - installable inner `readwisereader.koplugin.zip` SHA-256: `479358fa86d85dcde16e22aee2e1195521366a205e14f3708c754a16299bd067`;
  - inner ZIP `unzip -t`: **PASS**, no errors;
  - packaged `constants.lua`: version **0.1.43**;
  - packaged archive/status/diagnostic modules present;
  - packaged ZIP contains no `tests/` entries.
- Final pre-handoff CI run **#867** on `9066f96f133e590cd8343eca3e25812cbd5197e7`: **SUCCESS** across development checks, full Lua suite, package/layout, and artifact upload.
- PR #17 remains draft until Gate 14 completes physically.

## Target environment

- Kindle Paperwhite 3 / 7th generation
- Serial prefix: `G090KB`
- Firmware: `5.16.2.1.1 (4097470002)`
- Jailbreak/KUAL functional
- KOReader historical Gate 0–4 baseline: `2025.04`
- canonical physical V1 baseline from Gate 4A-1 onward: official KOReader `v2026.07.1`, `kindlepw2` package
- Bookshelf `v5.1.4` coexistence: Gate 4A-2 PASSED; current target is Phase P / Gate 14 Finished → Archive

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

Immediate blocker: **physical Gate 14 P1 validation on build 0.1.43**.

Everything possible without the Kindle is complete:
- P0 canonical Finished signal physically proven;
- archive setting implemented;
- durable queue state implemented without schema migration;
- offline/local discovery happens before remote preflight;
- remote archive reconciliation-before-PATCH implemented;
- retry/timeout/process-death idempotency implemented;
- local-file-preservation guard implemented;
- DB location + Collection postprocess implemented;
- deterministic tests cover first archive, second-sync no-op, already-archive adoption, timeout reconciliation without duplicate PATCH, local Finished reversal before PATCH, and missing-local-file blocking;
- storage/config/UI tests updated;
- full CI/package validation passed.

### Deviations / technical decisions
- Section 5.8's old conceptual sequence listed remote preflight before finished detection. Gate 13 proved local network flags cannot authorize writes and established the safer pattern used here: **detect/persist local intent before the read-only remote preflight; perform no remote mutation until preflight passes**. The canonical Phase P spec is updated accordingly.
- No DB schema migration was added because the existing generic queue already has all fields required by `archive_document`.
- `percent_finished` is explicitly not used: physical evidence showed a Finished document at 0.1538.

## Exact next steps

1. Install **0.1.43** preserving settings/database/documents/sidecars.
2. Keep the same test document marked **Finished**.
3. Confirm **Settings → Finished documents → Archive in Reader** is checked.
4. Keep Wi-Fi/internet available.
5. Do not alter/delete the fixture's highlights or notes.
6. Run ordinary **Sync now exactly once**.
7. Return the **entire Sync report**.
8. Verify in Reader that the document location is **Archive**.
9. On Kindle verify:
   - local document still exists and opens;
   - sidecar still exists;
   - reading progress is preserved;
   - existing highlights are preserved;
   - existing notes are preserved.
10. Do **not** run the second Sync until the first report + Reader/local preservation are reviewed.
11. After first-half PASS, run one unchanged second Sync.
12. Require second Sync:
   - Reader documents archived = **0**;
   - Archive queue items processed = **0**;
   - Archive queue waiting after sync = **0**;
   - Archive remote errors = **0**;
   - Reader remains Archive;
   - local file/sidecar/progress/highlights/notes remain intact.
13. Only after that close Gate 14 / Phase P and begin Phase Q / Gate 15.

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


### Remaining V1 path after Gate 13

Numbered gates:
- Gates 0–13: **14 of 17 numbered gates passed**.
- Gate 14: current Phase P / Finished → Archive.
- Gate 15: content refresh safety.
- Gate 16: release-candidate hardening.
- After Gate 16: execute the complete V1 acceptance script and tag `v1.0.0` only if it passes.

The largest remaining technical uncertainty is Gate 15 because remote content replacement must not invalidate local progress/highlights, especially across HTML versus original EPUB/PDF materializations.


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
