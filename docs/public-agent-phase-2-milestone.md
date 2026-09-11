# Public agent integration Phase 2 product/cart milestone

Status: completed and human-validated on 2026-09-09  
Public MCP endpoint: `https://ceerat-agent-gateway.onrender.com/mcp`

## Delivered surface

Phase 2 extends the Phase 1 OAuth integration with a Products domain while
preserving the public-MCP-to-private-gRPC boundary:

```text
ChatGPT/Codex
  -> HTTPS MCP + delegated OAuth bearer token
  -> ceerat-agent-gateway
  -> authenticated private gRPC
  -> service.ServiceManager
  -> PostgreSQL
```

The public tool surface adds:

```text
products_list
products_get
products_cart_get
products_cart_add_item
products_cart_update_item
products_cart_remove_item
products_cart_clear
```

Catalog reads require `ceerat.products.read`. Cart reads require
`ceerat.products.cart.read`; mutations require
`ceerat.products.cart.write`. Cart identity is never accepted from the model.
The user service resolves the authenticated user to its customer and enforces
ownership independently of MCP metadata or client behavior.

## Security and correctness properties

- Product visibility, availability, price, currency, totals, and cart ownership
  remain service-authoritative.
- Cart contracts are self-scoped `*MyCart*` private gRPC methods and contain no
  user/customer selector.
- Mutations use optimistic cart versions and bounded idempotency keys.
- Destructive clear is a two-step, short-lived, user/client/version-bound
  preparation and explicit confirmation; replay is rejected.
- Unknown or authority-shaped inputs are rejected at the gateway and again at
  the service boundary where applicable.
- Responses use stable safe error codes, retry guidance, operation state, and a
  request ID without exposing tokens, SQL, topology, or another customer.
- MCP and downstream operations emit correlated, redacted audit records.

## Deployment incident and recovery evidence

The initial production `ceerat-user-service` deployment failed closed with:

```text
step=self_cart_schema_preflight
self-cart schema preflight failed: 3 required objects missing
```

Render retained the prior service binary, so the newer gateway correctly
returned `DEPENDENCY_UNAVAILABLE` with `operation_state: not_started` for cart
reads. The production migration
`20260904_phase2_self_cart.sql` was applied through PostgreSQL, followed by
`20260904_phase2_self_cart_preflight.sql`; preflight returned `DO`. Redeploying
the user service then restored the private gRPC dependency. This demonstrates
that explicit production migration and preflight must precede dependent code;
startup `AutoMigrate` is not a substitute for named constraints and indexes.

## ChatGPT schema compatibility correction

The first `products_cart_clear` schema expressed preparation and confirmation
as a top-level `oneOf`. One version also combined that with an outer
`additionalProperties: false` and no outer properties, causing a standards-
compliant validator to reject valid branch fields. Removing the conflict was
necessary but did not address a cached ChatGPT app schema and inconsistent
wrapper handling of polymorphic tool inputs.

The final contract publishes one flat, closed object containing the four
possible fields. Runtime validation still requires exactly one valid pair:

- preparation: `expected_cart_version` and `idempotency_key`;
- confirmation: `preparation_id` and `confirmed: true`.

The compatibility correction is apps commit `b265929`. Because ChatGPT
development app versions may retain an imported tool schema, the app definition
was refreshed/versioned before retesting. A new conversation alone was not
sufficient while the registered app version remained stale.

## Acceptance evidence

Automated Phase 2 verification passed the exact public tool/scope surface,
gateway and service security tests, generated contracts/security maps,
disposable PostgreSQL migration/rollback/reapply behavior, TLS, public denial,
and rate controls. The gateway suite passed after the final schema correction.

Human ChatGPT acceptance then proved:

- catalog discovery/list/detail and the new OAuth scopes;
- authenticated cart read through MCP, private gRPC, and PostgreSQL;
- cart add, update, remove, version advancement, and empty-cart totals;
- destructive clear preparation after the schema/version refresh;
- validation failures occurred before dispatch and did not change cart state;
- dependency failures truthfully returned `not_started`; and
- the original cart was restored/emptied without unintended changes.

Representative redacted evidence includes successful cart read request
`req_17cd0c9a6eaf0fd06fa0b51335ecf27f`, successful item removal request
`req_6578b98615ea14379587dbadb776f981`, and a final empty cart at version 3
with total 0. Credentials, tokens, connection strings, and customer data are
not retained in this milestone.

## Completion boundary

Phase 2 product catalog and customer-owned cart are complete. Checkout,
payment, orders, subscriptions, admin catalog mutation, inventory management,
and browser UI are outside this milestone. Future phases must reuse the same
MCP -> OAuth -> gateway -> private gRPC -> service-owned database boundary.
# PR 10 transactional self-order service (implementation milestone)

The private `order.OrderManager` is the only customer-order writer. PR 10 adds
subject-derived ownership, exact minor-unit pricing, bounded quote/update/cancel
previews, cart/order optimistic versions, fingerprint-bound confirmations,
atomic cart checkout and cancellation payment-placeholder invalidation, and
durable customer-scoped operation outcomes for reconnect/restart reconciliation.

Deployment is dependency ordered: apply
`20260910_phase2_self_orders.sql`, run its preflight, deploy the matching
user-service commit, verify startup and one private-gRPC self-order call, and
only then enable PR 11+ MCP tools. The implementation milestone does not claim
live deployment. There is no legacy schema, float-money, dual-write, fallback
read, hard-delete cancellation, or gateway-owned order path.

## PR 11 self-scoped order reads (implementation milestone)

The public MCP gateway now exposes `orders_list` and `orders_get` in an
`orders` domain. Both require only `ceerat.orders.read`, accept closed bounded
schemas without identity selectors, and dispatch exclusively to the private
authenticated `ListMyOrders` and `GetMyOrder` gRPC methods. Ownership and stable
pagination remain service-owned; the gateway is a projection and error-mapping
boundary, not an order data source.

Customer responses use the `MyOrder` snapshot projection and exact
`minor_units` plus currency money objects. They omit customer/user IDs,
provider/payment internals, database details, inventory/cost/storage fields,
and idempotency records. Missing and foreign orders are indistinguishable.
Read failures remain `not_started`, with retry guidance where safe, and never
claim a mutation outcome is unknown. Correlated audit records include the
tool/domain/scope/downstream method and hashed resource ID without order notes,
filters, raw IDs, or dependency text.

The implementation and deterministic gateway tests are complete. Live Render
deployment, live `tools/list` comparison, app-version refresh, and authenticated
ChatGPT list/detail calls remain PR 11 deployment acceptance work.

## PR 12 quote and checkout (implementation milestone)

The order MCP domain now includes server-owned cart pricing, durable checkout
preview, explicitly confirmed checkout, and subject-scoped operation-status
reconciliation. The gateway never accepts customer identity, cart/order lines,
quantities, prices, totals, tax, lifecycle/payment status, or provider data.
All business authority stays in private `order.OrderManager` gRPC.

Preparations bind the authenticated user and OAuth client to normalized inputs,
cart version, idempotency key, service pricing fingerprint, exact reviewed
components/currency, digest, and expiry. A single atomic state transition occurs
before dispatch. Unknown results are never retried blindly; the agent receives
the operation kind/key needed for the read-only status lookup. Completed replay
returns the service's original durable order result.

Normal tests, race tests, build, and local security/schema/audit checks pass.
Live deployment and the disposable ChatGPT checkout exercise remain pending.
