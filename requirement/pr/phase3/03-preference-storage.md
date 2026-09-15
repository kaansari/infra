# Phase 3 PR 03: Preference storage foundation

Repository: `services-repo`  
Depends on: PR 02

## Objective

Add the canonical PostgreSQL schema, repositories, curated definition seed, and
startup preflight required by the preference service. Do not expose RPC behavior
until the schema is applied and verified.

## Schema

Create explicit ordered migrations for:

```text
preference_definitions
customer_preferences
customer_preference_profiles
preference_operations
customer_preference_history
```

Enforce customer foreign keys, positive versions, normalized logical uniqueness,
typed value/scope checks, bounded operation states, server timestamps, stable
customer-first read indexes, `(customer_id,idempotency_key)` uniqueness, and
retention/expiry indexes. Use the existing database; do not add another Render
database.

Store typed canonical values, not arbitrary request JSON. Any JSONB envelope is
strictly versioned, size-bounded, and validated at every write/read boundary.
No OAuth tokens, prompts, raw tool payloads, or secrets enter these tables.

## Repositories and seed

- Add preference/definition/profile/operation/history repository interfaces and
  PostgreSQL implementations with customer predicates on every owned query.
- Provide transactions and documented lock order for profile -> logical
  preference -> operation/history.
- Seed a small reviewed definition catalog idempotently with stable keys and
  versions. Application startup must not overwrite operator-reviewed changes.
- Seed only reviewed typed TXSE Intelligence preferences (signal family,
  explanation detail, default window, severity, units). Store bounded opaque
  references only; never FEED events, books, signals, portfolios, positions,
  entitlements, suitability, or reconstructed/raw Exchange Data.
- Add explicit rollback for development and preflight SQL/startup checks that
  fail closed when required objects/constraints are absent.

## Tests and gates

- Migration apply/reapply/rollback/preflight and missing-object startup failure.
- Logical uniqueness and two-customer isolation under concurrency.
- Stable pagination indexes and operation-retention cleanup.
- Repository error redaction and transaction rollback.
- Constraints reject customer mutation of consumer-domain metadata and any
  attempted market environment/entitlement/classification authority.

```text
go test ./services/ceerat-user-service/preferences/...
go test ./services/ceerat-user-service/...
go build ./services/ceerat-user-service/...
ceerat-builder check drift --output json
```

Apply migration and preflight before deploying dependent service code. Record
schema version without recording customer preference contents.

## Out of scope

RPC handlers, MCP, extra database, ORM-only production migration, arbitrary
JSON, embeddings/search service, browser/REST/legacy paths.

## Implementation record (2026-09-14)

Implemented the five-table preference schema in the existing user-service
PostgreSQL database with explicit idempotent forward migration, development
rollback, committed SQL/startup preflight, customer foreign keys, closed typed
value/scope constraints, logical uniqueness, positive versions, customer-first
pagination/context indexes, durable idempotency/reconciliation records, and
history/retention indexes. Preference models were deliberately excluded from
`AutoMigrate`; production now fails closed before dependent behavior if the
reviewed migration is absent.

Added reviewed non-overwriting definitions, including bounded
`txse_intelligence` signal-family, explanation, window, severity, and units
settings. No market data, environment, entitlement, health, formula, position,
suitability, warning suppression, or trading authority is stored. Repository
interfaces/implementation repeat customer predicates, enforce bounds, redact
dependency errors, and document profile -> preference -> operation/history
locking.

Preference package, full user-service tests, and build pass. The local Go 1.26
race runtime is unavailable (`runtime/race: package testmain: cannot find
package`), so the race gate must be rerun in CI/a supported toolchain. The PostgreSQL
lifecycle harness covers missing-schema failure, apply/reapply, preflight,
logical uniqueness, two-customer isolation, invalid scope rejection, rollback,
and post-rollback failure when `CEERAT_TEST_DATABASE_URL` is supplied; it was
skipped locally because that variable was not set. No RPC handler or tool was
registered.

Operator deployment record: `20260914_phase3_preferences.sql` was applied to
the target database before this PR was pushed. The production service preflight
therefore remains the authoritative deployment verification.
