# Security and scale PR 04: Cross-repository release and security gates

Status: Planned — implementation and deployed acceptance are not complete.  
Priority: P1  
Repositories: infra and all implementation repositories  
Dependencies: PRs 01–03 tests join this gate as delivered; coordinate ../confi/05-secret-scanning.md and ../confi/06-keycloak-drift-gate.md.

## Problem and evidence

The inspected infra workflow builds portals, internal agent, contracts, and user service, but omits the MCP gateway. It does not provision PostgreSQL integration fixtures and is not triggered by pull requests. Manual test success is not a repeatable release gate.

Source: `infra/.github/workflows/ci.yml`. External CI settings were not audited.

Evidence describes the source/template review on 2026-10-23. Revalidate against
current source and deployed configuration before implementation; absence of
committed configuration is not proof of absence in production.

## Required work

- Add pull-request validation and include the gateway in build, tests, dependency caches, and artifacts. Define triggers or required release orchestration for changes in every contributing repository.
- Run database-backed security/integration tests against disposable PostgreSQL with required environment configured. Fail when mandatory integration tests unexpectedly skip; retain explicit documented generator-only exceptions.
- Run relevant race tests, builder RBAC/inventory/drift checks, dependency/container vulnerability scanning, and the existing secret-scanning gate. Pin workflow dependencies and use minimum CI credentials.
- Record an immutable contract/service/gateway/portal/migration version tuple. Promote the tested artifacts, verify schema/auth compatibility, and define rollback or roll-forward for irreversible migrations.
- Gate deployment on sanitized results, including OAuth scopes, revocation, ownership, confirmation, and sensitive-log tests.

## Acceptance and verification

- [ ] Demonstrate that a failing gateway test, database authorization test, builder drift, or synthetic scanner fixture blocks release.
- [ ] Demonstrate a passing clean checkout using the recorded repository revisions, with no hidden local database or credentials.
- [ ] Verify branch protection/deployment enforcement in the actual hosting system; workflow YAML alone is insufficient evidence.

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

A claim that all vulnerability findings can be ignored or that local tests certify the deployed environment.
