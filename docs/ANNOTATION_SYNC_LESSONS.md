# KOReader ↔ Readwise Reader annotation sync — production lessons

> **Purpose:** durable engineering memory for future KOReader/Readwise work.
>
> Read this together with `IMPLEMENTATION_SPEC.md`, `STATUS.md`, and `docs/API_INTEROP.md` before changing annotation identity, note sync, conflict handling, retry logic, or deletion.
>
> Evidence baseline: Kindle PW3 / KOReader v2026.07.1, physical Gates 7–12, 2026-09-23.

## 1. Local annotation source of truth

- KOReader sidecar annotations are the local source of truth.
- Do not use `My Clippings.txt`.
- For physical tests, close/reopen the document before sync when a sidecar flush matters.
- SQLite `annotation_links` is the durable bridge state: local annotation id, Reader child id, optional numeric Readwise v2 id, last-synced text/note hashes, tombstone and sync state.

## 2. Remote identity: non-destructive update vs destructive delete are different

For **note update**, production identity is:

```text
durable Reader child id
AND same original Reader parent_id
AND category == highlight
```

Reader `saved_using/source` is useful evidence but **must not be mandatory for note updates**:
- pre-Gate-10 children may use the generic marker `KOReader Readwise Reader`;
- production Reader LIST may omit or normalize the newer per-annotation marker;
- Gate 12 physically proved that a correct durable child can be linked while marker verification is zero.

For **remote DELETE**, keep the stronger destructive rule:
- exact durable Reader child id;
- same parent;
- `category=highlight`;
- exact newer per-annotation KOReader ownership marker.

Do not let the legacy generic marker or a missing marker authorize destructive deletion.

## 3. Reader v3 ↔ Readwise v2 mapping

The deterministic bridge physically proved in Gate 8 and reused in Gate 12 is:

```text
Readwise v2 highlight.external_id == Reader v3 highlight child id
```

Rules:
- persist the numeric v2 highlight id after an exact `external_id` match;
- never fall back to text/note heuristics for production mutation identity;
- zero matches blocks;
- multiple matches block;
- a stored v2 id must still map back to the same Reader child `external_id`.

## 4. Remote note truth and conflict detection

Do **not** use Reader v3 LIST `notes` as the sole remote conflict baseline in production.

Gate 12 showed that Reader v3 can return a stale/inconsistent note even when child identity is correct. For the production three-way merge:
- local = KOReader sidecar note;
- baseline = durable `last_synced_note`;
- remote = exact mapped Readwise v2 highlight `note`.

Conflict rule:
- local changed + remote unchanged from baseline → local may update;
- local unchanged + remote changed → do not overwrite remote;
- local changed + remote changed to a different value → conflict, overwrite neither side;
- local and remote already equal → reconcile without another v2 PATCH.

## 5. Note comparison normalization

Compare note semantics conservatively, not raw bytes.

For conflict/equality comparison only:
- CRLF/CR → LF;
- trim trailing spaces/tabs per line;
- trim outer whitespace.

Do **not** rewrite the user's payload using this normalization. Preserve the exact local note text, including Markdown, `[[wikilinks]]`, hashtags, and intentional internal newlines.

## 6. A successful API response is not end-to-end success

This is the most important Gate 12 lesson.

A successful Readwise v2 PATCH response does **not** prove that Reader UI/state has updated.

Production success requires:
1. exact remote identity verified;
2. v2 conflict check passed;
3. v2 PATCH accepted when needed;
4. poll the exact Reader v3 child;
5. Reader v3 child must reflect the expected note;
6. if v2 already has the desired note but Reader v3 is stale, issue a v3 repair PATCH to that already-validated child;
7. poll/verify Reader again;
8. **only then** advance `last_synced_note` / hashes and report success.

This also provides recovery for a partial/premature state:
- if local + durable baseline + v2 already agree but Reader v3 is stale, repair Reader without repeating the v2 write.

## 7. Gate 12 failure sequence — what not to repeat

### 0.1.26
Failure: old linked highlights rejected because only the newer per-annotation source marker was accepted.

Lesson: maintain legacy compatibility for non-destructive operations when durable child/parent/category identity is exact.

### 0.1.27
Failure: newly-created linked highlights could still be rejected because Reader did not reliably expose the expected source marker.

Lesson: source marker is supplementary for note update, not primary identity.

### 0.1.28
Failure: Reader v3 `notes` produced false conflicts.

Lesson: use exact Readwise v2 mapping for production remote-note conflict truth.

### 0.1.29
Failure: v2 mapping was correct, but raw note string comparison still produced false conflicts.

Lesson: normalize only invisible newline/whitespace representation for equality decisions.

### 0.1.30
Failure: v2 PATCH returned the new note and the plugin reported success, but Reader still displayed the old note.

Lesson: never advance durable sync baseline on API acknowledgement alone; verify the user-visible Reader representation.

### 0.1.31 — physical note-update PASS
Observed on the target PW3:
- current-document highlights scanned: 2;
- highlights created: 0;
- highlights already linked: 2;
- notes updated: 1;
- note updates reconciled: 1;
- note conflicts blocked: 0;
- annotation mutations blocked safely: 0;
- local highlight deletions detected: 0;
- remote highlight deletions: 0;
- Readwise v2 remote-note reads: 2;
- Readwise v2 note updates: 1;
- Reader note verification reads: 6;
- Reader propagation misses: 1;
- Reader v3 repair PATCHes: 2;
- Reader note repairs completed: 2;
- annotation remote errors: 0;
- user visually confirmed the edited note is now correct in Reader.

Conclusion: the production note-update pipeline must be **v2 conflict/update + v3 end-to-end verification/repair**, not a single-API assumption.

## 8. MUST / DO NOT checklist for future annotation work

### MUST
- inspect current repository/spec/status before implementation;
- use durable IDs and explicit parent identity;
- preserve sidecar/local annotations;
- use exact v2 `external_id` mapping where v2 interoperability is needed;
- verify downstream Reader state after cross-API mutation;
- keep conflict handling conservative;
- make retries/recovery idempotent;
- add diagnostic counters that identify which API/path actually ran;
- test on the real PW3 before closing a gate.

### DO NOT
- do not trust chat history over repository state;
- do not infer annotation identity from text/note similarity;
- do not require Reader `source` for non-destructive note update;
- do not use Reader v3 `notes` alone as production conflict truth;
- do not treat a v2 PATCH response as Reader propagation proof;
- do not advance `last_synced_note` before Reader visibility is verified;
- do not silently last-writer-wins a conflict;
- do not weaken destructive DELETE identity to text/note heuristics; use exact cross-API Reader child + Readwise v2 external-id identity;
- do not blindly retry ambiguous remote creates.

## 9. Apply these lessons beyond this plugin

Any future KOReader ↔ Readwise integration (including Quartzo/Obsidian-related annotation workflows) should start from these invariants rather than re-deriving API behavior from documentation alone. Gate 8 disposable spikes are useful, but production behavior must still be verified against real linked documents because Reader v3 and Readwise v2 can differ in propagation timing and representation.


## 10. Physical conflict handling evidence

Gate 12B on build 0.1.31 physically proved the intended three-way conflict behavior:
- local note diverged from the durable baseline;
- exact mapped Readwise v2 remote note also diverged to a different value;
- the plugin reported exactly one conflict;
- no v2 note PATCH ran;
- no Reader repair PATCH ran;
- Reader preserved the remote value;
- KOReader preserved the local value;
- no remote error occurred.

Future work must preserve this invariant: **a true local+remote divergence blocks mutation and preserves both sides; never convert this path to last-writer-wins.**


## 11. Physical deletion-OFF invariant

Gate 12C physically proved on build 0.1.31:
- a local KOReader highlight disappearance is detected as a tombstone;
- with deletion propagation OFF, no Reader DELETE occurs;
- the remote target remains;
- an unrelated control highlight remains;
- the sync reports the deletion as retained remotely, with no mutation block/error.

Future implementations must preserve this default-safe invariant: **local deletion alone must never imply remote deletion**. Destructive propagation requires an explicit opt-in plus the stronger remote identity contract.


## 12. Destructive identity lesson from Gate 12D attempt 1

Build 0.1.31 physically proved that Reader `source/saved_using` is not reliable enough to be a mandatory destructive identity field either: the legitimate tombstoned target was detected, but DELETE was blocked because the marker was absent/inconsistent.

The correction in 0.1.32 does **not** remove destructive identity protection. It replaces a weak/unreliable field with a stronger two-representation proof:

```text
Reader child id == durable linked child id
AND Reader parent_id == expected document
AND Reader category == highlight
AND Readwise v2 external_id == Reader child id
```

Rules:
- v2 zero-match blocks;
- v2 ambiguity blocks;
- stored v2 id must still map back to the exact Reader child;
- parent/category mismatch blocks;
- DELETE acknowledgement is not durable success;
- poll the exact Reader child and clear durable link state only after Reader reports it gone;
- never substitute text/note similarity for destructive identity.

This is the destructive counterpart to the note-sync lesson: **cross-API agreement is stronger than assuming one API representation contains every field reliably.**


## 13. Physical deliberate-delete invariant

Gate 12D physically passed on build 0.1.32:
- the explicitly tombstoned target disappeared from Reader;
- the control highlight remained;
- deletion propagation was turned OFF again;
- a follow-up OFF sync had no pending local deletion, no remote deletion, no mutation block, and no remote error.

This closes the destructive identity lesson:
- do not trust Reader `source/saved_using` as mandatory production identity;
- do require exact durable Reader child + parent/category and exact Readwise v2 `external_id` mapping;
- do verify remote disappearance before clearing durable state;
- do keep deletion opt-in/default OFF;
- do verify an unrelated control survives.

Future destructive annotation work must preserve both halves of Gate 12: safe retention while OFF and exact-target deletion while deliberately ON.
