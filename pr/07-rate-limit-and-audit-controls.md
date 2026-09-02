# PR 07: Rate limiting and audit controls

Repository: `apps-repo`

Depends on: PR 02 and PR 04

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
