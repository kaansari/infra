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
