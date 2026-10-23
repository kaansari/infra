# CEERAT security and scalability PR plan

This track turns the 2026-10-23 source and deployment-template assessment into
seven separately reviewable implementation PR requirements. All items are
**planned**. These files are local PR specifications, not opened GitHub pull
requests, implemented fixes, or a production security certification.

## Priorities and sequence

P0 means address before broader production exposure. P1 means required for the
production readiness/capacity claim defined here; it does not assert a known
active exploit. Sequence follows the dependency field in each document. PR 01
can ship independently; PR 04 can begin alongside PRs 02–03 and incorporate their
tests as they land. Workload definition for PR 07 should begin early; final
acceptance follows all dependencies.

| Order | PR | Priority | Status |
| --- | --- | --- | --- |
| 01 | [OAuth callback and sensitive-log redaction](01-oauth-log-redaction.md) | P0 | Planned |
| 02 | [Database privilege isolation and migration ownership](02-database-privilege-isolation.md) | P0 | Planned |
| 03 | [Privileged agent confirmation and administrative controls](03-privileged-agent-action-controls.md) | P1 | Planned |
| 04 | [Cross-repository release and security gates](04-release-security-gates.md) | P1 | Planned |
| 05 | [Bounded database and agent workloads](05-bounded-workloads-and-pools.md) | P1 | Planned |
| 06 | [Dependency readiness, availability, and recovery](06-readiness-availability-and-recovery.md) | P1 | Planned |
| 07 | [Capacity, observability, and production acceptance](07-capacity-observability-acceptance.md) | P1 | Planned |

## Existing requirements remain authoritative

- [Configuration hardening](../confi/README.md) owns credential rotation,
  network/transport isolation, admin MFA/session policy, secret scanning,
  Keycloak drift, centralized audit, and production configuration acceptance.
  Reuse those PRs; do not create competing policies. This new track explicitly
  includes portal and internal-agent behavior outside that track's original scope.
- [Canonical OAuth/gRPC](../oauth-grpc-auth/README.md) remains the identity and
  original-token propagation architecture.
- [Phase 3 preferences](../phase3/README.md) retains typed preferences,
  ownership, encryption/privacy, confirmed durable writes, and its own live
  acceptance matrix. Scale testing does not replace domain security acceptance.
- [Database architecture](../../../docs/database-architecture.md) and
  [restore runbook](../../../docs/database-create-restore.md) must be updated
  when runtime roles, migrations, or recovery procedures change.

## Architecture constraints

Preserve original OAuth token propagation, private gRPC enforcement, service-owned
RBAC/account status/ownership, and existing customer MCP confirmation controls.
No new end-user JWT, generic privileged CRUD, automatic admin MCP exposure, or
parallel preference implementation. Keep the current domain/service boundaries;
add infrastructure or split services only for a demonstrated requirement.

## Required builder workflow

Use `ceerat-platform-builder-agent` to revalidate context, security, architecture,
ownership, RBAC, and drift before each implementation PR. Run from its checkout:

```text
ceerat-builder check-context
ceerat-builder codex-context --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder rbac check --output json
ceerat-builder check apps --output json
ceerat-builder check sql --output json
ceerat-builder check drift --output json
```

Use applicable contract/service impact and verification commands when changing
contracts. Builder success is architecture evidence, not authorization for live
mutation or proof of deployed security/capacity.

## Evidence and completion

Each implementation PR records exact repository revisions, migration/configuration
versions, environment, redacted commands/results, rollout/recovery steps, and
remaining risks. Store only safe counts, timings, policy/resource names, and
correlation identifiers. Never include credentials, OAuth codes/state, tokens,
cookies, database URLs, preference values, prompts, or customer PII.

Local, integration, staging, and deployed acceptance are distinct. Do not mark a
PR complete until its checklist passes; do not declare this track production-ready
until existing configuration gates and PR 07's agreed capacity/recovery targets
are verified in the intended deployment. Creating these requirements authorizes
no production mutation or billable load test.
