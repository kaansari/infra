# CEERAT database operations: start, stop, bootstrap, migrate, back up and restore

Reference date: 2026-10-07. See [architecture](database-architecture.md),
[object models](database-object-models.md), and the [HTML catalog](database-schema.html).

## Authority and guarantees

Production user-service startup never changes its application schema. The pinned `dbbootstrap`
command creates the base schema only for an empty database; ordered SQL files
then evolve it. `schema_migrations` records each version, filename, SHA-256
checksum, and application time. Applied migration files are immutable.
The runner uses a 15-minute database lease to reject concurrent migrations.
It does not renew the lease; coordinate long migrations and prevent a second
runner from starting after expiry while the first is still active.

Migrations restore structure and reviewed seed metadata. They do not restore
customers, carts, orders, preferences, or audit history. Recover business data
from a database backup or provider point-in-time recovery (PITR).

## Required environment

Set `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_NAME`, and `DB_PASSWORD`. Set
`DB_SSLMODE=require` and `DB_SCHEMA=ceerat` for hosted PostgreSQL. Keycloak uses
the separate `keycloak` schema; the gateway owns `ceerat_agent_gateway`. Never put passwords in commands,
Git, logs, or migration files.

The bootstrap, migration, preflight, and status scripts export `DB_SSLMODE` to
the PostgreSQL client. If it is omitted for local development, they use
`prefer`; Render must set it to `require`.

## Target selection and status

| Target | Connection | Application schema | PostgreSQL process owner |
|---|---|---|---|
| Existing local development | `localhost:55434`, database `postgres`, configured `CEERAT_DB_*` | `public` | Local `pg_ctl`, configured `CEERAT_PGDATA` |
| Existing Render instance | `ceerat-postgres`; internal hostname for consumers, external hostname for operators | `ceerat`, verified against service configuration | Render |
| Isolated creation/restore drill | A distinct disposable database, never the only existing copy | Same schema as the selected backup/release | Drill operator / provider |

Choose the target explicitly for each operation. Do not source local stack helpers
for hosted work. Use the database's direct connection on port 5432 for schema
changes. Render external connections require TLS and the full external hostname;
do not replace it with a cached IP. [Render connection documentation](https://render.com/docs/postgresql-creating-connecting).

Load DB variables from the approved secret source without printing them. To avoid
an inherited URL overriding bootstrap's component settings, `unset DATABASE_URL`
when operating with `DB_*`. Check client/server versions before backup: use a
`pg_dump` client matching the server major version, and compatible `pg_restore`.

```bash
psql --version
pg_dump --version
pg_restore --version
export PGPASSWORD="$DB_PASSWORD" PGSSLMODE="$DB_SSLMODE"
psql -X -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SELECT current_database(),current_user,current_setting('server_version');"
# This block runs from infra; database targets belong to the user service.
make -C ../services-repo/services/ceerat-user-service db-status
```

`db-status` requires an existing ledger. On a never-migrated schema, its absence
is a setup signal, not permission to insert ledger records manually. Inspect only
schema metadata while choosing bootstrap versus adoption.

## Local start, stop and restart

The following commands run from `infra` and operate only on the configured local cluster:

```bash
source ./common.sh
require_local_development_targets
case "$CEERAT_DB_HOST" in localhost|127.0.0.1|::1) ;; *) exit 1 ;; esac
ensure_dirs

# First installation only; never initialize over an existing cluster.
if [[ ! -f "$CEERAT_PGDATA/PG_VERSION" ]]; then
  env LANG=C LC_ALL=C "$INITDB" -D "$CEERAT_PGDATA" -U "$CEERAT_DB_USER" \
    -A trust -E UTF8 --locale=C
fi

# The guard handles stopped-cluster status under common.sh's set -e.
if "$PG_CTL" -D "$CEERAT_PGDATA" status; then
  echo "Local PostgreSQL is already running"
else
  "$PG_CTL" -D "$CEERAT_PGDATA" -l "$POSTGRES_LOG" \
    -o "-h localhost -p $CEERAT_DB_PORT" -w start
fi
```

To stop the database in the same configured local shell, stop consumers first:

```bash
"$PG_CTL" -D "$CEERAT_PGDATA" -m fast -w stop
```

Fast shutdown rolls back open transactions cleanly. Local trust authentication is restricted to the development
cluster; it is not a hosted authentication configuration. Starting PostgreSQL
does not bootstrap or migrate the application schema.

For the full local stack, `make start-stack`, `make status-stack` and
`make stop-stack` are available from `infra`. `stop-stack` stops the applications,
managed Keycloak/Typesense, and PostgreSQL. Database-only restart uses stop/start
above, followed by `make -C ../services-repo/services/ceerat-user-service db-verify`
from `infra` with the local `DB_*` settings, then restarts
consumers. Keep the data directory and backups; deletion is not a stop routine.

## Render start, stop and restart

Authenticate with `render login`, select the intended workspace, and identify the
exact database ID before an operation:

```bash
render workspaces -o json
render postgres list -o json
render postgres get "$RENDER_DB_ID" -o json

# Planned outage only: stop/drain every consumer before suspension.
render postgres suspend "$RENDER_DB_ID" --confirm -o json
render postgres resume "$RENDER_DB_ID" --confirm -o json
```

Suspension affects user service, Keycloak and gateway because they share the
instance. Wait for the database to become available after resume, run full
preflight, then resume consumers and verify their health. For a provider-managed
restart use the Render Dashboard database controls or the documented restart API;
never run local `pg_ctl` against Render. [Render CLI reference](https://render.com/docs/cli-reference),
[Postgres restart API](https://api-docs.render.com/reference/restart-postgres).

## Routine schema deployment to Render

Apply committed migrations from the chosen release to the existing Render
instance, preserving its data. A local dump is not a schema deployment artifact.

1. Record release commit, database ID, schema and server version. Check ledger
   status/checksums and inspect pending SQL. Check for concurrent deploys or
   migrations; the migration lease does not itself stop application writes.
2. Take a full database backup to a private location and validate the archive.
   Schedule a write pause when a migration requires it. Preference corrections
   acquire table locks, audit existing values and can abort on incompatible data.
3. Export the Render external `DB_*`, `DB_SSLMODE=require`, `DB_SCHEMA=ceerat`;
   do not print the password or assembled URL. `unset DATABASE_URL` when using
   these component settings.
4. From the pinned service checkout run `make db-verify`. It applies pending
   migrations, checks every committed preflight and prints ledger status.
5. Repeat verification to confirm pending-only execution. Check versions
   `20261007` and `20261008`, their file checksums, validated constraints and
   the absence of a held migration lease. Record identifiers/checksums and
   sanitized outcomes only.
6. Deploy/restart a matching service release only after schema verification;
   verify Keycloak/gateway health and authenticated private gRPC reads. Reopen
   writes only after required application smoke checks pass.

`render.yaml` builds the pinned bootstrap binary and runs
`db-bootstrap-if-empty.sh`, migration, full preflight and status in the user
service pre-deploy command. That guard skips a populated application schema;
normal application startup does not migrate it. Direct operator deployment uses
the same committed migration/preflight scripts. Do not assume hosted PITR or
backup retention from the Blueprint alone; verify the actual database plan.

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

## Preference storage prerequisite

Both clean creation and existing-database adoption must include
`20261007_phase3_preferences_hardening.sql` after the immutable September
preference foundation. `make migrate` discovers the correction in order and
records version `20261007` with its SHA-256 checksum. `make preflight-schema`
also discovers its matching hardening preflight automatically. No manual ledger
insertion or standalone preference bootstrap is needed.

The matching service binary requires this correction. It audits existing
catalog/TXSE bindings and fails transactionally on incompatible data. If a
migration fails, preserve the backup, review the sanitized failure, and explicitly
remediate incompatible records before retrying. Never delete data or edit an
applied migration to bypass verification. Only schema versions/checksums and
aggregate integrity evidence belong in the deployment record.

The additive `20261008_phase3_preferences_restore.sql` repair must follow
hardening. It pins validator/trigger function lookup to the owning schema so
logical restore can evaluate constraints with the cleared caller `search_path`.
Do not edit `20261007` to add this repair: it may already be recorded in the
ledger. The full runner and runtime also check the repair's matching preflight.

## Backup

Enable the provider's automated backups/PITR and confirm retention matches the
business recovery objective. Also create a periodic encrypted logical backup in
an access-controlled location outside the primary service account:

```bash
: "${BACKUP_DIR:?Choose a private backup directory outside Git}"
umask 077
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/ceerat-$(TZ=UTC date +%Y%m%dT%H%M%SZ).dump"
PGPASSWORD="$DB_PASSWORD" pg_dump -Fc --no-owner --no-acl \
  -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
  -f "$BACKUP_FILE"
pg_restore --list "$BACKUP_FILE" >/dev/null
shasum -a 256 "$BACKUP_FILE"
```

Back up all schemas: omit `-n` so application, Keycloak, gateway and the ledger
share the snapshot. Use a private directory outside Git (`umask 077` before
creating the dump). Validate `pg_restore --list "$BACKUP_FILE"`, calculate
`shasum -a 256 "$BACKUP_FILE"`, and record size with `wc -c`. Encrypt the archive
with the approved backup key before off-host storage; keep encryption keys
separate, verify ciphertext checksum and the ability to decrypt in a drill.
Custom-format PostgreSQL dumps are not encrypted by `-Fc`.

Render-managed PITR and logical exports are available on paid compute plans;
Free databases require an operator-created logical backup. Recovery windows
and available retention depend on the actual workspace/plan. Verify these in
Render before promising RPO/RTO. [Render backup and recovery documentation](https://render.com/docs/postgresql-backups).

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
  -U "$RESTORE_DB_USER" -d "$RESTORE_DB_NAME" "$BACKUP_FILE"
```

For an empty restore target, omit `--clean --if-exists`; those flags are only
appropriate when intentionally replacing the contents of an isolated target.
Never use them against the active database. Restore all schemas, recreate
approved roles/grants excluded by `--no-owner --no-acl`, and supply service
secrets/TLS certificates separately from the dump.

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


## Failure handling and routine maintenance

| Failure | Routine |
|---|---|
| Expired Render CLI login | Run `render login`, authorize it, confirm workspace and database identity, then retry status. Do not paste tokens into chat or documentation. |
| Checksum mismatch | Stop deployment. Compare the checked-out release with the recorded applied file; restore the correct immutable file or add a new reviewed repair. Never alter ledger checksums to bypass the gate. |
| Migration lease held | Identify the active migration and wait. Do not remove a live lease or run concurrent schema work. |
| Constraint/catalog audit failure | Keep backup and private diagnostics, roll back failed transaction, review incompatible records, remediate explicitly and retry. No automatic deletion. |
| Preflight failure | Keep dependent service deployment blocked; apply the correct pending repair or restore verified schema objects. Service boot is not a repair mechanism. |
| Migration exceeds expected lock time | Inspect database activity/locks with operator privileges, coordinate a write pause, and retry after rollback. Do not terminate arbitrary sessions. |
| Restore inconsistency | Keep original database and traffic unchanged; investigate or choose an earlier verified backup/PITR point. |

Monitor storage, connection use, long transactions, backup age, failed preflights
and unresolved operations. PostgreSQL autovacuum is the default maintenance
mechanism; schedule manual maintenance from observed needs. Run aggregate orphan
checks and counts on isolated restores, without placing row contents in evidence.
Preference cleanup is bounded, history-first, terminal-only and never removes
unresolved outcomes; this foundation exposes cleanup methods but registers no
scheduler. Application timestamps, versions and digest history are business
state, not substitutes for a backup.

When the migration release changes, regenerate the object catalog from schema
metadata and record its source/environment. Verify HTML links and that no
credentials, DSNs or customer values were copied into documentation. Re-run
restore drills with representative synthetic records so constraint functions and
triggers are exercised during actual data load.
