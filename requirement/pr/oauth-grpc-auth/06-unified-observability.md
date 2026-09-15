# PR 06: Unified gRPC/MCP tracing and authorization logs

Repositories: `contracts-repo`, `services-repo`, `apps-repo`, `infra`  
Depends on: PR 05

## Objective

Make direct gRPC and MCP-originated gRPC requests produce equivalent, safe,
correlatable security and operational evidence.

## Work

- Define and validate `x-request-id` and W3C `traceparent` metadata contracts.
- MCP creates or validates a request ID and forwards it to gRPC; direct gRPC
  accepts a bounded valid value or creates one server-side.
- Log transport/origin, method/tool, request ID, trace ID, OAuth client ID,
  issuer identifier, subject/session/token safe digest, CEERAT user/customer safe
  identifier or digest, required scopes, authorization decision, gRPC status,
  operation state, and duration.
- Record separate gateway-early and gRPC-authoritative decisions under the same
  trace without claiming the gateway decision executed the handler.
- Redact authorization metadata, raw tokens, claims, PII, request/response
  bodies, passwords, codes, secrets, idempotency keys, and database topology.
- Ensure identity-resolution, scope, RBAC, ownership, and handler failures have
  stable categories and do not become generic dependency errors at MCP.
- Add cross-log acceptance tooling based on synthetic safe fixture IDs.

## Tests

- direct gRPC and MCP calls correlate to the same downstream request/trace;
- malformed/oversized/spoofed correlation metadata is replaced or rejected;
- auth, scope, RBAC, ownership, validation, dependency, and unknown-outcome log
  classifications;
- secret/PII scanners over logs, traces, errors, and test artifacts;
- concurrent requests do not cross-contaminate actor or trace context.

## Gates

```text
go test -race ./...
make verify-grpc-oauth
make verify-api-security
ceerat-builder check drift --output json
```

## Out of scope

New telemetry vendor, payload logging, browser analytics, UI tracing, and
business-domain behavior changes.

## Documentation after PR

Update service and gateway logging/security docs, incident lookup instructions,
and safe evidence examples. Update builder logging standards only after tests
and human validation pass.

