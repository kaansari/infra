# Security and scale PR 07: Capacity, observability, and production acceptance

Status: Planned — implementation and deployed acceptance are not complete.  
Priority: P1  
Repositories: infra, apps-repo, services-repo, builder documentation  
Dependencies: PRs 01–06; existing required ../confi/ gates and applicable ../phase3/ acceptance gates.

## Problem and evidence

No reproducible capacity benchmark or sufficient latency/saturation alert evidence was established in the reviewed source. Functional tests and the prior customer MCP exercises do not establish production throughput or reliability.

Evidence describes the source/template review on 2026-10-23. Revalidate against
current source and deployed configuration before implementation; absence of
committed configuration is not proof of absence in production.

## Required work

- Define a versioned target workload: concurrent users, request mix, data size, peak rate, agent/model usage, latency/error objectives, maximum resources, and acceptable cost. Record any unanswered target as an open release decision, never an invented capacity number.
- Create repeatable read, prepare/confirm, mixed-tenant, burst, sustained, saturation, and recovery scenarios using synthetic data and isolated credentials. Include multiple gateway/service instances and realistic database limits.
- Instrument safe request/error/latency metrics, database connection waits/locks, limiter failures, agent concurrency/model cost, dependency readiness, and backup success. Avoid customer identity, raw paths/queries, prompts, and secret-bearing labels.
- Implement dashboards, actionable alerts, and response runbooks with named operational ownership. Keep centralized security audit requirements linked rather than duplicated.
- Freeze the tested version/configuration tuple, dataset scale, resource footprint, bottlenecks, safe operating envelope, rollback criteria, and outstanding risks. Update durable builder standards only after validated behavior.

## Acceptance and verification

- [ ] Publish reproducible sanitized results showing whether agreed latency/error/cost targets hold and where saturation begins; a failed target blocks the corresponding readiness claim.
- [ ] Trigger representative dependency, saturation, backup, and security alerts and verify delivery and runbook usefulness.
- [ ] Complete production acceptance against actual deployed configuration, including existing MFA, isolation, transport, secret, drift, and audit gates. Record PASS/FAIL separately from local and staging results.

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

A blanket security certification, an unsupported readiness percentage, or executing billable/destructive production load without explicit operator intent.
