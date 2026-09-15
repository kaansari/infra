# Phase 3 PR 03B: Deterministic database lifecycle

Status: implemented locally

## Objective

Make a new database, routine deployment, and disaster restore deterministic
before preference RPC behavior is added.

## Delivered

- Production service startup no longer executes `AutoMigrate`.
- `dbbootstrap` creates the pinned base model schema and refuses a non-empty
  schema; it is a transitional empty-database bootstrap, not normal migration.
- The strict migration runner uses `ON_ERROR_STOP`, a database lease, ordered
  files, a `schema_migrations` ledger, SHA-256 checksums, and pending-only
  execution. Applied files are immutable.
- One preflight runner discovers every committed preflight, including base,
  commerce, order-line, and preference checks.
- Make targets provide bootstrap, migrate, preflight, status, and verify flows.
- `docs/database-create-restore.md` defines clean creation, existing-database
  adoption, backups, isolated PITR/logical restore, integrity validation,
  cutover, and quarterly restore drills.

## Acceptance

Shell syntax, full Go tests/build, and diff checks pass. A destructive real
blank-database and restore drill requires a disposable PostgreSQL database and
must be completed before production-readiness claims. Never run `dbbootstrap`
against the current database; it refuses any non-empty current schema.

## Boundary

No service RPC, MCP tool, new database, REST path, legacy route, or production
data deletion is introduced. Migrations build schema; backups/PITR recover data.
