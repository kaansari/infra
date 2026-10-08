# Preference write service implementation plan

> **For agentic workers:** Execute inline using superpowers:executing-plans and TDD; one fresh read-only final review.

**Goal:** Implement PR05's five private preview, confirmed mutation and reconciliation RPCs in the existing user service.
**Architecture:** Read-only previews validate current definitions and normalized identity. Expiring MAC fingerprints bind ownership, idempotency, input, complete before/after and catalog snapshots. Confirmation serializes on the customer profile, locks logical preference then definition/operation, and atomically writes preference/profile, digest-only history and an encrypted replay result. Reconciliation is self-scoped and never retries mutation.
**Tech stack:** Existing Go/GORM/pgx/protobuf/gRPC/PostgreSQL, standard-library HMAC/AES-GCM, existing configured 32-byte secret; no new dependency.
**Requirement:** requirement/pr/phase3/05-preference-write-service.md.

## Rulings

- Ruling: Extend the existing module/schema/contracts rather than create another service. The supplied PR is the authorized spec and implementation scope.
- Ruling: Add an immutable forward migration for bounded encrypted result bytes, plus rollback/preflight. Existing applied migrations stay unchanged. Full replay cannot depend on a mutable/deleted preference row.
- Ruling: Fingerprint is 16 hex characters of expiry plus 48 of HMAC-SHA256; it fits the existing 64-hex contract and binds full preview data. No preview is persisted. Validity is 15 minutes.
- Ruling: Derive separate keyed purposes for preview fingerprints, content/identity digests and creation IDs from the configured secret. Idempotency values and history contents are never stored raw. AEAD result data binds customer/operation and is retained 30 days; keys must stay available for that retention window.
- Ruling: Updates require ID, unchanged normalized key/scope, and current preference/profile/catalog versions. Create matching an existing logical identity conflicts rather than silently updating.
- Ruling: New custom writes use closed personal hint identities, labels, values and global scopes; arbitrary free-form data/encoded records cannot be safely distinguished from Exchange Data. Legacy custom read/delete remains available, and expanding writes requires review.
- Ruling: Synchronous atomic execution exposes completed durable results. Rejected confirmations may persist a bounded failed operation without active preference/history changes. Legacy pending/unknown/failed rows remain safely reconcilable. Missing records report outcome_unknown, never proof of failure. Deadline after dispatch instructs reconciliation, never retry.
- Ruling: Cleanup reuses bounded SKIP LOCKED history-before-operation routines. No new scheduler or production deployment; document trusted invocation and retention.

## Tasks

- [x] Write failing PG-backed canonical/custom preview/create/update/delete/replay/restart tests and schema preflight/restore tests.
- [x] Add replay migration/preflight and encrypted result codec; fingerprint and normalized domain planning/policy.
- [x] Add bounded authenticated write transaction and five RPC handlers; atomic history/profile/operations; safe error/audit/status mapping.
- [x] Test stale/tampered/expired/catalog state, invalid inputs, hashed persistence, concurrency, crash/rollback/deadline and retention; real JWT/RBAC ownership.
- [x] Update inventory, runtime schema preflight, API/security/logging/testing/module docs and requirement acceptance.
- [x] Run full PG tests/race/build, vendor build and builder checks; request final read-only review and fix findings.
- [x] Record actual verified evidence and scoped local commits. No push/deployment.

Ruling: Independent review proved keyword-only custom filtering admitted unnamed quotes and warning-control booleans. Replaced it with seven documented personal schemas and value-level regression tests; broader custom data is intentionally rejected rather than stored.

Evidence: PG-backed preference race tests, full service tests/build and vendor build/race passed; contract tests/build passed. Builder RBAC/drift/apps returned ok with no issues; verification returned checklist. Local checksum migration 17 and all preflights passed. Review P1 fixed with closed personal schemas; P2 fixed by valid-label value regressions. Scoped commits follow; no hosted deployment.
