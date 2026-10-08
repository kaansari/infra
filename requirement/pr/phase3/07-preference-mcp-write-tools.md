# Phase 3 PR 07: Preference MCP prepare/confirm tools

Repository: `apps-repo`  
Depends on: PR 06 and live PR 05 write path

## Objective

Expose persistent preference changes through four explicit tools:

```text
preferences_upsert_prepare
preferences_upsert_confirm
preferences_delete_prepare
preferences_delete_confirm
```

Do not add direct `preferences_upsert` or `preferences_delete` aliases.

## Preparation

Prepare tools require `ceerat.preferences.write`, are read-only at the domain
level, call the matching preview RPC, and persist a short-lived gateway
preparation bound to subject, OAuth client, operation, normalized preview,
resource/profile/definition versions, service fingerprint, idempotency key
hash/digest, and expiry.

The upsert schema supports one closed typed value shape without ambiguous
top-level `oneOf`; runtime repeats exact mutual-exclusion validation. Delete
accepts an opaque preference ID, expected versions, and fresh idempotency key.

Return a complete customer-readable preview and stop. Tool descriptions require
the model to ask for explicit confirmation and prohibit saving inferred
preferences without user agreement.

For TXSE categories, the preview explicitly labels the setting as a preference,
not an entitlement, market fact, recommendation, or trade authorization. Reject
attempts to store environment selection, warning suppression, formula override,
positions, suitability conclusions, or raw/reconstructable Exchange Data.

## Confirmation

Confirm tools require `ceerat.preferences.write` and accept only:

```json
{"preparation_id":"...","confirmed":true}
```

Atomically consume the durable preparation before one private confirmation
dispatch. Recheck current OAuth authorization and binding. Known pre-dispatch
failures are `not_started`; uncertain post-dispatch results are
`outcome_unknown`, non-retryable, and direct the model to
`preferences_operation_status` with the original operation kind/key.

Delete confirmation is destructive. Upsert confirmation is consequential and
reversible but still explicitly confirmed. Accurate MCP annotations never
replace server enforcement.

## Tests and gates

- Closed schema for every typed value/scope, hosted-client compatibility, and no
  identity or definition-authority injection.
- Preparation user/client/operation/digest/expiry binding, single use, restart,
  horizontal-instance concurrency, and scope revocation between steps.
- Explicit confirmation only; no model-controlled mutation after preview.
- Replay/conflict/unknown outcome/status guidance and no blind retry.
- Rate limits and logs/errors redact all preference content, preparation body,
  raw idempotency key, token, and page token.

```text
env GOWORK=off go test ./...
env GOWORK=off go build ./...
ceerat-builder app-context ceerat-agent-gateway --output json
ceerat-builder check apps --output json
ceerat-builder check drift --output json
```

After deploy, verify live schemas and create a new hosted app version before any
human write test.

## Out of scope

Direct writes, bulk import/delete, definition mutation, automatic inference,
REST/browser/legacy/fallback/parallel paths.

## Implementation record — 2026-10-08

Implemented locally in the existing gateway: the four write-scope prepare/confirm
tools, canonical private method policies, Preferences grouping, catalog version
0.3.1, complete projected previews, flat closed typed input schemas and explicit
confirmation-only arguments. Prepare tools stop for user agreement; no aliases,
automatic inference, browser/REST route or direct preference database access was
added. Private catalog/personal-data policy remains the authority for prohibited
TXSE/Exchange Data content.

The existing gateway startup schema routine now creates
`ceerat_agent_gateway.preference_preparations`. Durable records bind the exact
private confirmation request and preview to user/subject/client/operation,
versions/fingerprint, key digest, content digest and expiry. A conditional update
checks byte-exact payload, current token lifetime/scope, revocation and binding
before one dispatch. Consumed preparations never dispatch again. Restart and
multiple instances share consumption state. Development without the existing
production-required database URL retains the normal memory-only behavior.

Known rejections are `not_started`; ambiguous post-dispatch results are
non-retryable `outcome_unknown` with operation-status guidance. Private
FailedPrecondition is conservatively uncertain because the service also uses it
for unknown outcomes. Successful results must match the reviewed preference and
profile version before projection. Errors and audit logs exclude raw content,
keys, preparation bodies, tokens and pagination; reconciliation uses the original
key from the prepare request/result instead of echoing it in errors.

Verification covers all seven value variants and three scopes, exact numbers,
mutual exclusion, hosted-compatible schemas/snapshots, authority injection,
missing explicit confirmation, immutable payloads, subject/user/client/operation/
digest/expiry binding, scope removal and revoked grants, replay/conflict/lost reply/
deadline/malformed response, status-only recovery, limits and redaction. Signed
JWT tests traverse real gRPC for preview/confirm and reduced-scope/foreign-subject
rejection. Real local PostgreSQL race tests exercise restart, payload tampering,
expiry/operation binding and concurrent confirmations across two instances with
exactly one write. Local gRPC fixtures test transport; production policy remains
covered by the owning service's integration suite.

Hosted deployment was not performed. Live PR05 write acceptance, live schema
inspection and a new/refreshed hosted app version remain required before any
human write test. Gateway backup/restore must preserve consumption state; an old
preparation snapshot is never permission to replay a write. Startup cleans expired
records after a one-day grace period. See the gateway README for operational
bounds and recovery instructions.

Final gates passed: `GOWORK=off go test ./...`, full `go test -race ./...`,
`GOWORK=off go build ./...`, real PostgreSQL durability/concurrency race tests,
canonical security/preference contract tests, builder app-context, apps and drift
checks. Fresh review and follow-up review reported no actionable findings.
