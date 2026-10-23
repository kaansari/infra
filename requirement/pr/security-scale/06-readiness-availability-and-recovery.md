# Security and scale PR 06: Dependency readiness, availability, and recovery

Status: Planned — implementation and deployed acceptance are not complete.  
Priority: P1  
Repositories: infra, services-repo, apps-repo  
Dependencies: PR 02 for role-aware recovery; PR 04 for deployment gates; PR 05 for resource budgets.

## Problem and evidence

Kubernetes templates retain single-instance PostgreSQL and Typesense. Some probes establish only TCP availability. Restore documentation exists, but this review did not establish deployed HA, tested failover, or measured RPO/RTO.

Source: `infra/k8s/base/postgres/statefulset.yaml`, `infra/k8s/base/typesense/`, `infra/k8s/base/ceerat-user-service/deployment.yaml`, and `infra/docs/database-create-restore.md`.

Evidence describes the source/template review on 2026-10-23. Revalidate against
current source and deployed configuration before implementation; absence of
committed configuration is not proof of absence in production.

## Required work

- Define production availability, recovery-point and recovery-time objectives, dependency ownership, and the intended supported deployment topology. Select managed HA or another tested design according to those objectives.
- Separate liveness from bounded dependency/schema readiness. Preserve gateway authenticated readiness: provide a safe operational probe or authenticated probe identity rather than exposing protected business RPCs.
- Configure resource budgets, graceful shutdown/draining, disruption protection, and scaling policies appropriate to the selected platform. Do not use additional stateless replicas as a substitute for database HA.
- Automate and monitor backups/PITR as appropriate, with protected independent retention. Include Keycloak, application data, gateway preparations/operations, and required encryption/replay keys in a consistent recovery design.
- Perform isolated restore and failover drills. Verify Typesense reconstruction, migration compatibility, OAuth identity/session behavior, and ambiguous write reconciliation after recovery.

## Acceptance and verification

- [ ] A listening process with an incompatible schema or unavailable required dependency does not receive business traffic; transient dependency failures do not create liveness restart storms.
- [ ] Kill an instance during a confirmed operation and prove bounded disruption and recoverable outcomes.
- [ ] Restore from protected backups into an isolated environment and record measured RPO/RTO, data consistency, ownership checks, and dependency recovery; repeat on an owned schedule.

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

Claiming template configuration proves deployed HA, exposing authenticated readiness publicly, or destructive production drills without operator authorization.
