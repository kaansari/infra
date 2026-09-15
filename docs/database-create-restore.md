# CEERAT database creation, migration, backup, and restore

## Authority and guarantees

Production service startup never changes schema. The pinned `dbbootstrap`
command creates the base schema only for an empty database; ordered SQL files
then evolve it. `schema_migrations` records each version, filename, SHA-256
checksum, and application time. Applied migration files are immutable.
The runner uses a database lease so concurrent deploys cannot migrate together.

Migrations restore structure and reviewed seed metadata. They do not restore
customers, carts, orders, preferences, or audit history. Recover business data
from a database backup or provider point-in-time recovery (PITR).

## Required environment

Set `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_NAME`, and `DB_PASSWORD`. Set
`DB_SSLMODE=require` for hosted PostgreSQL. Never put passwords in commands,
Git, logs, or migration files.

## Brand-new empty database

From `services-repo/services/ceerat-user-service`:

```bash
make db-bootstrap
make migrate
make preflight-schema
make db-status
go test ./...
go build ./...
```

`db-bootstrap` is transitional and pinned to the checked-out service commit. It
must run only on an empty database. After bootstrap, SQL migrations and their
ledger are the schema authority. Start/deploy the service only after preflight.

## Existing database adoption

Run `make migrate`. Existing idempotent migrations safely reconcile their
objects and are then recorded with checksums. Run `make db-verify` immediately.
Never manually insert migration-ledger rows or change an applied SQL file.

## Backup

Enable the provider's automated backups/PITR and confirm retention matches the
business recovery objective. Also create a periodic encrypted logical backup in
an access-controlled location outside the primary service account:

```bash
PGPASSWORD="$DB_PASSWORD" pg_dump -Fc --no-owner --no-acl \
  -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
  -f ceerat-YYYYMMDDTHHMMSS.dump
```

Encrypt before upload, restrict restore credentials, record backup timestamp,
database/server version, application commits, migration status, checksum, size,
and retention expiry. Do not commit dumps. A backup is not accepted until a
restore drill succeeds.

## Disaster/PITR restore

1. Declare the incident and stop writes/deployments.
2. Choose a provider PITR timestamp immediately before corruption, or the most
   recent verified backup consistent with the recovery-point objective.
3. Restore into a new isolated database; do not overwrite the only copy.
4. For a logical dump:

```bash
PGPASSWORD="$RESTORE_DB_PASSWORD" pg_restore --exit-on-error --clean --if-exists \
  --no-owner --no-acl -h "$RESTORE_DB_HOST" -p "$RESTORE_DB_PORT" \
  -U "$RESTORE_DB_USER" -d "$RESTORE_DB_NAME" ceerat-YYYYMMDDTHHMMSS.dump
```

5. Point the DB environment variables at the isolated restore and run
   `make db-verify`; pending migrations may apply only from the exact release
   commit selected for recovery.
6. Verify row counts and foreign-key/orphan checks, latest orders/preferences,
   authentication mappings, RBAC, idempotency/operation records, and required
   audit retention. Test authenticated private gRPC reads without writes.
7. Record evidence and obtain incident-owner approval before switching traffic.
8. Rotate any credential suspected of exposure, resume writes, and monitor.

## Restore drill and objectives

Run a restore drill at least quarterly and before major schema releases. Record
RPO (maximum acceptable lost data), RTO (maximum restoration time), actual
backup age, restore duration, migration/preflight result, integrity result, and
application smoke result. Production readiness requires named owners and
provider retention that meet the approved RPO/RTO.

## Prohibited shortcuts

- Do not use production `AutoMigrate`.
- Do not edit, reorder, rename, or delete an applied migration.
- Do not treat rollback SQL as data recovery.
- Do not restore directly over the only production database.
- Do not log DSNs/passwords or expose database access to MCP/browser clients.
