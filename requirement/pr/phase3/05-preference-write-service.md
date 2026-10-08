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


## Implementation record (2026-10-08)

All five write/preview/reconciliation RPCs are implemented in the existing
registered preference service through the unchanged OAuth/identity/scope/RBAC
chain. Previews are read-only and return complete normalized before/after,
static warnings, versions, fingerprint and 15-minute expiry. Purpose-separated
HMAC authenticates user/customer, normalized input/key, full before/after and
catalog metadata. Definition metadata changes invalidate review even without a
version bump. Create is explicit; updates cannot retarget identity or scope.

Confirmation serializes on the customer profile and locks preference/catalog
before atomically applying active data, profile increment, digest-only history
and a replayable encrypted result. Same key/digest replays the original snapshot
after updates/deletion/restart; changed input/kind conflicts. Known rejected
confirmations can persist a safe failed record without active data/history
changes. Dependency failure rolls back. Deadline or uncertainty after dispatch
instructs self-scoped reconciliation with the original kind/key, never automatic
retry. Status supports completed/failed/pending/unknown; missing, foreign or
expired results are unknown, never proof of failure.

Additive immutable `20261009_phase3_preferences_replay.sql` introduces bounded
nullable AEAD result bytes, plus development rollback and strict runtime/operator
preflight. Original applied files remain unchanged. The local checksum-ledger
runner applied migration 17 and all preflights passed. Operation keys, request
and before/after/actor content persist only as keyed digests; the exact replay
projection is encrypted/authenticated to customer/operation. Retention is 30
days; bounded history-before-operation SKIP LOCKED cleanup remains safe across
instances. A SQL restore requires the separately retained configured secret to
recover encrypted replay. No cleanup scheduler or hosted deployment was added.

Independent review found keyword-only custom filtering could admit unnamed
market records. It was replaced with documented closed personal schemas:
`custom.<personal category>.note/enabled/rating/weight/budget/style/attributes`,
fixed safe labels, global scope, reviewed descriptor strings/options, bounded
rank/relative weight and whole-dollar USD personal budgets. Arbitrary text,
encoded records, market/control keys and market-bearing references are rejected.
Existing custom records remain readable/deletable; updates must meet the new
policy. Expanding custom writes requires server review. Canonical TXSE writes
remain limited to reviewed catalog/options and never grant control authority.

Verification covers real PostgreSQL canonical/custom lifecycle, typed values,
invalid catalog/type/scope/key/value, stale resource/profile/definition/metadata,
tampered/expired/foreign fingerprints, exact replay after deletion/restart,
changed payload/kind, atomic rollback/lost reply/deadline reconciliation,
completed/failed/pending/unknown status, encrypted result corruption/logical
record restore, retention, migration apply/reapply/rollback/preflight, and the
specified mutation/definition-disable races. Signed JWT/scopes/RBAC tests cover
all nine RPCs and two-customer isolation. Required preference race/full service
tests and builds passed, including the Render vendor build/race tests; contract
and builder RBAC/drift/app checks passed. The builder verification command
returned its contract/service checklist. Review issues were corrected with
value-level regression coverage; no remaining confirmed runtime findings.

Inventory and API/security/logging/architecture/testing/module docs now describe
all nine implemented methods and recovery policy. Hosted deployment remains a
separate gate: apply replay migration and all live preflights, configure/preserve
the shared secret, then perform authenticated authorized smoke tests.
