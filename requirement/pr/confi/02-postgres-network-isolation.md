# Confi PR 02: PostgreSQL network isolation

Depends on: Confi PR 01

## Objective

Remove broad public access to the production OLTP database and ensure CEERAT
services use private, encrypted, least-privilege database connections.

## Work

- Replace the observed `0.0.0.0/0` database allowlist with private-only access
  where the Render plan supports it.
- Make `ceerat-user-service` and Keycloak use Render internal connection details.
- If temporary public administration is unavoidable, allowlist one explicit
  operator IP for a bounded maintenance window, require TLS, then remove it.
- Use distinct least-privilege database roles for application runtime,
  migration, Keycloak, backup/restore, and read-only diagnostics as applicable.
- Confirm application roles cannot create roles/databases or bypass ownership.
- Add a deployment gate that fails when production database public access is
  broad or when a public database URL is supplied to a service.
- Verify backups and restore connectivity through the intended administrative
  path before removing emergency access.

## Acceptance

- No production PostgreSQL allowlist contains `0.0.0.0/0` or `::/0`.
- External unauthorized connection attempts fail.
- User service and Keycloak remain healthy through private connections.
- Migrations use the dedicated controlled path and `db-verify` passes.
- No connection string or password appears in evidence.

## Out of scope

OLTP schema changes, a second database, direct client/database access, and
permanent administrator public access.

