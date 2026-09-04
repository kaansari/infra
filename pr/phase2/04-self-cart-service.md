# Phase 2 PR 04: Self-cart service enforcement

Repository: `services-repo`  
Depends on: Phase 2 PR 03  
Owner: `service.ServiceManager`

## Objective

Implement the five self-cart RPCs by deriving the customer exclusively from the
authenticated internal user context. No caller field, metadata value, or
gateway assertion may choose the cart owner.

## Explicit database migration

Add a sortable, idempotent SQL migration such as:

```text
services/ceerat-user-service/migrations/20260904_phase2_self_cart.sql
```

It must:

- backfill `carts.version` to `1` where missing or zero, then enforce `NOT NULL`
  and default `1` without overwriting versions greater than `1`;
- create `cart_idempotency_keys` with text UUID ID, customer ID, operation,
  bounded idempotency key, normalized request hash, closed state, result cart
  version, safe result reference/payload if required, timestamps, and expiry;
- enforce uniqueness on `(customer_id, operation, idempotency_key)`;
- add customer/expiry/reconciliation indexes, foreign keys, and closed-state
  checks needed by the repository;
- store no tokens, OAuth claims, credentials, prompts, request bodies, or PII;
- be safe to apply repeatedly using catalog checks or idempotent DDL;
- avoid destructive table recreation, broad locks, and cart data loss.

Add the matching GORM entity and startup registration, but treat the reviewed
SQL file as the production deployment artifact. Add a schema preflight that
fails rollout if required columns, constraints, or indexes are absent.

Provide a down/rollback script only for objects introduced by this phase.
Rollback must prove no records are in flight and must not undo the cart-version
backfill or drop cart data. When destructive rollback is unsafe, document
roll-forward as the production recovery path.

## Read and mutation behavior

`GetMyCart` requires an authenticated customer, resolves
`CustomerIDForUser(authenticated_user.id)`, and returns that cart. Mutations
resolve the same identity before repository work, then atomically compare
`expected_version`, validate product/variant and inventory, calculate
server-owned prices/totals, mutate, increment `Cart.version`, and persist the
idempotent outcome.

Bind each idempotency key to user/customer, RPC, normalized input hash, and
result. Same key/same input returns the original result; same key/different input
fails. Reject cross-cart item IDs, stale versions, inactive inventory, invalid
quantities, and caller-controlled pricing. An uncertain commit directs callers
to read the cart before deciding whether to retry.

Delete the old customer-ID-shaped cart handlers and their request-path tests.
There is no admin/agent cart-owner selector in this system; any future support
workflow must be designed as a separately authorized operation rather than
reusing customer self-service RPCs.

## Tests

Cover missing authentication, wrong role, missing mapping, Users A/B isolation,
forged item IDs, duplicate/concurrent adds, same-key mismatch, stale versions,
inventory races, price authority, rollback, uncertain commit, restart/shared
storage, safe logs/errors, and absence of the old RPC implementations.

### Migration tests

- Apply to an empty PostgreSQL schema.
- Apply to a representative pre-change schema with cart versions `0`, `1`, and
  greater than `1`; verify the exact backfill.
- Apply twice and prove the second application succeeds without changes.
- Validate types, defaults, nullability, checks, foreign keys, unique keys, and
  indexes through PostgreSQL catalogs.
- Exercise approved rollback/roll-forward and reapply.
- Inject a transactional migration failure and prove readiness never reports a
  partially migrated schema as usable.

### Repository and gRPC integration tests

- Use a disposable PostgreSQL schema, never an in-memory replacement.
- Start the real repository and gRPC handler with JWT/RBAC interceptors.
- Create synthetic Users A/B, customers, products, variants, carts, and
  inventory fixtures transactionally; delete the schema after the suite.
- Prove ownership, cross-user denial, active-product validation, server pricing,
  version conflict, idempotent replay, key/input mismatch, concurrent duplicate
  calls, rollback, and persistence across service restart.
- Confirm one concurrent mutation commits, duplicates do not create a second
  effect, and errors/logs reveal no other-user identifiers.
- Assert service audit/log records cover every read/write attempt and outcome,
  use the propagated request ID, hash resource/idempotency references, and omit
  request bodies, SQL values, authenticated claims, and credentials.
- Inject audit-sink failure: reads follow the documented availability policy;
  mutations fail before repository dispatch when the durable attempt record is
  unavailable.

## Builder-agent gate

Run the common workflow plus:

```bash
ceerat-builder decide-owner "self-scoped customer cart" --output json
ceerat-builder patterns service --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder evidence request "ServiceManager self-cart ownership idempotency transaction" --output json
ceerat-builder docs service --output json
```

Also run the repository migration targets and focused suites:

```bash
make migrate-local
make migrate
go test ./services/... -count=1
go test -race ./services/... -count=1
```

CI supplies a disposable PostgreSQL database. Never run migration tests against
the shared live database.

## Acceptance

Direct private gRPC tests prove the service—not ChatGPT or the gateway—enforces
identity, ownership, price, inventory, version, and idempotency. Service tests,
race tests, migrations, build, vet, static analysis, inventories, builder drift,
and aggregate platform verification pass.

Deployment order is schema preflight → forward SQL migration → service binary
→ private gRPC smoke test. On failure, stop before gateway deployment and use
the tested rollback or roll-forward runbook.
