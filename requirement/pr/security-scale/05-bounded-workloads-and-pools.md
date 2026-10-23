# Security and scale PR 05: Bounded database and agent workloads

Status: Planned — implementation and deployed acceptance are not complete.  
Priority: P1  
Repositories: services-repo, apps-repo, contracts-repo, infra  
Dependencies: PR 04 for regression gates; coordinate PR 07 workload definitions.

## Problem and evidence

User-service and gateway database initialization do not establish explicit production connection-pool budgets. Some administrative lists load all rows. Replica growth multiplies connections and expensive work; agent request deadlines alone do not bound concurrent model spend.

Source: `services-repo/services/ceerat-user-service/main.go`, `admin-services/repository.go`, and `apps-repo/ai/ceerat-agent-gateway/internal/gateway/state.go`.

Evidence describes the source/template review on 2026-10-23. Revalidate against
current source and deployed configuration before implementation; absence of
committed configuration is not proof of absence in production.

## Required work

- Set validated maximum open/idle connections and connection lifetimes for each process. Budget maximum replicas times pool limits, migrations, Keycloak, and operational headroom against database capacity.
- Implement stable server-side pagination and maximum page sizes for unbounded administrative queries. Coordinate contract and caller updates without silently truncating existing results.
- Bound request sizes, deadlines, expensive RPC concurrency, and per-user agent concurrency/model usage. Apply service-owned limits with shared enforcement where multiple replicas must share a quota.
- Specify overload behavior and cancellation propagation. Reserve bounded operational capacity so health/recovery work remains possible under load.
- Review gateway rate-limit storage contention and expiry cleanup under the measured workload; move broad cleanup off the request path if warranted. Add infrastructure only when evidence justifies it.

## Acceptance and verification

- [ ] Load realistic data volumes and verify bounded query size, stable pagination, and correct authorization across pages.
- [ ] Run multiple replicas with a constrained database; prove connection totals remain within budget and overload returns bounded, documented failures without runaway queues.
- [ ] Verify cancellation, quota concurrency, and bounded agent work; record connection wait time and recovery after saturation.

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

Arbitrary capacity claims, automatic microservice decomposition, or an unconditional Redis/queue requirement.
