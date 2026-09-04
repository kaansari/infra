# PR 08: Live Phase 1 security acceptance harness

Repository: `infra`

Depends on: PRs 01 through 07

Status: partial Codex acceptance completed on 2026-09-03; interactive,
multi-user, refresh-family, datastore-count, and live-log checks remain manual.

## Objective

Run the final security scenarios against a deployed development environment and
produce machine-readable PASS/FAIL evidence without committing credentials.

## Harness design

- Keep test-user credentials and OAuth secrets in local/CI secret storage.
- Create isolated User A and User B fixtures with deterministic cleanup.
- Drive OAuth through a supported test client using Authorization Code + PKCE;
  do not add a password grant for test convenience.
- Save only redacted request IDs, timestamps, status/error codes, and resource
  identifiers created for the test.

## Required scenarios

1. Health, MCP discovery, OAuth metadata, TLS, and exact redirect policy.
2. Valid and invalid JWT dimensions plus the complete scope matrix.
3. A cannot read or modify B's profile or revoke B's connection.
4. Preparation expiry, replay rejection, content binding, and version conflict.
5. A/B/C connection test: revoke B; A and C continue; B cannot refresh.
6. Logout: old access and refresh family cannot regain CEERAT access.
7. Unverified email denied; verified email provisioned exactly once.
8. Duplicate/concurrent identity exchanges do not duplicate user/customer/map.
9. Rate-limit behavior and recovery.
10. Public responses and captured logs contain none of the forbidden secrets.

## Deliverables

- A runnable script or Go test entry point with documented prerequisites.
- A redacted JSON result matching a versioned acceptance schema.
- A short operator runbook for ChatGPT and Codex interactive portions.
- Cleanup that targets only test-created identities/resources.

## Non-goals

No production destructive testing, load test, browser automation framework,
jobs, skills, applications, TXSE, or Kubernetes.

## Builder-agent and documentation gate

- Run the complete shared builder workflow before and after the acceptance
  harness, including `make verify-platform` from `infra`.
- Treat the public-AI security profile's production verification gate as the
  acceptance checklist; every item must link to automated or explicitly manual
  evidence.
- Update the infra acceptance runbook, redacted evidence, deployment notes,
  and milestone status in this PR.
- After human validation, reconcile every reusable finding into builder-agent
  architecture/security/tool standards and inventories before PR 09. Do not
  mark an untested item complete.

## Acceptance

All scenarios pass twice: once with Codex and once with the ChatGPT app where an
interactive client-specific behavior is involved. Any manual step is recorded
as evidence rather than silently marked automated.

## Codex automation evidence

Run `CEERAT_PR08_RUN_RATE_LIMIT=true make verify-phase1-live`. The harness
writes a credential-free, mode-0600 report to the gitignored
`.verification/pr08-codex.json` using
`verification/phase1/acceptance-result.schema.json` version 1.0.

The 2026-09-03 deployed-development run passed eleven checks:

- gateway health/readiness, MCP initialize/list, protected-resource discovery,
  OAuth challenge metadata, and tool security declarations;
- TLS 1.2-or-newer certificate verification;
- exact ChatGPT/Codex redirect policy, S256 PKCE, and rejection of implicit,
  password, bad-redirect, missing/plain-PKCE, and invalid revoker credentials;
- JWT signature, issuer, audience, lifetime, client, identity, and scope tests;
- static ownership, preparation, conflict, replay, revocation, provisioning,
  rate-limit concurrency, audit-field, and credential-redaction suites;
- live source-IP rate limiting: ten unauthenticated attempts were accepted as
  authentication challenges and the eleventh returned `RATE_LIMITED` without
  executing a tool.

No credentials, response bodies, customer data, or production database content
are retained. The remaining eight checks are enumerated as `MANUAL_REQUIRED` in
the generated report and operator runbook; PR 08 is not complete yet.

Builder contract/service drift passed. The complete platform check continues to
report the pre-existing legacy AI-tool inventory entries and formatting inside
vendored `services-repo` dependencies. The acceptance harness changes no tool,
contract, service method, generated dependency, or inventory and therefore
records rather than silently broadens PR 08 to repair those separate findings.
