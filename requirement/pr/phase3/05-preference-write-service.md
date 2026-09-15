# Phase 3 PR 05: Preference write, idempotency, and reconciliation service

Repository: `services-repo`  
Depends on: PR 04

## Objective

Implement domain-authoritative preview and confirmed mutation:

```text
PreviewMyPreferenceUpsert
UpsertMyPreference
PreviewMyPreferenceDeletion
DeleteMyPreference
GetMyPreferenceOperationStatus
```

## Upsert rules

- Canonical writes resolve the current enabled definition and validate category,
  type, allowed values, and supported levels.
- TXSE-oriented writes are limited to the reviewed typed catalog. Reject keys or
  values purporting to grant data access, select environment, alter formulas,
  suppress health/licensing warnings, record holdings/suitability, or authorize
  market actions.
- Custom writes require a valid `custom.<category>.<slug>` key, safe bounded name,
  and typed value; they cannot shadow canonical definitions.
- Normalize logical identity exactly once. Create or update is explicit in the
  preview. Updating by ID cannot retarget key/scope.
- Preview returns complete normalized before/after, deterministic display and
  safe guidance, expected preference/profile versions, fingerprint, warnings,
  and expiry without mutation.

## Delete rules

Preview reads and identifies the owned active preference and describes exact
removal/retention semantics. Confirm deletes the active record and increments
profile version; policy-required history/idempotency is not misrepresented as
full erasure. Missing and foreign IDs remain indistinguishable.

## Transaction and outcome rules

Confirmation validates current JWT/RBAC/ownership, expected versions,
fingerprint, expiry, and fresh idempotency key; locks in documented order;
applies preference/profile/history/operation changes atomically; and persists a
replayable result before response.

Same key/same digest returns `replayed=true`; changed input conflicts. A timeout
after dispatch is never retryable and is reconciled by self-scoped operation
kind plus original idempotency key. Cleanup retains results for the documented
window and is safe under restart/horizontal instances.

## Tests and gates

- Canonical/custom create/update/delete and every invalid type/scope/key/value.
- Stale preference/profile/definition/fingerprint/expiry fail before mutation.
- Replay, changed-payload conflict, crash after commit/before response,
  operation-status pending/completed/failed/unknown, restart, and cleanup.
- Races: create/create logical identity, update/update, update/delete,
  confirm/confirm, and definition-disable/confirm; one deterministic winner.
- History and logs contain no raw preference content, prompts, queries, tokens,
  raw keys, or raw idempotency values.
- No TXSE raw/reconstructable data, signal evidence/history, portfolio, position,
  or entitlement is persisted through custom preferences.

```text
go test -race ./services/ceerat-user-service/preferences/...
go test ./services/ceerat-user-service/...
go build ./services/ceerat-user-service/...
ceerat-builder verify contract-and-service preference.PreferenceService --output json
ceerat-builder check drift --output json
```

## Out of scope

Direct unpreviewed writes, definition mutation, hard audit erasure claims,
cross-customer operations, REST/browser/legacy/fallback paths.
