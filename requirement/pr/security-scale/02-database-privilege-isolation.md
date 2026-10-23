# Security and scale PR 02: Database privilege isolation and migration ownership

Status: Planned — implementation and deployed acceptance are not complete.  
Priority: P0  
Repositories: infra, services-repo, apps-repo  
Dependencies: Coordinate credential inventory in ../confi/01-credential-inventory-rotation.md.

## Problem and evidence

The deployment uses a shared PostgreSQL credential for Keycloak, application services, and gateway state. Separate schemas do not restrict that role. Gateway initialization also performs schema DDL.

Source: `infra/docs/database-architecture.md`, `infra/render.yaml`, and `apps-repo/ai/ceerat-agent-gateway/internal/gateway/state.go`.

Evidence describes the source/template review on 2026-10-23. Revalidate against
current source and deployed configuration before implementation; absence of
committed configuration is not proof of absence in production.

## Required work

- Create distinct runtime identities and schema grants for Keycloak, the application, and the gateway. Enumerate required operations and remove cross-schema access, ownership, and privilege inheritance.
- Use a separate migration identity and versioned gateway migrations. Runtime startup validates schema compatibility without CREATE, ALTER, or migration privileges.
- Inventory Keycloak startup/upgrade migration requirements and define its controlled migration lifecycle before removing privileges; do not assume the application migration runner manages Keycloak.
- Update local bootstrap, deployed configuration, credential rotation, schema preflight, and restore procedures. Keep secrets outside committed files and evidence.

## Acceptance and verification

- [ ] In disposable PostgreSQL, prove each runtime role can perform intended operations and cannot read/write other service schemas or execute DDL.
- [ ] Prove clean bootstrap, upgrade from existing data, parallel startup, and incompatible-schema failure with restricted runtime roles.
- [ ] Verify actual grants and service readiness after controlled deployment; rehearse recovery and credential rollback without reintroducing shared production credentials.

- [ ] Run the shared builder workflow in [README](README.md), relevant module tests/builds, and update affected inventories/runbooks.
- [ ] Attach sanitized evidence with exact revisions, environment, commands, results, known limits, and rollout/recovery procedure. Never mark live acceptance from local tests alone.

## Rollout and recovery

Validate locally with disposable state, then in staging. Describe compatibility,
pre-deployment checks, canary/smoke checks, abort criteria, and a tested recovery
procedure in the implementation PR. Production writes, credential changes,
failover, and load execution require explicit operator intent. Preserve security
boundaries during rollback; restore/roll forward when a schema change cannot be
safely reversed.

## Out of scope

A forced database-per-service split or production credential changes during requirements authoring.
