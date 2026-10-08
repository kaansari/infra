# Phase 3 PR 02: Self-scoped preference gRPC contract

Repositories: `contracts-repo`, documentation/inventories  
Depends on: PR 01 design (not live tool exposure)

## Objective

Add `preference.PreferenceService` and typed messages for definitions,
preferences, context retrieval, previews, confirmations, and operation status.
This is a domain service implemented inside `ceerat-user-service`, not a new
binary.

## Contract surface

```text
GetMyPreference
ListMyPreferences
GetMyPreferenceContext
SearchPreferenceDefinitions
PreviewMyPreferenceUpsert
UpsertMyPreference
PreviewMyPreferenceDeletion
DeleteMyPreference
GetMyPreferenceOperationStatus
```

All requests are self-scoped and contain no customer/user/tenant/role/scope
selector. Use opaque IDs, bounded stable page tokens, explicit filters, positive
resource/profile versions, idempotency keys, and typed operation status.

## Model rules

- Add enums for five levels, typed value kind, scope kind, match kind, operation
  kind/state, and upsert result kind.
- Use a protobuf `oneof` for exactly one typed value. Reuse canonical
  `commerce.Money`; represent general decimals canonically as validated strings,
  not `double`.
- Scope uses explicit context/entity fields with operation-dependent validation.
- Add an allowlisted consumer-domain/purpose selector for minimized context
  retrieval and server-owned `consumer_domains` definition metadata. Include
  `txse_intelligence` without adding market-data payloads to this contract.
- Instrument/watchlist references remain bounded opaque entity identifiers; no
  environment, entitlement, book health, formula, position, or trading field is
  accepted as preference authority.
- Separate full customer projection, compact context item, definition, preview,
  confirmed result, and operation-status messages.
- Previews return normalized before/after, profile/resource versions, safe
  warnings, fingerprint, and expiry; confirmation carries validated reviewed
  inputs/idempotency required by the service, never customer identity.
- Reserve retired field numbers/names during iteration; generate and commit Go
  output. Do not retain draft aliases.

## Security and inventories

Add every method to `KnownGRPCMethods` and customer default role permissions;
add none to `DefaultPublicMethods`. Update contract and service inventories as a
coordinated declared surface. Validate that generic builder CRUD suggestions do
not replace the explicit `My` methods.

## Tests and gates

- Proto/mapper tests for every valid/invalid value, scope, filter, bound, enum,
  version, ID, and mutually exclusive field combination.
- Prove no trusted identity or arbitrary JSON field is accepted.
- Prove TXSE consumer context cannot select UAT/PROD/DR, entitlement, data class,
  health, provenance, formula version, or suppress required warnings.
- RBAC/public allowlist and inventory parity tests.

```text
make proto
go test ./...
go build ./...
ceerat-builder impact contract preference.PreferenceService --add Preference --output json
ceerat-builder rbac check --output json
ceerat-builder check drift --output json
```

## Out of scope

Database/service implementation, public tools, admin definition mutation,
generic CRUD, new binary, REST, browser UI, legacy/compatibility contract.

## Implementation record (2026-09-14)

Implemented `preference.PreferenceService` with the nine approved self-scoped
RPCs, closed typed value/scope models, exact `commerce.Money`, positive-version
contract fields, preview/confirm fingerprints and expiry, operation-state
reconciliation, and server-owned consumer-domain metadata including the bounded
TXSE Intelligence consumer profile. Generated Go and gRPC output is committed.

All methods are known, customer-role protected, absent from public and agent
permissions, and represented in contract/service inventories as contract-only
until the Phase 3 service PR registers the implementation. Reflection tests
prove requests expose no customer/user/tenant/role/OAuth or TXSE environment,
entitlement, health, classification, formula, position, warning-suppression, or
trading-authority selector. `make proto`, `go test ./...`, `go build ./...`,
builder RBAC, and builder drift checks pass. No database, handler, MCP tool,
public method, runtime registration, or compatibility route was added.

## Acceptance completion (2026-10-07)

Closed the remaining contract acceptance gaps with reusable request/value/scope,
definition/projection/preview/operation-status, and response-envelope validators
in the contracts package. Bounds and selector policy are documented in
`contracts-repo/packages/ceerat-contracts/proto/preference/README.md`. Validators
reject recursively unknown wire fields; the strict JSON adapter rejects unknown
members and ambiguous oneof input. Errors contain fixed field paths only.

Contract tests now cover all seven value kinds, exact canonical decimal/money
handling, scope exclusivity, allowlisted filters/consumer purposes, IDs and list
bounds, positive versions and the create-only resource-version absence sentinel,
canonical/custom input combinations, reviewed fingerprints/expiry, normalized
before/after consistency, compact match kinds, and operation/error-envelope
invariants. A closed request-graph reflection test prevents nested identity,
arbitrary JSON, and TXSE authority fields. TXSE context tests reject environment,
entitlement, classification, health/provenance/formula/position/trading and
warning-suppression selectors while allowing bounded instrument/watchlist refs.

The shared domain value union and validated mappers preserve false, zero, exact
decimals and canonical money, copy mutable lists, and reject malformed values.
The contract inventory includes the complete preference message surface and the
new domain types/mappers. No field numbers were retired or reassigned and no
compatibility aliases were introduced.

Builder impact guidance now projects the existing nine reviewed RPCs instead
of proposing generic preference CRUD. Regression tests check this behavior,
contract/service inventory parity, customer-only protected permissions and the
unchanged generic hints for other capabilities.

Verified locally: `make proto`, `go test ./...`, `go test -race ./...`,
`go build ./...`, all 19 builder unit tests, and the required builder impact,
RBAC and drift commands. RBAC/drift reported no issues. An independent code
review found no critical or important defects; its two minor projection/error
bound findings were corrected and covered by regression tests.

These are contract checks, not live service acceptance. The owning service must
invoke the helpers and independently enforce authentication, ownership, current
definition policy, signed subject/filter-bound pagination, fingerprint/expiry
binding and transactional idempotency in later PRs. Runtime handlers, schema,
public tools and deployment remain outside PR 02.
