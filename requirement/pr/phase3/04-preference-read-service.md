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
