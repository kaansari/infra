# Confi PR 01: Credential inventory and rotation

## Objective

Replace every credential that has been exposed, shared across environments, or
lacks a documented owner and rotation procedure.

## Work

- Inventory Keycloak admin, revoker client, ChatGPT confidential client, SMTP,
  database, JWT/prototype, Google broker, Render/API, and workload credentials.
- Record only owner, environment, purpose, storage location, creation/rotation
  dates, and safe fingerprint—not secret values.
- Rotate credentials previously entered into chat, terminal output, tickets,
  documentation, or logs.
- Use distinct random values for local, test, and production.
- Store production values only as Render secret environment variables or an
  approved secret manager. Keep local values in ignored mode-0600 files.
- Remove superseded secrets completely; do not keep rollback credentials.
- Restart only consumers that require the rotated value, then verify success and
  rejection of the superseded credential without recording either value.
- Add production startup rejection for documented default/development secrets.

## Acceptance

- Every privileged secret has an owner and rotation interval.
- Previously exposed values fail authentication.
- Current services authenticate successfully after restart.
- Repository, Git history scan, logs, and evidence contain no active secret.
- Recovery procedure is tested without exposing recovery material.

## Out of scope

Application authentication redesign, browser changes, and storing secrets in
new database tables.

