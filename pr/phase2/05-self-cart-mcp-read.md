# Phase 2 PR 05: Self-cart MCP read

Repository: `apps-repo`  
Depends on: Phase 2 PR 04  
Owner behind gateway: `service.ServiceManager`

## Objective

Add `products_cart_get`, requiring `ceerat.products.cart.read`, backed only by the new private
`ServiceManager.GetMyCart` RPC.

## Boundaries

- The MCP input schema has no business arguments and rejects unknown fields.
- The gateway sends the internal user session but no user/customer selector.
- No customer-ID-shaped `GetCart` method exists after PR 04.
- The service remains authoritative for identity resolution and ownership.
- Public output omits internal ownership identifiers and exposes only safe item
  data, server-computed prices/totals, and cart version.

## Changes and tests

Extend the platform adapter, strict schema, read-only annotation, scope,
timeout, rate limit, audit outcome, safe error mapping, active MCP inventory,
and API documentation. Test valid/empty carts, no-argument enforcement,
OAuth/client/scope rejection, Users A/B isolation, downstream failures,
malformed responses, and redaction. Browser UI and legacy-agent callers are out
of scope; this PR changes only the MCP gateway and its active inventory/docs.
Register the tool as `domain: products`, emit optional
`ceerat/domain: products` metadata, and add it to the Products capability group.

## Builder-agent gate

Run the common workflow plus:

```bash
ceerat-builder app-surface ceerat-agent-gateway --output json
ceerat-builder app-match "get my cart MCP" --output json
ceerat-builder evidence request "GetMyCart customer ownership MCP" --output json
ceerat-builder patterns grpc-security --output json
```

## Acceptance

User A sees only A's cart, User B sees only B's cart, and neither the public
tool nor private RPC permits selecting the other identity. Gateway tests,
build/vet/race, builder checks, and platform verification pass.

## Integration test

Run the gateway against the real private gRPC service and a disposable
PostgreSQL schema. Exchange two synthetic authenticated identities, call MCP
`products_cart_get` for both, and prove distinct persisted carts are returned. Repeat
after gateway and service restart. Retain only status, safe opaque test IDs,
error codes, and request IDs—never tokens or database contents.
Verify successful, empty, denied, rate-limited, timed-out, and dependency-error
reads each produce a correlated gateway audit event and private gRPC log entry.
