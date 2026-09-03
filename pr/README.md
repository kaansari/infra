# CEERAT Phase 1 completion PR plan

This folder turns `requirement/phase1-pr1.md` into small, dependency-ordered
pull requests. Phase 1 remains limited to identity, profiles, connections, and
their security controls. Jobs, skills, applications, TXSE, account deletion,
and Kubernetes are explicitly excluded.

## Merge order

| Order | Document | Repository | Purpose |
| --- | --- | --- | --- |
| 1 | [PR-01](01-gateway-contract-correctness.md) | `apps-repo` | Complete — strict input handling and authenticated-status scope behavior |
| 2 | [PR-02](02-connection-lifecycle-semantics.md) | `apps-repo` | Complete — truthful connection/token state and server-derived `is_current` |
| 3 | [PR-03](03-keycloak-oauth-hardening.md) | `infra` | Complete — split clients, hardened OAuth, and automatic refresh live-validated |
| 4 | [PR-04](04-token-and-scope-security-tests.md) | `apps-repo` | Complete — JWT client allowlist and per-tool scope enforcement verified |
| 5 | [PR-05](05-keycloak-session-revocation.md) | `apps-repo` | Complete — Keycloak-backed logout and post-logout denial live-validated |
| 6 | [PR-06](06-profile-write-safety-tests.md) | `apps-repo` | Complete prepare/confirm expiry, replay, and conflict tests |
| 7 | [PR-07](07-rate-limit-and-audit-controls.md) | `apps-repo` | Add bounded abuse controls and verify safe audit logging |
| 8 | [PR-08](08-live-security-acceptance.md) | `infra` | Exercise two-user isolation and credential revocation against a deployed stack |
| 9 | [PR-09](09-phase1-freeze.md) | `infra` | Record evidence, fix documentation drift, and freeze/tag Phase 1 |

PRs 1 and 2 establish truthful public behavior. PR 3 establishes the live OAuth
policy. PRs 4 through 7 harden and test individual security boundaries. PR 8 is
the final system-level gate. PR 9 contains no feature work.

## Delivery slices

- Slice A: PR 01, then PR 02. These are small gateway correctness changes and
  should merge before security behavior is used as an acceptance baseline.
- Slice B: PR 03 and PR 04 may be developed in parallel after PR 01, but PR 04
  must use the client/audience decisions finalized by PR 03 before merge.
- Slice C: PRs 05, 06, and 07 are separate gateway concerns and should remain
  separate even if one engineer implements them consecutively.
- Slice D: PR 08 is integration evidence; PR 09 is documentation/release only.

Target each implementation PR at one reviewable behavior, its migrations or
configuration, and its tests. If a PR starts requiring unrelated protobuf or
user-service changes, stop and create a separately reviewed defect PR rather
than widening the current one. No `contracts-repo` or `services-repo` change is
planned initially; the live isolation suite verifies those boundaries.

## Rules for every PR

- One repository and one security concern per PR.
- No secrets, live tokens, user passwords, or production database contents in
  fixtures, logs, screenshots, or commits.
- Add negative tests before or with the implementation change.
- Preserve the self-service rule: tool arguments never select a CEERAT user.
- Public errors remain stable, generic, and agent-actionable; diagnostics stay
  in sanitized internal logs with a request ID.
- Generated/vendor changes must be explained and limited to dependencies used
  by that PR.
- Do not merge on unit tests alone when the acceptance section requires a live
  Keycloak or multi-user check.
- Avoid drive-by refactors, dependency upgrades, or generated-file churn.

## Mandatory ceerat-platform-builder-agent workflow

Every PR must use `ceerat-platform-builder-agent` as a required architecture
and security reviewer, not as optional background reading.

Before implementation, run from the builder-agent repository:

```bash
ceerat-builder check-context
ceerat-builder codex-context --output json
ceerat-builder app-context ceerat-agent-gateway --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder docs all --output json
```

Also run the PR-specific builder commands listed in its design document. Save a
sanitized planning/validation summary in the PR description; do not commit raw
tokens, secrets, environment dumps, or production identity data.

The review must explicitly answer:

- Where do external OAuth credentials terminate?
- Which component authenticates the gateway-to-service call?
- Which service owns authorization, record ownership, validation, and storage?
- Can any model-controlled field select a user, customer, scope, role,
  connection owner, or grant authority?
- Are consequential operations confirmed, bound, expiring, idempotent where
  retryable, and safe under uncertain outcomes?
- Can errors, logs, traces, or audit events reveal credentials or internals?
- Does the change preserve the public MCP -> gateway -> private gRPC boundary?

After implementation, run:

```bash
ceerat-builder check apps --output json
ceerat-builder check drift --output json
```

From `infra`, run `make verify-platform` when the PR affects a platform
boundary or shared inventory. A builder warning must be resolved or recorded as
an explicit risk acceptance; it must not be silently ignored.

## Documentation synchronization after every PR

Each implementation PR updates its owning README, API/tool documentation,
architecture/security notes, inventories, deployment configuration examples,
and test/runbook material affected by the change. Documentation describes the
implemented behavior, not the intended future behavior.

After the PR is merged, deployed, and human-validated, complete a small
documentation-only checkpoint in `ceerat-platform-builder-agent` before
starting the next PR:

1. Run `ceerat-builder docs all --output json` to identify affected canonical
   documentation.
2. Update `.ceerat-agent/architecture.md`,
   `.ceerat-agent/public-ai-integration-security-profile.md`,
   `.ceerat-agent/security-rbac-standard.md`,
   `.ceerat-agent/service-standards.md`, or
   `.ceerat-agent/ai-tool-standard.md` only where the PR established a reusable,
   tested rule.
3. Update builder inventories/context when the implemented surface, ownership,
   configuration, or verification commands changed.
4. Run `ceerat-builder check-context`, `ceerat-builder check apps --output
   json`, and `ceerat-builder check drift --output json`.
5. Commit and push the builder-agent documentation checkpoint with the
   implementation PR number and validation evidence referenced in its message.

Deployment-specific evidence remains in `infra`; reusable platform rules live
in `ceerat-platform-builder-agent`. Speculative design must not be promoted to
a platform standard.

## Definition of Phase 1 complete

Phase 1 is complete only after PR 8 records passing evidence for OAuth, token
validation, scope enforcement, two-user isolation, profile-write safety,
connection/session revocation, email verification, secret redaction, rate
limiting, and TLS. PR 9 then freezes the API and publishes the milestone.
