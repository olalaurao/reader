# Gate 11 — Readwise Official → Obsidian

Date prepared: 2026-09-23  
Project phase: M  
Kindle plugin build: 0.1.25 (unchanged from Gate 10)

## Purpose

Prove the complete annotation path:

```text
KOReader highlight/note
→ Reader highlight child
→ Readwise
→ Readwise Official Obsidian export
→ Obsidian Markdown
→ [[Foucault]] internal link
```

Gate 10 already proved the path through Reader and the exact note payload. Gate 11 must not modify the KOReader plugin unless evidence shows that payload was wrong upstream.

## Current official contract checked

Sources reviewed on 2026-09-23:

- https://docs.readwise.io/readwise/docs/exporting-highlights/obsidian
- https://docs.readwise.io/readwise/docs/exporting-highlights
- https://docs.readwise.io/reader/docs/faqs/exporting

Observed/documented behavior:

1. The supported Obsidian path is the **Readwise Official** community plugin.
2. A manual sync can be triggered with `Readwise Official: Sync your data now`.
3. The documented default Highlight template includes attached notes through `{{ highlight_note }}`.
4. New highlights for an already-exported document are appended to its page.
5. The integration is append-only and does not overwrite user edits.
6. Edits or notes/tags added to a highlight that was already exported do not automatically update the existing Obsidian block.
7. Readwise documents a refresh/re-export workflow for cases where a historical export must be regenerated.

## Gate fixture

Use the Gate 10 highlight already created from KOReader.

Reader note:

```text
ver [[Foucault]]
#pesquisar
```

Do not create a second fixture unless the original was intentionally removed.

## Real-template rule

The first observation must preserve the user's current real export configuration.

Before syncing:
- inspect the active Readwise Obsidian **Highlight** template;
- record whether it emits `highlight_note`;
- do not silently replace the template with the documented default.

If a custom template omits `highlight_note`, the downstream note cannot appear by design. Record that configuration limitation. It is not a failure of the KOReader → Reader implementation.

## PASS criteria

All of the following:
- active real template exports highlight notes;
- correct Reader article maps to the correct Obsidian file;
- Gate 10 highlight appears;
- note appears;
- source Markdown contains literal `[[Foucault]]`;
- the wikilink is not escaped/backticked/code-wrapped;
- `#pesquisar` is preserved;
- Obsidian recognizes `[[Foucault]]` as a normal internal link.

An unresolved internal link is still a valid Obsidian wikilink if no note named `Foucault` exists. If that note exists, clicking should open it.

## Append-only limitation

Gate 11 proves initial export only.

The official integration currently does not automatically rewrite a previously-exported highlight when its Readwise note/text/tags later change. For a historical refresh, use Readwise's documented refresh/re-export procedure rather than expecting the next ordinary Obsidian sync to mutate the existing block.

This matters for Phase N:
- Gate 12 may prove Kindle note edit → Reader update;
- that does not imply automatic mutation of the already-exported Obsidian block;
- the V1 documentation must keep those two contracts separate.

## Result string

`template exporta nota: sim/não / artigo certo: sim/não / highlight apareceu: sim/não / nota apareceu: sim/não / markdown tem [[Foucault]] literal: sim/não / #pesquisar preservado: sim/não / link funciona no Obsidian: sim/não`

## Recorded result — 2026-09-23

**PASS** using the user's real Readwise Official export configuration and real Obsidian vault.

- template exported highlight notes;
- correct article/highlight exported;
- note appeared;
- literal `[[Foucault]]` remained in Markdown;
- `#pesquisar` remained intact;
- Obsidian recognized the wikilink normally.

The append-only limitation remains documented: later edits to already-exported highlights are not expected to rewrite the existing Obsidian block on ordinary sync.