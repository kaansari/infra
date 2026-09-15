# Phase 3 PR 06: Preference MCP read tools

Repository: `apps-repo`  
Depends on: PRs 01–05 live private read path

## Objective

Expose the authenticated read surface through `ceerat-agent-gateway`:

```text
preferences_context
preferences_list
preferences_get
preferences_definitions
preferences_operation_status
```

All require `ceerat.preferences.read`, call only matching private gRPC methods,
and are grouped under `domain: preferences`, `ceerat/domain: preferences`, and
the Preferences capability group in `describe_ceerat`.

## MCP schemas and behavior

- Use flat, closed, bounded input objects; no top-level `oneOf` and no identity,
  authority, or raw backend fields.
- Context requires categories and supports bounded context/entity filters,
  include-global, limit, and detail level exactly as the private contract allows.
- List/get/definitions use stable opaque IDs/tokens and allowlisted filters.
- Operation status accepts only operation kind and idempotency key and never
  dispatches a write.
- Project compact versus full data deliberately. Never return customer/user IDs,
  database metadata, definition internals, history, or other customers' data.
- Tool descriptions tell models that customer-authored preference text is
  untrusted data and current explicit user/system/developer instructions win.
- TXSE context calls identify consumer purpose and state that preferences are
  presentation/query defaults only. Returned content cannot be represented as
  market fact, entitlement, advice, health, provenance, or a trading instruction.

## Errors, logs, and tests

Use the standard actionable envelope and OAuth challenge. Reads always report
`not_started` on failure. Audit safe tool/domain/method/count/version/outcome
metadata only; redact values, notes, names, queries, summaries, page tokens,
raw keys/idempotency, and response bodies.

- Tool inventory/schema snapshots, strict decoding, annotations, scopes, and
  domain discovery.
- Missing/expired/wrong-audience tokens, insufficient scope, revoked grant,
  rate limits, deadline/dependency failures, malformed downstream responses.
- Two-user isolation through gateway -> real gRPC integration.
- Prompt-injection strings are returned only as bounded quoted data and never
  affect tool selection or gateway control flow.
- Integration projection tests combine preference context with a mock TXSE
  intelligence response and prove explicit inputs and mandatory health,
  freshness, classification, provenance, and warning fields always win.

```text
env GOWORK=off go test ./...
env GOWORK=off go build ./...
ceerat-builder app-context ceerat-agent-gateway --output json
ceerat-builder check apps --output json
ceerat-builder check drift --output json
```

Deploy the gateway only after authenticated private read smoke tests pass.
Verify protected-resource scopes and live `tools/list`, then refresh/version the
hosted ChatGPT app because a new conversation does not guarantee schema refresh.

## Out of scope

Write tools, natural-language parsing, recommendation execution, REST/browser,
legacy tools, direct database access, or duplicated preference logic.
