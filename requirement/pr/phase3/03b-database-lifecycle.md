# Phase 3 PR 03B: Deterministic database lifecycle

Status: implemented; local setup and isolated restore verified (2026-10-07)

Restore repair implementation: `services-repo` commit `87c3918`.

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

## Preference hardening in the lifecycle

`services-repo/services/ceerat-user-service/migrations/20261007_phase3_preferences_hardening.sql`
is a required ordered migration in this lifecycle, following the applied
`20260914_phase3_preferences.sql` foundation. The runner discovers it without
special-case commands and records its SHA-256 checksum under version `20261007`.
The original applied migration remains immutable.

The correction aligns typed values and custom definition versions with PR02,
enforces customer-wide operation-key uniqueness, validates existing catalog
bindings, and adds the reviewed catalog write guard and retention indexes.
Incompatible existing rows abort the transaction and require explicit operator
remediation; setup never deletes customer preferences to make a gate pass.

Full preflight must discover and pass
`migrations/preflight/20261007_phase3_preferences_hardening_preflight.sql`, as well
as all earlier checks. Deploy the matching service only after the ledger and
preflight confirm this correction. A separate development rollback exists under
`migrations/rollback/`; it is excluded from forward setup and does not recover
business data. See PR03 for the storage implementation and tests.

The real logical restore drill exposed a caller `search_path` dependency in the
hardening validators. Preserve the applied hardening checksum and apply the
additive `20261008_phase3_preferences_restore.sql` repair as the next ordered
version. It pins validators and the catalog trigger to `pg_catalog` plus their
owning schema so constraint evaluation works under `pg_restore`'s cleared path.
Its matching preflight is part of both the full runner and runtime checks.

## Full setup workflow

Use the existing database and its configured schema; do not create a separate
preference database. From `services-repo/services/ceerat-user-service`, with the
DB environment set for the intended target:

- Empty database/schema: `make db-bootstrap`, then `make db-verify`.
- Existing database/schema: back up first, then `make db-verify`; never bootstrap.
- Repeat `make db-verify` to confirm pending-only execution and checksum stability.
- Verify clean creation and logical backup/restore in isolated disposable
  databases. Restored data and migration-ledger checksums must match; rerun full
  preflight before considering a restore usable.

`db-verify` runs migration, every committed preflight, and ledger status. Record
only schema versions/checksums and aggregate test evidence, not customer contents
or credentials. Detailed procedures remain in `docs/database-create-restore.md`.

## Acceptance

Local development setup and a disposable blank-database/restore drill were run
on 2026-10-07. The development database was backed up and adopted through the
checksum-ledger runner; pending migrations, including `20261007` and the additive `20261008` repair, and every
committed preflight passed. Bootstrap was not run against the existing database.

The isolated drill passed empty-schema bootstrap, all forward migrations,
full preflight, pending-only rerun, non-empty bootstrap refusal, altered-checksum
rejection, active-lease rejection, and logical backup/restore into a separate
database. Synthetic exact-money preferences, profiles, completed operations, and history
were included in the dump. All 47 table counts/fingerprints and all 16 migration
ledger entries matched after restore; a separate `keycloak` probe confirmed
schema preservation. Full service tests, full race tests, build, lifecycle shell
syntax, builder drift, diff checks, and independent review passed. Disposable databases are removed after verification;
the development database stays running and its pre-migration backup remains in
a private local directory outside Git.

Verified local target: loopback PostgreSQL on port `55434`, database `postgres`,
application schema `public`. The existing database was preserved and is left
running. The isolated creation/restore drills used separate databases and the
`ceerat` schema; no hosted database or application traffic was changed.

This local evidence does not certify hosted PITR, provider backup retention,
production cutover, or production RPO/RTO. Those require the operator-owned
production restore drill described in the runbook.

## Boundary

No service RPC, MCP tool, new database, REST path, legacy route, or production
data deletion is introduced. Migrations build schema; backups/PITR recover data.
