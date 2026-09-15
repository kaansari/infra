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
