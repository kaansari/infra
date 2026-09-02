# PR 08: Live Phase 1 security acceptance harness

Repository: `infra`

Depends on: PRs 01 through 07

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

## Acceptance

All scenarios pass twice: once with Codex and once with the ChatGPT app where an
interactive client-specific behavior is involved. Any manual step is recorded
as evidence rather than silently marked automated.
