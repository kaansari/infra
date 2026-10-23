# Security and scale PR 03: Privileged agent confirmation and administrative controls

Status: Planned — implementation and deployed acceptance are not complete.  
Priority: P1  
Repositories: apps-repo, services-repo, contracts-repo, infra  
Dependencies: PR 02 for durable storage changes; reuse ../confi/04-admin-mfa-session-policy.md and ../confi/07-central-security-audit.md.

## Problem and evidence

Internal agent function tools can dispatch model-selected customer/order mutations directly. Existing OAuth, RBAC, and ownership checks still apply; the gap is protection against unintended authorized actions. Committed configuration alone does not prove deployed admin MFA enforcement.

Source: `apps-repo/ai/ceerat-agent-service/internal/agent/agent.go`, `internal/agent/tools.go`, `internal/agent/tools_order.go`, and `services-repo/services/ceerat-user-service/admin-services/handler.go`.

Evidence describes the source/template review on 2026-10-23. Revalidate against
current source and deployed configuration before implementation; absence of
committed configuration is not proof of absence in production.

## Required work

- Inventory every agent/admin mutation and its required role, scopes, affected resource, risk, and confirmation policy. Explicitly identify unsupported actions.
- For agent writes requiring confirmation, implement server-owned preparation and an explicit human confirmation event outside model-controlled tool arguments. Bind confirmation to authenticated actor, session, action, canonical arguments, resource version, and expiry.
- Enforce validation and durable idempotency at the authoritative service boundary, with outcome lookup for ambiguous completion. Recheck authorization at confirmation and never blindly retry unknown writes.
- Reuse the existing MFA/session and centralized audit requirements for admin access and sensitive role changes; define step-up requirements and test verified authentication freshness. Do not infer MFA from a client-supplied flag.
- Treat retrieved content and prompts as untrusted data. Preserve original OAuth token propagation, RBAC, account status, and ownership checks.

## Acceptance and verification

- [ ] Prove prompt injection, forged model confirmation, changed arguments, cross-user/session replay, expiry, stale versions, and revoked authority cannot cause an unauthorized or unconfirmed write.
- [ ] Prove concurrent confirmation and crash/retry produce one logical mutation with recoverable operation status across restarts/instances.
- [ ] Verify admin login/step-up/session revocation against actual policy and sanitize audit evidence. Existing customer MCP confirmation behavior must continue to pass.

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

Exposing admin/agent MCP tools, broadening permissions, or treating a system-prompt instruction as an enforcement boundary.
