# Phase 3 PR 08: Preference security and resilience integration

Repositories: `contracts-repo`, `services-repo`, `apps-repo`, `infra`  
Depends on: PRs 01–07

## Objective

Run the reduced but real cross-repository security/resilience gate before live
customer testing. Fix defects in their owning earlier slice rather than adding
compatibility behavior here.

## Required matrix

### Identity and authorization

- missing, malformed, expired, not-yet-valid, wrong issuer/audience/algorithm
  token; missing read/write scope; revoked grant/session; wrong role;
- two customers with identical logical keys cannot read, paginate, preview,
  confirm, delete, or reconcile each other's data;
- no public or private request accepts customer/user/tenant/role/scope authority.

### Typed data and prompt safety

- fuzz closed protobuf/MCP value and scope unions, unknown fields, sizes,
  control characters, markup, role/tool/instruction strings, secret-like text,
  money currency/range, decimal canonicalization, and list limits;
- prove stored strings cannot alter gateway/service control flow and are never
  treated as system/developer instructions;
- context minimization returns only requested/global categories and never an
  unrelated preference dump.

### Concurrency and outcomes

- concurrent logical upsert, update/delete, double confirm, stale versions,
  idempotent replay/conflict, preparation reuse/expiry, definition change;
- database restart, gateway restart, multiple instances, timeout before
  dispatch, crash after commit/before response, audit/idempotency dependency
  failure, and status reconciliation without retry;
- stable subject/filter-bound pagination and cache separation/invalidation.

### Privacy and observability

Scan MCP responses/errors, gRPC errors, structured logs, traces, audit rows, and
test artifacts for fixture values, notes, names, queries, summaries, tokens,
raw keys/idempotency, page tokens, SQL/topology, and cross-customer IDs. Only
approved safe hashes/counts/versions/request IDs may remain.

### Deployment skew

Test old/new combinations and fail closed when contract, schema, service, OAuth
metadata, or gateway are mismatched. Readiness must exercise an authenticated
private preference RPC, not only process liveness.

### TXSE Intelligence boundary

- prove saved preferences cannot broaden OAuth/product entitlement or alter
  environment, data classification, formula version, source provenance,
  freshness/book health, degradation state, or mandatory warnings;
- prove prompt-like custom values cannot become investment/trading instructions;
- prove opaque instrument/watchlist references are not dereferenced by the
  preference service and no FEED/book/signal/position data is persisted there;
- fail preference retrieval independently while TXSE ingest/recovery/book stays
  healthy and intelligence uses documented defaults with all safety fields;
- scan combined projections and logs for reconstructable Exchange Data and
  cross-customer preference leakage.

## Gates

```text
make proto
go test -race ./...
go build ./...
make verify-platform
ceerat-builder rbac check --output json
ceerat-builder check apps --output json
ceerat-builder check drift --output json
ceerat-builder verify contract-and-service preference.PreferenceService --output json
```

Add a repeatable local/integration harness with disposable PostgreSQL state and
redacted machine-readable results. Record exact contract/service/gateway commit
tuple. All failures must be fixed before PR 09; do not waive them with docs.

## Out of scope

New product features, UI, performance scale certification, REST, legacy,
fallback, or parallel implementations.
