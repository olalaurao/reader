# Notices and provenance

This project is licensed under the GNU Affero General Public License, version 3 (AGPL-3.0). See `LICENSE`.

## Community implementation references

The implementation plan deliberately studies the prior KOReader ↔ Readwise Reader community work before reusing any code:

- `Endle/readwisereader` — upstream community implementation, AGPL-3.0.
- `tomtom800/readwisereader` — AGPL-3.0 fork that was archived in 2026.
- `koreader/contrib/readwisereader.koplugin` — contributed snapshot/reference, also distributed under AGPL-3.0.

Reference URLs:

- https://github.com/Endle/readwisereader
- https://github.com/tomtom800/readwisereader
- https://github.com/koreader/contrib/tree/main/readwisereader.koplugin

As of the Phase A bootstrap, the minimal plugin shell in this repository is newly written against the KOReader v2025.04 plugin loader and hello-plugin pattern; the old monolithic implementation has not been copied into the bootstrap shell.

If later changes reuse or adapt source code from any upstream implementation, preserve all copyright/license notices required by that source and record the reuse here or in the affected source file.
