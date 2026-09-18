# Phase 2 PR 12: Quote and product-cart checkout MCP tools

Repository: `apps-repo`  
Depends on: PR 11

## Objective

Expose server-owned pricing and product-to-order creation through separate,
client-compatible operations:

```text
orders_quote_cart       -> QuoteMyCartPricing
orders_checkout_prepare -> validated quote and checkout preview
orders_checkout_confirm -> CheckoutMyCart
orders_operation_status -> GetMyOrderOperationStatus
```

Quote and `orders_operation_status` require `ceerat.orders.read`;
prepare/confirm require `ceerat.orders.checkout`. Operation status is read-only,
subject-scoped reconciliation and never retries a mutation. The confirm tool is
the customer order-create action.
Do not expose generic `CreateOrder`, `CreateMyOrder`, or model-constructed order
lines through MCP.

## Builder gate

Run builder context/evidence/ownership, app-inventory, OAuth/RBAC, schema-client
compatibility, and drift checks before exposing checkout. Confirm pricing stays
service-owned, preparation state has one canonical owner, and no generic order
creation or gateway-side total calculation is introduced.

## Safety contract

- Quote accepts only allowlisted shipping-method ID and bounded discount code,
  returns exact-money totals/currency plus an opaque `pricing_fingerprint` and
  expiry, and performs no reservation or mutation.
- Prepare additionally requires the current cart version and an idempotency key,
  reads the service-owned quote, and returns a short-lived preview.
- Preparation binds subject, OAuth client, normalized inputs, cart version,
  pricing fingerprint, quoted component totals/currency, idempotency key, digest,
  and expiry.
- Confirm accepts only `preparation_id` and `confirmed: true`, consumes the
  preparation once, and sends its bound values to `CheckoutMyCart`.

- Confirmation re-authenticates and re-authorizes first, then dispatches only
  the bound values. The service must reject an expired/stale pricing fingerprint
  before creating an order; a changed price/tax/shipping/discount requires a new
  preview rather than silently changing the reviewed total.
- Preparation consumption is atomic with dispatch state. Authentication/scope,
  malformed-input, expired-preparation, and stale-preview failures are
  `not_started`; a post-dispatch transport loss marks the preparation/operation
  for reconciliation and must not make the preparation appear safely reusable.
- Use separate prepare/confirm tools rather than a polymorphic top-level schema.
- Never accept customer identity, lines, quantities, prices, tax, totals,
  payment status, order status, or provider fields from the model.

Classify deterministic pre-dispatch failures as `not_started`. A timeout or
connection loss after dispatch is `OUTCOME_UNKNOWN` with the operation kind and
idempotency key needed for `orders_operation_status`; never recommend blind
checkout retry. Idempotent replay must return the original order safely.
`orders_operation_status` exposes only safe `not_found`/`in_progress`/
`completed`/`outcome_unknown` state and the resulting safe order when completed.

## Tests

Cover empty/stale carts, inactive merchandise, invalid shipping/discount,
missing scope, foreign/expired/replayed preparation, changed cart/quote,
price/tax/shipping drift after preview, idempotency conflict/replay, unknown
outcome plus operation-status reconciliation, safe order projection, exact-money
schema compatibility, rate limits, and correlated redacted audit events. Test
scope/token revocation between prepare and confirm, concurrent/double confirms,
gateway restart with a pending preparation/operation, and tampered preparation
IDs. Update the gateway/app inventories and run all gateway and builder gates.

## Live test setup and stop points

Before ChatGPT testing, create a disposable active product, ensure the test
customer has complete shipping and billing addresses, add a known quantity to
an otherwise recorded cart, and save the cart version. Test in this order:

1. quote only and compare server totals;
2. prepare checkout and stop before confirmation;
3. confirm only after the preview is reviewed;
4. immediately get the returned order and read the cart;
5. replay the same confirmation/idempotency outcome;
6. attempt changed input with the reused key and expect conflict.

7. change one server-owned pricing input after a preview and prove confirmation
   fails `not_started` as stale with no order/cart mutation;
8. inject one post-dispatch response failure, reconcile through
   `orders_operation_status`, and prove exactly one order exists without blind
   retry.

If read/quote/prepare fails, do not attempt confirmation. If confirmation is
`OUTCOME_UNKNOWN`, inspect/get/list the order by correlation and idempotency
state before any retry. Record the created disposable order for PR 13 cleanup.

## Implementation record (2026-09-11)

Implemented the four `orders` tools in `ceerat-agent-gateway` without exposing
generic order creation or model-authored lines/prices. Quote and operation
status require `ceerat.orders.read`; prepare and confirm require
`ceerat.orders.checkout`. The adapter calls only private self-scoped order/cart
gRPC and uses the standard safe MCP envelope.

Live acceptance exposed and closed one prerequisite gap: the existing prepared
customer-profile update now accepts complete, closed-schema `shipping_address`
and `billing_address` objects through the existing self-scoped
`UpdateMyCustomerProfile` gRPC method. Address updates remain behind
`ceerat.profile.write`, resource-version checking, preparation, and explicit
confirmation. Profile reads expose only address-completeness flags; address
values appear in the confirmation preview because they were explicitly supplied
by the user. Missing checkout addresses are classified as actionable validation
failures with `not_started`, never as dependency outages.

The live preparation acceptance test also verified that the preview must expose
the exact bound `pricing_fingerprint` and `quote_expires_at`. These values are
now returned with the server-owned pricing breakdown so a user or agent can
verify the identity and validity window of the quote being confirmed; confirm
still accepts only the opaque preparation ID and `confirmed: true`.

### Live acceptance result

The 2026-09-11 ChatGPT acceptance run passed the complete success path: profile
address prerequisites were satisfied, cart version 5 was quoted and prepared at
USD 174.40 from a USD 160.00 subtotal plus USD 14.40 server-calculated tax, and
explicit confirmation created exactly one `pending_payment` order. A subsequent
`orders_get` returned the same order and totals, while the cart advanced to
version 6 and contained no items. No retry or reconciliation was needed.

The run identified one final response-shape omission: initial successful confirm
did not explicitly return whether the result was a replay. The success response
now always includes `replayed: false`; reconciliation/idempotent replay returns
`replayed: true`. The remaining live acceptance action is to repeat the consumed
preparation once and verify that the original order is returned without creating
a second order.

Checkout preparation is durable, subject/client-bound, exact-money preserving,
digest-verified, quote-expiring, and atomically single-dispatch. Confirmation
accepts only an opaque preparation ID plus `confirmed: true`. Deterministic
service rejection is `not_started`; uncertain post-dispatch outcomes direct the
agent to `orders_operation_status` rather than blind retry. A completed replay
resolves and returns the original durable service outcome.

Automated tests and race detection cover closed schemas, scopes, normalized
bound inputs, tampering, expiry, foreign/replayed and concurrent confirmation,
restart-capable PostgreSQL state, exact-money invariants,
deterministic/uncertain error mapping, operation reconciliation, safe
projection, rate limiting, and correlated redacted audit events. The full
gateway build passes. Live Render and ChatGPT acceptance remain separate.
