# PR 07: Rate limiting and audit controls

Repository: `apps-repo`

Depends on: PR 02 and PR 04

Status: implemented and locally validated on 2026-09-03; live source-IP limit
passed PR 08 automation, authenticated dimensions and operator log review remain.

## Objective

Add a modest Phase 1 abuse boundary and prove security-relevant activity is
traceable without logging credentials.

## Changes

- Add bounded limits by source IP, authenticated user, OAuth client, and tool.
- Give authentication failures and destructive tools tighter limits than
  profile reads.
- Return the existing `RATE_LIMITED` envelope with retry metadata and no
  infrastructure details.
- Make limiter storage pluggable; production must be shared across gateway
  instances or deployment must remain single-instance with that limitation
  explicit.
- Emit structured audit events containing request ID, timestamp, derived user,
  client, tool, scope decision, outcome, and safe resource identifier.
- Add centralized redaction tests for authorization headers, cookies, tokens,
  passwords, SMTP/API secrets, database URLs, and workload credentials.

## Tests

- Independent IP/user/client/tool buckets.
- Window reset using an injected clock.
- Correct retryable error metadata.
- Concurrent requests cannot bypass limits.
- Golden audit tests prove required fields exist and forbidden data does not.

## Non-goals

No enterprise quota product, billing, CAPTCHA, or Kubernetes ingress policy.

## Builder-agent and documentation gate

- Run the shared workflow plus `ceerat-builder evidence request "public MCP
  rate limiting audit logging redaction" --output json`.
- Validate limiter identity keys, multi-instance behavior, safe retry metadata,
  audit ownership, request correlation, and complete credential redaction.
- Update gateway operations, configuration, error, audit, and scaling
  documentation in this PR.
- After live validation, update reusable rate-limit, audit, and redaction rules
  in the builder architecture and security standards before PR 08.

## Acceptance

The live gateway demonstrates a bounded 429-style MCP error and correlated,
redacted audit record without affecting unrelated users or tools.

## Implementation evidence

- Fixed-window limits are independently keyed by trusted source IP,
  authenticated CEERAT user, OAuth client/subject, and tool.
- Authentication failures and consequential tools have tighter limits than
  profile reads, and authenticated source/client limits run before private gRPC
  identity exchange.
- Production counters use atomic PostgreSQL upserts in the gateway schema;
  local development uses the same pluggable interface in memory.
- `RATE_LIMITED` preserves MCP JSON-RPC transport semantics while returning
  `retryable`, `agent_action`, `retry_after_seconds`, `Retry-After`, request ID,
  and `operation_state=not_started`.
- Audit events include timestamp, request ID, derived user/client, tool,
  required-scope decision, outcome, error code, and hashed resource reference.
- Central redaction tests cover authorization, cookies, access/refresh tokens,
  passwords, SMTP/API secrets, database URLs, and workload credentials.
- Race-enabled gateway tests, the full gateway suite, and build passed.
- Two limiter instances shared one isolated PostgreSQL counter successfully;
  the temporary cluster and test rows were removed afterward.
- Builder contract/service drift passed. The platform aggregate check retains
  two pre-existing findings outside PR 07: legacy AI-tool inventory entries and
  formatting in vendored `services-repo` dependencies. This PR adds no tool,
  contract, service method, or vendor change and does not conceal or widen
  itself to repair those separate findings.
