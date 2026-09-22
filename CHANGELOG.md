# Changelog

All notable project changes are recorded here.

## [Unreleased]

### Added

- Canonical V1 plan, implementation specification and resumable status ledger.
- AGPL-3.0 licensing and upstream provenance notice.
- Repository/bootstrap documentation and Gate 0 device validation.
- Local Readwise access-token configuration through KOReader `LuaSettings`.
- Password-masked token entry with replace/clear behavior.
- Readwise auth validation using the documented `GET /api/v2/auth/` contract.
- HTTP error classification for auth, offline/network, timeout, TLS, rate limit, client and server failures.
- Unit tests for configuration, auth request construction, token/log redaction behavior and HTTP error classification.
- SQLite schema v1 for documents, annotation links, durable queue and sync metadata.
- Transactional schema migration foundation with rollback and future migration backup support.
- Storage repositories keyed by stable Reader/local IDs, with queue idempotency and stale in-flight recovery.
- Real-SQLite CI coverage for schema constraints, rollback and storage repository invariants.
- Reader v3 metadata LIST client with validated query encoding and response parsing.
- Full cursor pagination with repeated-cursor/empty-loop guards and ID deduplication.
- Metadata-only Gate 2 full-library scanner with location/category/child/duplicate counts.
- Proactive Reader LIST pacing at 3.1 seconds between requests for the documented 20/minute limit.
- Bounded 429 retry handling that honors `Retry-After` and never advances a failed page cursor.
- Cancellable Gate 2 scanning via KOReader's subprocess trap pattern so long metadata/rate-limit waits remain dismissable.
- Unit coverage for 21-page pacing, cancellation, cursor loops, deduplication and rate-limit recovery.

## [0.0.2] - 2026-09-22

Config/auth build validated on the target PW3. Gate 1 passed for masked credential handling, valid and invalid authentication, offline detection without Wi-Fi control, and credential clearing. It does not sync Reader library content or annotations yet.

## [0.0.1] - 2026-09-22

Bootstrap plugin shell validated by Gate 0 on the target PW3 / KOReader 2025.04.
