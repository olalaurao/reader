from pathlib import Path
import os
import shutil


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"marker not found in {path}: {old[:120]!r}")
    if text.count(old) != 1:
        raise SystemExit(f"marker not unique in {path}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1))


def append_once(path, marker, body):
    p = Path(path)
    text = p.read_text()
    if marker in text:
        return
    if not text.endswith("\n"):
        text += "\n"
    p.write_text(text + "\n" + body.rstrip() + "\n")


# Preserve any newer metadata already produced by the document-sync phase.
replace_once(
    "readwisereader.koplugin/sync/worker.lua",
    "            postprocess(local_document.local_path).metadata = copyMetadata(update)\n",
    "            local item = postprocess(local_document.local_path)\n"
    "            if item.metadata == nil then\n"
    "                item.metadata = copyMetadata(update)\n"
    "            end\n",
)

# Lock the precedence rule with a deterministic regression.
replace_once(
    "readwisereader.koplugin/tests/test_worker.lua",
    "    assert(projected.metadata.tags[1] == \"reader-new\")\n"
    "    assert(postprocess_by_path[\"doc-remote-only\"] == nil)\n",
    "    assert(projected.metadata.tags[1] == \"reader-new\")\n"
    "\n"
    "    projected.metadata = { title = \"Newer document-sync metadata\", tags = { \"newer\" } }\n"
    "    Worker._applyMetadataMutationReport({}, {\n"
    "        document_metadata_updates = {\n"
    "            { id = \"doc-1\", title = \"Older metadata mutation result\", tags = { \"older\" } },\n"
    "        },\n"
    "    }, {\n"
    "        getById = function()\n"
    "            return {\n"
    "                reader_id = \"doc-1\",\n"
    "                is_managed = true,\n"
    "                is_local_present = true,\n"
    "                local_path = \"/Readwise/doc-1.epub\",\n"
    "            }\n"
    "        end,\n"
    "    }, postprocess)\n"
    "    assert(projected.metadata.title == \"Newer document-sync metadata\",\n"
    "        \"metadata mutation projection must not overwrite newer document-sync metadata\")\n"
    "    assert(projected.metadata.tags[1] == \"newer\")\n"
    "    assert(postprocess_by_path[\"doc-remote-only\"] == nil)\n",
)

# Label the fully automated candidate accurately; final v1.3.0 remains gated by PW3 acceptance.
replace_once(
    "readwisereader.koplugin/constants.lua",
    '    VERSION = "1.3.0-alpha.1",\n',
    '    VERSION = "1.3.0-rc.1",\n',
)

# Changelog: concise product/engineering contract for the candidate.
replace_once(
    "CHANGELOG.md",
    "## [Unreleased]\n",
    "## [Unreleased]\n\n"
    "### Added — 1.3.0-rc.1 Reader metadata editing candidate\n\n"
    "- Edit Reader document tags and document notes from a Reader-managed KOReader document.\n"
    "- Add/remove Reader tags on existing linked highlights and attach tags to a newly-created KOReader highlight before its first remote create.\n"
    "- Clear document notes and linked highlight notes without inventing placeholder text.\n"
    "- Durable SQLite metadata mutation queue integrated into ordinary `Sync now`, gated by the existing read-only Readwise reachability/auth preflight.\n"
    "- Conservative note conflict handling: a Reader-side note change after the Kindle baseline blocks overwrite until the user explicitly keeps Kindle or Reader.\n"
    "- Delta-based tag reconciliation preserves unrelated concurrent Reader tag additions/removals.\n"
    "- Successful document-tag changes project back to KOReader custom `keywords`/Bookshelf Genres on the same local path.\n"
    "- Sync summary counters for metadata queue processing, updates, reconciliation, conflicts, blocked/deferred/auth-wait states and remaining work.\n\n"
    "### Safety — 1.3.0-rc.1\n\n"
    "- Metadata PATCHes never run before the remote preflight; offline/retryable work remains durable.\n"
    "- Highlight metadata mutation requires the durable Reader child ID and expected parent/category identity.\n"
    "- Ambiguous write outcomes are reconciled by a fresh GET before another PATCH; no create/deduplication guarantees from v1.2 are weakened.\n"
    "- A metadata mutation result never overwrites newer metadata already produced by the same run's document-sync phase.\n"
    "- `v1.3.0` final tag/merge remains blocked on the consolidated PW3 physical acceptance matrix.\n",
)

spec_marker = "# V1.3 addendum — Reader metadata editing"
spec_body = r'''# V1.3 addendum — Reader metadata editing

Status: **implementation/off-device validation complete; final PW3 acceptance pending**.

This is a post-V1 extension and does not retroactively change the original V1 non-goal of a full Reader taxonomic-management UI. V1.3 deliberately exposes only the bounded metadata needed for the Kindle reading workflow:

- Reader document tags;
- Reader document note;
- Reader highlight tags;
- existing linked-highlight note editing/clearing through the already-proven annotation path.

## Identity and mutation authority

- A document metadata edit is keyed only by durable `reader_document_id`.
- An existing-highlight metadata edit requires durable `reader_highlight_document_id`, `category=highlight`, and the expected `parent_id`; text/title heuristics are forbidden.
- A newly-created local highlight may receive Reader tags before first Sync. KOReader creates/persists the real local annotation first; tag intent is then stored by that durable local annotation identity and is included in the existing Reader create POST. No synthetic highlight ID is invented.
- Reader v3 `PATCH /api/v3/update/<id>/` is the metadata write path for document notes/tags and linked-highlight tags. Existing v1.2 note interoperability rules remain authoritative for linked-highlight note edits.

## Durable queue and offline rules

- UI edits never directly PATCH Reader. They produce durable SQLite intent.
- Ordinary `Sync now` processes metadata intent only after the existing read-only Readwise auth/reachability preflight succeeds.
- Offline/auth/rate-limit/retryable failures retain recoverable queue state and do not advance a metadata intent as successful.
- A PATCH timeout/ambiguous response is followed by a fresh Reader GET on the next eligible attempt. If the desired state is already present, reconcile without a second PATCH.
- 404/identity mismatch/unsupported client state blocks safely rather than guessing.

## Conflict semantics

### Notes

Document notes use a three-way baseline:
- if Reader still equals the captured baseline, Kindle may apply the desired note;
- if Reader already equals the desired Kindle note, reconcile without another PATCH;
- if Reader differs from both baseline and desired note, block as a conflict and overwrite neither side.

The UI then offers explicit resolution. **Keep Kindle** rebases the same desired note on the freshly-cached Reader value and requires a later `Sync now`; **Use Reader version** cancels the local queued edit. Clearing a note is represented by the empty string, not a placeholder.

### Tags

Tags use delta reconciliation, not whole-baseline overwrite. The queued intent stores the additions/removals relative to the Kindle baseline, then applies that delta to the freshly-read Reader tag set. This preserves unrelated concurrent remote changes while honoring the user's explicit add/remove operations. Tag ordering is normalized deterministically and duplicates/empty values are removed.

## KOReader / Bookshelf projection

After a successful document-tag mutation, the verified Reader response updates durable document metadata and schedules parent-process KOReader custom-metadata projection on the same managed local path. Tags continue to map to newline-separated `keywords` consumed by Bookshelf Genres. If normal document sync has already scheduled newer metadata for that path during the same run, that newer projection wins.

## UI contract

- Main Reader menu exposes **Reader metadata** only for the current Reader-managed document.
- Document metadata surface provides Document tags and Document note.
- KOReader highlight dialog gains **Reader tags** for the current Reader-managed document.
- Tag picker supports selecting existing Reader tags, searching/filtering the loaded tag list, and adding a new free-text tag name.
- No background sync is introduced; writes still require manual `Sync now`.

## Gate M10 — final physical acceptance

One consolidated PW3 session must cover document tag add/remove, document note create/edit/clear plus one conflict resolution, existing-highlight tag add/remove, new-highlight tag intent on first create, linked-highlight note clear, offline/restart persistence, reconnect delivery, no-op duplicate safety, Bookshelf Genre projection, and regression preservation of existing document progress/annotations. `v1.3.0` must not be tagged or merged as final until that matrix passes.
'''
append_once("IMPLEMENTATION_SPEC.md", spec_marker, spec_body)

plan_marker = "## Post-V1 milestone — v1.3 Reader metadata editing"
plan_body = r'''## Post-V1 milestone — v1.3 Reader metadata editing

Goal: let the Kindle perform the small organization/edit operations that are useful while reading without turning KOReader into a second full Reader client.

In scope:
- edit Reader document tags;
- edit/clear Reader document note;
- add/remove Reader tags on highlights;
- attach tags to a new Kindle highlight before its first Reader create;
- preserve the existing linked-highlight note editing path, including clearing;
- durable offline queue + manual `Sync now` only;
- reflect successful document-tag edits in KOReader/Bookshelf metadata.

Out of scope:
- arbitrary Reader document fields/title/body editing;
- deleting Reader tag definitions globally;
- background sync;
- heuristic highlight identity;
- changing the existing Reader ↔ KOReader reading-position scope.

Release rule: `1.3.0-rc.1` is the single physical-test candidate. Final `v1.3.0` is authorized only after the consolidated PW3 acceptance matrix in `docs/DEVICE_TESTS.md` passes.
'''
append_once("PLAN.md", plan_marker, plan_body)

tests_marker = "## V1.3 / Gate M10 — consolidated Reader metadata acceptance"
tests_body = r'''## V1.3 / Gate M10 — consolidated Reader metadata acceptance

Target: the existing PW3 / KOReader v2026.07.1 / Bookshelf v5.1.4, preserving the current Reader database, documents and sidecars. Install **1.3.0-rc.1** over the existing plugin; do not delete the SQLite DB or Reader documents.

This is intentionally one final device session rather than incremental developer gates.

1. **Baseline/regression:** open one already-managed EPUB/HTML and one already-managed PDF if available. Confirm prior reading position and existing highlights/notes are intact. Run one online `Sync now`; require no crash, no duplicate documents/highlights, and zero unexpected annotation/metadata errors.
2. **Document tags:** from the managed document, open `Readwise Reader → Reader metadata → Document tags`. Add one distinctive new tag and select one pre-existing Reader tag; save, then `Sync now`. Verify both appear on the same document in Reader and in KOReader/Bookshelf Genres. Remove only the distinctive tag on Kindle, sync again, and verify it disappears while the unrelated/pre-existing tag remains.
3. **Document note:** create a distinctive document note on Kindle, sync and verify it in Reader. Edit it on Kindle, sync and verify the replacement. Clear it on Kindle, sync and verify Reader has an empty/cleared note rather than placeholder text.
4. **Document-note conflict:** establish a baseline note, then queue a different Kindle edit and independently change the same Reader note before syncing. `Sync now` must report a metadata note conflict and must not overwrite either side. Reopen Reader metadata, choose **Keep Kindle**, run `Sync now`, and verify that exact Kindle text becomes the Reader note. No duplicate document may be created.
5. **Existing highlight tags:** on an already-linked highlight, add a distinctive Reader tag from the highlight dialog, sync and verify it on that exact Reader highlight. Remove it on Kindle, sync and verify removal without changing highlight text/note or creating a second highlight.
6. **New highlight + tags before first remote create:** select a unique sentence that has not been highlighted before, choose **Reader tags**, select/add a distinctive tag, then add a KOReader note to that newly-created local highlight before syncing. Run `Sync now`. In Reader require exactly one new child highlight under the correct parent, with exact highlighted text, note, and tag. Run a second unchanged sync and require still exactly one remote highlight.
7. **Linked-highlight note clear:** on a linked highlight with a non-empty note, clear the KOReader note and sync. Verify the same Reader child remains and its note is cleared; the highlight itself must not disappear or duplicate.
8. **Offline durability + restart:** disconnect internet outside the plugin. Queue at least one document metadata edit and one highlight-tag edit, then run `Sync now`. Require zero metadata remote writes processed successfully and queued/waiting work to remain. Fully exit/reopen KOReader while still offline; confirm the document, progress and annotations remain intact. Reconnect Wi-Fi, run `Sync now`, and verify each queued edit reaches Reader exactly once. Run one more no-op sync and verify no duplicates/repeated mutations.
9. **Final Bookshelf/regression check:** confirm the final Reader document tag set is reflected in Bookshelf Genres, Reader location Collection membership is unchanged unless deliberately changed elsewhere, prior reading position is preserved, and pre-existing highlights/notes remain present.

Pass condition: every item above passes in the same candidate build with no crash/freeze, no identity mismatch, no duplicate remote highlight/document, no lost sidecar/progress, and no unexpected queue items left waiting after the final online no-op sync. Only then may the branch be merged/tagged as final `v1.3.0`.
'''
append_once("docs/DEVICE_TESTS.md", tests_marker, tests_body)

status_marker = "## 2026-10-05/06 — v1.3 Reader metadata editing off-device complete; Gate M10 only blocker"
run_id = os.environ.get("GITHUB_RUN_ID", "unknown")
trigger_sha = os.environ.get("GITHUB_SHA", "unknown")
status_body = f'''## 2026-10-05/06 — v1.3 Reader metadata editing off-device complete; Gate M10 only blocker

- **Branch:** `feature/reader-metadata-editing-v1.3.0`.
- **Candidate:** `1.3.0-rc.1`; final `v1.3.0` is **not authorized yet**.
- **Validated implementation entering cleanup:** `6c754b1922637b45f418ac820e9c07be16aa127a` (`Integrate Reader metadata queue into Sync now`).
- **Validated finalizer run:** GitHub Actions run `37397537080` passed source normalization, v1.3 integration, `./scripts/dev-check.sh`, the full Lua unit suite, installable ZIP build and package-layout verification before committing the integrated worker changes.
- **Cleanup workflow trigger:** `{trigger_sha}` / run `{run_id}`; this session removes all temporary `.automation` payloads and `.github/workflows/apply-v1.3-metadata.yml` after re-running the complete validation suite.

### Implemented
- document tags and document-note edit/clear UI for the current Reader-managed document;
- highlight tag add/remove UI for linked highlights;
- tags on a brand-new KOReader highlight: KOReader persists the real annotation first, then stores tag intent by durable local annotation ID so the first Reader create carries the tags;
- schema v4 with `remote_notes`, durable document/highlight tag state, and annotation tag intent;
- generic durable metadata queue using the existing queue state machine;
- metadata processing as an explicit `Sync now` worker phase **after** the read-only remote preflight;
- verified Reader GET-before-write/reconcile-after-ambiguous-result behavior;
- document-note three-way conflicts with explicit Keep Kindle / Use Reader resolution;
- tag delta merge preserving unrelated concurrent Reader adds/removes;
- successful document-tag mutation updates the same local document's custom `keywords`, keeping Bookshelf Genres coherent;
- document-sync metadata already scheduled later in the same run has precedence over an older metadata-mutation projection;
- Sync report exposes metadata processed/update/reconciled/conflict/blocked/deferred/auth/error/waiting counters;
- existing v1.2 annotation-create, dedupe, deletion and Reader→KOReader import contracts remain unchanged.

### Automated evidence
- UI module was split into `ui/metadata.lua`, `ui/metadata_document.lua`, `ui/metadata_highlight.lua`, and `ui/metadata_tags.lua` after the original monolithic staged file contained invalid/corrupted bytes; the modular replacement passed full CI.
- deterministic coverage includes document note create/edit/clear, note conflict + explicit rebase/discard semantics, tag add/remove/no-op reconciliation, preservation of concurrent remote tag changes, linked-highlight identity guard, new-highlight pending tags, timeout-after-write reconciliation, timeout-without-write retry, auth wait, rate-limit defer, missing remote target block, schema v4 fresh DB, worker metrics, Bookshelf projection and newer-document-sync precedence.
- the first modular UI correction passed workflow run `37396386837` end-to-end.
- the integrated metadata-worker/hardening finalizer passed workflow run `37397537080` end-to-end.

### Safety decisions
- UI never performs a Reader mutation directly; it only queues intent.
- no guessed highlight identity, no blind create retry, and no destructive default were introduced.
- metadata writes do not bypass the PW3 remote reachability/auth authority established in Gate 13.
- note conflicts fail closed; tag conflicts use explicit delta merge rather than whole-baseline overwrite.
- temporary patch/application infrastructure must not remain in the release branch.

### Only remaining blocker
**Gate M10 physical acceptance on the target PW3.** The exact one-session matrix is now canonical in `docs/DEVICE_TESTS.md` and covers document tags, document note create/edit/clear/conflict, existing + new highlight tags, highlight-note clear, offline/restart/reconnect persistence, Bookshelf projection, no-op idempotency and preservation of prior progress/annotations.

Do not merge/tag final `v1.3.0` until M10 passes. No further off-device implementation blocker is known after the cleanup CI is green.
'''
append_once("STATUS.md", status_marker, status_body)

# Remove all staging/application infrastructure from the candidate itself.
workflow = Path(".github/workflows/apply-v1.3-metadata.yml")
if workflow.exists():
    workflow.unlink()
shutil.rmtree(".automation", ignore_errors=True)

print("v1.3 candidate finalized; temporary automation removed")
