# PR 09: Phase 1 freeze and milestone

Repository: `infra`

Depends on: a passing PR 08 acceptance report

Status: **release-candidate documentation implemented on 2026-09-03; milestone
tag blocked by eight explicit PR 08 human/operator checks**

## Objective

Close Phase 1 without adding functionality and establish the identity/security
foundation that Phase 2 must reuse.

## Changes

- Update the Phase 1 and Phase 1-B documents to match deployed behavior,
  including Brevo SMTP, verified email, separated OAuth clients, connection
  lifecycle semantics, and actual revocation guarantees.
- Add the final redacted acceptance summary and commit references for every
  participating repository.
- Record remaining limitations explicitly; do not convert an unverified item
  into a pass.
- Freeze the nine-tool identity/profile/connection surface and response schema.
- Document compatibility and deprecation policy for future changes.
- Prepare the annotated release/tag notes for `v1.0.0` / “Phase 1 COMPLETE”.

## Required checks

- All repositories clean and all referenced commits pushed.
- Contract, service, gateway, and infra validation green.
- Live acceptance report green.
- No secrets in Git history introduced by these PRs.
- Rollback instructions tested for Keycloak and gateway deployments.

## Non-goals

No implementation change, social login, jobs, skills, applications, TXSE, or
Kubernetes.

## Builder-agent and documentation gate

- Run `ceerat-builder docs all --output json`, all shared builder checks, and
  `make verify-platform` before declaring the milestone complete.
- Reconcile infra deployment evidence with builder-agent architecture,
  public-AI security, RBAC, service, and AI-tool standards.
- Verify there is no documentation drift across `infra`, `apps-repo`,
  `services-repo`, `contracts-repo`, and `ceerat-platform-builder-agent`.
- The freeze commit must reference the final builder checks and live acceptance
  evidence. Documentation is part of the completion gate, not follow-up work.

## Acceptance

The milestone can be reproduced from the committed runbook, and Phase 2 work
can depend on the frozen identity boundary without modifying it opportunistically.

## PR 09 result

Codex prepared the release-candidate documentation, reconciled the deployed
OAuth and revocation behavior, froze the compatibility rules, and recorded the
participating repository revisions in
`docs/public-agent-phase-1-release-candidate.md`. It did not create `v1.0.0` or
claim Phase 1 complete because PR 08 still reports eight `MANUAL_REQUIRED`
checks.

The tag may be created only after a human replaces every required item with
redacted passing evidence, verifies all repositories are clean and pushed,
runs the complete platform gate without unresolved active-product failures,
and confirms the Keycloak/gateway rollback exercise. Builder standards are not
updated before that human validation, per the builder-agent workflow.

Codex validation completed on 2026-09-03:

- builder context, documentation discovery, contract/service drift, and active
  app inventory checks pass;
- `make verify-platform` passes tests, builds, vet, race, coverage, and static
  analysis across the participating Go modules;
- deprecated legacy AI-tool inventory is excluded from the active MCP gate;
- vendored third-party Go is excluded from first-party formatting checks.
