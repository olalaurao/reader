# KOReader upgrade + Bookshelf compatibility gate

> Research/plan date: 2026-09-22  
> Device: Kindle Paperwhite 3 / 7th gen (G090KB), firmware 5.16.2.1.1  
> Current KOReader baseline: v2025.04  
> Planned post-Gate-4 baseline: official KOReader v2026.07.1  
> Planned Bookshelf validation: v5.1.4

## Decision: upgrade after Gate 4, before Phase G

The clean migration point is **after Phase F / Gate 4 passes on KOReader 2025.04 and before Phase G**.

Why:

1. Gates 0-3 already passed physically on 2025.04, and Phase F was built against that known baseline.
2. Gate 4 gives a clean before/after reference. If the exact same Readwise Reader build fails after the KOReader update, the regression is attributable to the platform change rather than an unresolved Phase F feature.
3. Phase G/H depend on rendering/download behavior, while Phase I depends directly on sidecar/annotation internals. Updating before those phases prevents implementing them for 2025.04 and immediately reworking them.
4. Bookshelf is introduced only after Readwise Reader passes alone on the new KOReader, so a KOReader-version regression is not confused with plugin coexistence.

## Pinned versions

### KOReader

- Latest official stable release checked on 2026-09-22: **v2026.07.1**.
- Release: https://github.com/koreader/koreader/releases/tag/v2026.07.1
- KOReader build tooling documents `kindlepw2` as the optimized target for Kindle models >= Paperwhite 2.
- `kindlehf` requires firmware >= 5.16.3. This PW3 runs 5.16.2.1.1, so Gate 4A must use **`koreader-kindlepw2-v2026.07.1.zip`**, not `kindlehf`.
- Upstream issue #15794 reported an updater-labelled `2026.07.02` build where several plugins failed to load. For this gate, pin the published official v2026.07.1 release rather than a nightly/development build.

This is a KOReader update only. **Do not update Kindle firmware, jailbreak or KUAL for this migration.**

### Bookshelf

- Latest release checked on 2026-09-22: **v5.1.4**.
- Release: https://github.com/AndyHazz/bookshelf.koplugin/releases/tag/v5.1.4
- Current `_meta.lua` does not publish a formal minimum KOReader version.
- Bookshelf requires KOReader's built-in **Cover browser** plugin.
- Its release history includes explicit compatibility fixes for older KOReader releases. That is useful evidence, but not a guarantee that the current plugin is fully supported on 2025.04.

## Source-level compatibility review of Readwise Reader

Compared between KOReader tags v2025.04 and v2026.07.1, the internal APIs currently used by this project are still present:

- `Trapper:dismissableRunInSubprocess`;
- `ReadCollection:addCollection`, `addItem`, `removeItem`, `write`;
- `DocSettings:flushCustomMetadata(filepath)`;
- `ReaderUI:showReader(filepath)`;
- `NetworkMgr:isOnline()`;
- `LuaSettings`;
- `DataStorage:getSettingsDir()`;
- `ReaderAnnotation` persistence through the `annotations` sidecar setting.

The notable compatibility change is PluginLoader: newer KOReader derives plugin identity from the `.koplugin` directory and treats `_meta.lua` `name` as deprecated for enabled plugins. Keep `name = "readwisereader"` while the old baseline exists because older loaders still need it in disable/re-enable flows; newer KOReader tolerates it.

Source-level presence is not sufficient to close compatibility. The physical Gate 4A below is mandatory.

## Phase F.5 / Gate 4A procedure

### A. Freeze the known-good 2025.04 baseline

Run this only after Gate 4 passes.

Record:
- exact Readwise Reader commit/package;
- KOReader 2025.04;
- successful no-op second sync;
- successful Reader location/title-change tests;
- no duplicate local documents.

Back up before changing KOReader:
- ideally the entire `/mnt/us/koreader/` directory;
- at minimum `koreader/settings/`, `koreader/plugins/`, the Readwise Reader SQLite/settings files and `crash.log`;
- `/mnt/us/documents/Readwise/`, including KOReader sidecars for test documents.

Never expose the Readwise token in chat, Git, screenshots or logs.

### B. Upgrade KOReader only

Install **official v2026.07.1 `kindlepw2`**.

Pinned asset:
- `koreader-kindlepw2-v2026.07.1.zip`
- official release: https://github.com/koreader/koreader/releases/tag/v2026.07.1
- SHA-256: `ea1f575c54492a2c679d128b7f3210fd7d6a87e5f5a1ff1f7a7fe2080ff68f86`

For this existing KUAL installation, prefer KOReader's documented **Manual Update** path rather than deleting/replacing the entire KOReader directory:

1. exit KOReader completely before entering USB storage mode;
2. connect the Kindle by USB;
3. copy the **ZIP itself** (`koreader-kindlepw2-v2026.07.1.zip`) to the Kindle USB root; do not unpack/delete the existing `koreader/` folder;
4. safely eject/unplug;
5. open KUAL -> KOReader -> Tools -> Update KOReader;
6. let the updater finish and relaunch KOReader;
7. verify the reported KOReader version is 2026.07.1 before Gate 4A-1.

The current official Kindle wiki states that manual update preserves settings as long as the `koreader` folder is not deleted.

Do not:
- update Kindle firmware;
- alter jailbreak/KUAL;
- install Bookshelf yet;
- delete KOReader settings or sidecars;
- enter USB mass-storage mode while KOReader is still running.

### C. Gate 4A-1 — Readwise Reader alone

Before installing/enabling Bookshelf, validate the exact Gate 4 Readwise Reader build:

1. KOReader starts normally.
2. Readwise Reader appears and can be disabled/re-enabled.
3. Existing token remains configured without being displayed.
4. `Test connection` succeeds.
5. Existing downloaded Reader article opens normally.
6. Existing reading position, highlight and note still exist.
7. `Sync status` opens.
8. `Sync now` completes.
9. A second sync with no remote changes creates no duplicate.
10. Start a `Full document rescan` and cancel it; KOReader remains responsive and the cancelled attempt does not commit a new document watermark.
11. Move/rename one already-managed Reader article and sync; the same local file/Reader-ID ownership remains.
12. Review `crash.log` for plugin errors and sensitive data.

If any item fails, stop here. Fix compatibility before Bookshelf is introduced.

### D. Adopt the new baseline

After Gate 4A-1 passes:
- update canonical target references to v2026.07.1 where they concern future work;
- use KOReader v2026.07.1 source for all later internal-API spikes;
- retain automated compatibility with 2025.04 where it remains cheap, but physical V1 acceptance moves to v2026.07.1.

### E. Install Bookshelf v5.1.4

Only after Gate 4A-1 passes:

1. Confirm built-in **Cover browser** is enabled.
2. Install Bookshelf v5.1.4 at `/mnt/us/koreader/plugins/bookshelf.koplugin/`.
3. Restart KOReader.
4. Initially leave normal File Manager as the startup screen; do not set `Start with -> Bookshelf` yet.

### F. Gate 4A-2 — Bookshelf coexistence

Validate:

1. Bookshelf loads without disabling Readwise Reader.
2. Readwise Reader remains reachable from KOReader menus.
3. `Sync now` works while Bookshelf is installed.
4. Newly downloaded Readwise documents appear after Bookshelf refresh/restart.
5. Reader location is represented through the plugin-managed `Readwise: Inbox/Later/Shortlist/Feed/Archive` Collections.
6. Move one already-managed document in Reader and sync; Bookshelf/KOReader must reflect the new location Collection without creating a duplicate or losing unrelated user Collections.
7. Reader tags are projected to KOReader custom metadata (`keywords`, or the exact Bookshelf-compatible equivalent validated on this baseline) and are visible/filterable in Bookshelf as tags/genres/keywords.
8. Add/remove/change a Reader tag, sync, refresh Bookshelf if required, and verify the local metadata/Bookshelf representation changes on the same local document.
9. Reader title/author metadata changes continue to update the same local document and remain visible in Bookshelf.
10. Open a Readwise-managed article from Bookshelf; reading controls, position, highlight and note work.
7. Close the article and return to the library without a crash.
8. Run another no-op Readwise sync; no duplicates.
9. Restart KOReader; both plugins still load and settings persist.
10. Only then optionally set `Start with -> Bookshelf` and repeat open -> read -> close -> sync once.

If coexistence fails, keep KOReader v2026.07.1 as the target and debug the interaction before Phase G. Do not weaken document identity, sidecar safety or atomic installation as a workaround.

## Rollback

If v2026.07.1 is unusable on this device:

1. close KOReader;
2. restore the backed-up KOReader directory/version;
3. restore settings/plugin files if the update changed them;
4. keep Readwise documents/sidecars intact;
5. verify the previously known-good 2025.04 Gate 4 package again.

Do not roll back Kindle firmware as part of this project.

## Later implementation rule

**Phase G and every later KOReader-internal spike wait for Gate 4A.** In particular, Phase I sidecar/annotation behavior must be researched and implemented against the post-upgrade pinned KOReader tag, not assumed from v2025.04.
