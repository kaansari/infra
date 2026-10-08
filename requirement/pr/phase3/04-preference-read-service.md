# Phase 3 PR 04: Preference read and definition service

Repository: `services-repo`  
Depends on: PRs 02–03

## Objective

Implement the four private read RPCs through the new preference module in the
existing `ceerat-user-service`:

```text
GetMyPreference
ListMyPreferences
GetMyPreferenceContext
SearchPreferenceDefinitions
```

## Behavior

- Resolve the authenticated user to its customer; accept no ownership selector.
- Get conceals missing/foreign IDs with the same `NOT_FOUND` result.
- List supports bounded category/scope/enabled/query filters and stable opaque,
  subject/filter-bound pagination.
- Definition search returns only enabled definitions for new selection while an
  existing preference can still render its snapshotted/linked disabled
  definition safely.
- Context requires bounded categories, optional context/entities, explicit
  include-global policy, deterministic precedence ordering, compact projection,
  profile version, truncation indicator, and deterministic safe summary.
- TXSE requests require consumer purpose `txse_intelligence`, return only its
  allowlisted categories, and preserve opaque instrument/watchlist references
  without dereferencing. Failure returns a safe error; the TXSE caller—not this
  service—uses documented defaults and never degrades market-data controls.
- Do not call an LLM, infer relevance from natural language, resolve conflicts,
  or dereference entity/context keys.
- Treat stored strings as untrusted data; deterministic guidance comes only from
  reviewed server templates. Custom preferences return no executable guidance.

## Security and observability

JWT -> RBAC -> logging -> handler remains intact. Repositories repeat customer
predicates. Apply deadlines and query/result limits. Logs include request ID,
method, pseudonymous actor, safe filter category/counts, result count, profile
version, outcome, and latency—not query text, preference fields, values, notes,
summary, page token, or returned body.

## Tests and gates

- Authentication/RBAC and two-customer ownership isolation for every method.
- Exact canonical/custom projections, definition disabled/version behavior,
  category/context/entity/global ordering, conflicts retained, deterministic
  summary, truncation, empty state, and no fallback.
- Stable pagination across filter changes/concurrent mutation; tampered/foreign
  tokens rejected.
- Prompt-like stored data remains quoted data and cannot change service flow.
- Dependency/timeouts map to safe gRPC errors with no content leakage.
- Prove context cannot override explicit input, entitlement, source environment,
  health/freshness/provenance, data classification, signal version, or warnings.

```text
go test -race ./services/ceerat-user-service/preferences/...
go test ./services/ceerat-user-service/...
go build ./services/ceerat-user-service/...
ceerat-builder verify contract-and-service preference.PreferenceService --output json
ceerat-builder rbac check --output json
ceerat-builder check drift --output json
```

Deploy `ceerat-user-service` only after the PR 03 schema preflight passes live;
then use authenticated grpcurl/service smoke tests before public tools exist.

## Out of scope

Writes, MCP, model inference, embeddings, cross-customer/admin reads, REST,
browser UI, legacy or parallel implementation.


## Implementation record (2026-10-08)

The existing user service registers all four private reads through its unchanged
OAuth/identity/scope/RBAC/logging chain. Read-only repeatable-read transactions
resolve customer ownership and profile version together. Lists and enabled
catalog searches use bounded literal filters, stable ordering and encrypted
15-minute subject/filter/method/snapshot-bound cursors. Profile or matching-row
changes invalidate continuation with ABORTED, including direct maintenance SQL.
Disabled/older linked definition snapshots remain renderable.

Context preserves exact typed projections, entity/context/global ordering and
all conflicts, explicit global inclusion, deterministic counts-only summary,
profile/resource versions and row/128-KiB truncation. Custom strings remain data
without executable guidance. TXSE admits only reviewed catalog/options and
bounded opaque references; static hints cannot override market-data controls.
Reads insert no profiles and supply no fallback. Two-second deadlines and
PostgreSQL statement timeouts bound dependency failures; errors and audit logs
exclude request/response contents, raw IDs, query text, tokens and database detail.

Verification used real isolated PostgreSQL schemas: preference race tests, full
service tests and build, contract tests and build, Render vendor build and
vendor-backed preference race tests, signed JWT/scopes/RBAC gRPC
tests with two customers, cursor mutation/expiry/tampering, byte-limit pagination,
blocked-dependency deadline, typed zero/false/decimal/money/options, disabled
catalog/version snapshots, custom prompt-like strings and authority rejection.
Builder contract-and-service returned its verification checklist; RBAC and drift
checks passed without issues. Independent read-only review found no remaining
actionable issues after correcting startup constructor handling.

The Render blueprint declares `CEERAT_PREFERENCE_PAGE_TOKEN_KEY` as an operator
secret: standard base64 of 32 random bytes, shared across replicas. The missing
preference protobuf/validator package is added to the checked-in vendor bundle
without refreshing unrelated contracts. Production
startup fails closed without it. Module/API/security/logging/architecture/testing
docs and the nine-method inventory describe four implemented reads and five
planned mutation/reconciliation methods. No schema migration or live deployment
was performed for PR04. Hosted release remains gated on live PR03 schema
preflight, configured pagination secret and authenticated service smoke tests.
