# Phase 2 PR 02: Product catalog read tools

Repository: `apps-repo`  
Depends on: Phase 2 PR 01  
Owner behind gateway: `service.ServiceManager`

## Objective

Add two read-only MCP tools backed by existing private gRPC methods:

```text
products_list -> ServiceManager.ListProducts
products_get  -> ServiceManager.GetProduct
```

Both require `ceerat.products.read` and a fully validated CEERAT OAuth identity.

## Contract

`products_list` accepts bounded `page_size`, opaque `page_token`, and the
existing allowlisted query/sort/category/model/size/color/price/availability
filters. Reject unknown fields, invalid enums, oversized pages, malformed page
tokens, and unbounded queries before gRPC dispatch. Force customer-visible
active products; the model cannot request inactive inventory.

`products_get` accepts only an opaque product ID. Responses include customer-safe
catalog fields and server-computed price/availability. Do not expose supplier,
cost, internal inventory controls, unpublished items, or storage details.

## Changes and tests

- Extend the gateway platform interface/client with product DTO mapping.
- Register strict schemas, read-only annotations, scope requirements, timeouts,
  rate limits, audit outcomes, and LLM-safe error mappings.
- Register both tools with `domain: products`, optional
  `ceerat/domain: products` metadata, and the Products capability group returned
  by `describe_ceerat`; add no routing or authorization based on that metadata.
- Emit correlated audit records for list/detail success, empty/not-found,
  validation rejection, authentication/scope denial, rate limit, timeout, and
  dependency failure without logging filters or response bodies.
- Update the active MCP inventory and public integration documentation.
- Add schema, scope, pagination, filter, inactive-product, not-found, downstream
  failure, timeout, audit-redaction, and no-gRPC-on-invalid-input tests.
- Preserve the nine frozen Phase 1 tools unchanged.

## Builder/security gate

Run the common workflow plus:

```bash
ceerat-builder app-surface ceerat-agent-gateway --output json
ceerat-builder app-match "product catalog MCP" --output json
ceerat-builder evidence request "ListProducts GetProduct MCP" --output json
```

The review must confirm the gateway adapts protocol only and does not duplicate
catalog visibility, pricing, inventory, or persistence logic.

## Acceptance

Unauthenticated, wrong-client, missing-scope, unknown-field, invalid-page, and
inactive-product cases fail safely. Valid list/detail calls return schema-valid,
bounded results with one request ID and no customer or infrastructure leakage.
Gateway tests/build/vet/race, builder checks, and platform verification pass.

## Integration test

Seed active and inactive disposable products and variants in a disposable
PostgreSQL schema. Run MCP JSON-RPC through the real gateway adapter and private
gRPC service. Verify pagination/cursors, every allowlisted filter, stable detail,
customer-visible pricing, inactive-product concealment, scope denial, malformed
input rejection before gRPC, rate limiting, restart behavior, and cleanup.
Assert every outcome has the same request ID in the MCP envelope and audit event.
