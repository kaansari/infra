# Security and scale PR 01: OAuth callback and sensitive-log redaction

Status: Planned — implementation and deployed acceptance are not complete.  
Priority: P0  
Repositories: apps-repo, infra  
Dependencies: None; independently shippable.

## Problem and evidence

Portal request logging can retain raw OAuth callback query parameters. Customer logging currently suppresses preference queries but returns other raw queries; web UI logging records RawQuery. Authorization codes and state must not enter ordinary telemetry. PKCE does not make logging these values acceptable.

Source: `apps-repo/apps/ceerat-customer-ui/internal/server/logging.go`, `internal/server/preferences.go`, and `apps-repo/apps/ceerat-web-ui/internal/server/logging.go`.

Evidence describes the source/template review on 2026-10-23. Revalidate against
current source and deployed configuration before implementation; absence of
committed configuration is not proof of absence in production.

## Required work

- Use an allowlist for safe request metadata across customer, web, and admin portals. Exclude OAuth query values, authorization headers, cookies, bodies, and preference content from logs, traces, errors, and proxy access logs.
- Preserve safe route, status, duration, and correlation fields. Inspect upstream/proxy logging independently of application logging.
- Document restricted access, retention, and safe remediation of existing logs through the configuration audit track. Assess historical exposure without copying sensitive log contents into evidence.

## Acceptance and verification

- [ ] Exercise successful and failed OAuth callbacks, encoded and repeated query parameters, and preference requests using unique synthetic secret markers.
- [ ] Capture application telemetry and verify no marker appears while safe request correlation remains available.
- [ ] Record sanitized deployment verification for each portal and proxy; do not put real callback URLs or credentials in evidence.

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

Changes to OAuth protocol behavior or customer permissions.
