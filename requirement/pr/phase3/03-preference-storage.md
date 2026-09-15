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
- Add explicit rollback for development and preflight SQL/startup checks that
  fail closed when required objects/constraints are absent.

## Tests and gates

- Migration apply/reapply/rollback/preflight and missing-object startup failure.
- Logical uniqueness and two-customer isolation under concurrency.
- Stable pagination indexes and operation-retention cleanup.
- Repository error redaction and transaction rollback.

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
