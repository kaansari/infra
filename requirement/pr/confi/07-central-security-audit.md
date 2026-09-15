# Confi PR 07: Centralized security audit retention

Depends on: OAuth/gRPC PR 06 and Confi PRs 01–06

## Objective

Collect the unified OAuth/MCP/gRPC authorization chain in a restricted,
tamper-resistant operational security store with useful alerting and retention.

## Work

- Ingest sanitized Keycloak, gateway, gRPC, RBAC, ownership, administrative,
  revocation, configuration-change, and database-access security events.
- Correlate with request ID and trace ID while retaining safe actor/client/session
  digests, method/tool, decision, operation state, timestamp, and duration.
- Use append-only or equivalently protected retention with separate operator and
  security-reader permissions.
- Define retention, clock synchronization, integrity, export, deletion/legal,
  availability, and incident-query procedures.
- Alert on invalid clients/audiences, repeated authentication failures, scope or
  RBAC denials, cross-customer attempts, admin/MFA changes, revocation failures,
  secret detections, configuration drift, and unusual database access.
- Keep raw tokens, headers, claims, secrets, PII, request/response bodies, and
  database URLs out of the audit pipeline.

## Acceptance

- One direct gRPC and one MCP request produce a complete correlated chain.
- Authorized operators can diagnose by request ID without sensitive payloads.
- Unauthorized roles cannot read or modify audit records.
- Redaction and tamper/retention tests pass.
- Audit outage behavior is explicit and does not fabricate successful evidence.

## Out of scope

Using raw application logs as BI data, storing prompts/profile/order contents,
and exposing internal audit records to LLM clients.

