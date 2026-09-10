# Phase 2 PR 09: Self-scoped order gRPC contract

Status: **IMPLEMENTED — automated contract validation complete 2026-09-10**

Builder keyword ranking initially surfaced `admin.AdminService` because of the
generic word “status”; its detailed contract/service evidence and direct source
inspection identify `order.OrderManager` as the existing canonical owner. The
implemented method inventory is `GetMyOrder`, `ListMyOrders`,
`QuoteMyCartPricing`, `CheckoutMyCart`, `PreviewMyOrderUpdate`, `UpdateMyOrder`,
`PreviewMyOrderCancellation`, `CancelMyOrder`, and
`GetMyOrderOperationStatus`. All are protected, customer-permitted, and absent
from the public allowlist; the five new methods are not agent-permitted.

The coordinated contract cutover introduces shared exact `commerce.Money`,
reserves replaced float tags/names, returns customer-safe `MyOrder`
projections, and adds version/fingerprint/idempotency inputs without an identity
selector or hard-delete RPC. Contract tests/build and builder RBAC/drift checks
pass. Service behavior and database migration remain PR 10 scope.

Repository: `contracts-repo`  
Depends on: PR 08

## Objective

Define the new-system customer order contract in the existing
`order.OrderManager`. Reuse `GetMyOrder`, `ListMyOrders`, `QuoteMyCartPricing`,
and `CheckoutMyCart`; add the missing self-scoped preview/update/cancel and
operation-reconciliation semantics needed for safe hosted-client writes.

## Builder gate

Run builder context/evidence/ownership, contract-diff, RBAC, and drift checks
before editing protobufs. Confirm `order.OrderManager` remains the canonical
owner, all new methods are self-scoped private gRPC, and no existing public or
superseded method is being repurposed or retained as a compatibility path.
Record the approved method/field inventory in the PR evidence.

## Contract changes

- Add `expected_cart_version` to `CheckoutMyCartRequest` so checkout cannot
  consume a cart different from the one quoted/confirmed.
- Make `QuoteMyCartPricing` return an opaque `pricing_fingerprint` and
  `quote_expires_at`; require that fingerprint in `CheckoutMyCartRequest` so
  checkout can reject a stale economic preview instead of silently repricing.
- Add a monotonic `version` to `Order`; every successful customer-visible order
  mutation increments it exactly once.
- Add `PreviewMyOrderUpdate` with `order_id`, `expected_order_version`, and only
  the bounded mutable patch. It returns the normalized patch, resulting safe
  pricing summary, `pricing_fingerprint`, and preview expiry without mutating.
- Add `UpdateMyOrder` with only `order_id`, `expected_order_version`, bounded
  mutable fields, `expected_pricing_fingerprint`, and `idempotency_key`.
- Limit mutable fields to notes, shipping-method selection, and discount code
  while an order is unpaid and `pending_payment`; use explicit field presence so
  omitted, set, and cleared values cannot be confused. Repricing is server-owned.
- Add `PreviewMyOrderCancellation` with `order_id`, `expected_order_version`, and
  bounded reason. It returns the safe cancellation effect plus an opaque
  `precondition_fingerprint` over the order/payment state relevant to cancel.
- Add `CancelMyOrder` with `order_id`, `expected_order_version`, bounded reason,
  `precondition_fingerprint`, and `idempotency_key`.
- Add `GetMyOrderOperationStatus` taking only an allowlisted operation kind and
  idempotency key. It is subject-scoped and returns a safe operation state plus
  the resulting order projection when one exists; it never exposes request
  hashes, database rows, or another customer's operation.
- Add explicit response messages returning the resulting safe order.

No request contains `user_id`, `customer_id`, owner, role, scope, status,
payment status, product lines, prices, tax, discount amount, shipping amount,
or total. Do not add `DeleteOrder`, legacy aliases, optional identity fallbacks,
or old/new dual contracts.

Remove any superseded customer-order RPC/message from the proto and reserve its
field numbers/names where required. Remove the corresponding generated methods,
security-map entries, mappers, and inventory records in the same coordinated
cutover. Do not leave an unadvertised callable duplicate for rollback.


## Contract invariants

- The current platform has no canonical exact-money contract and existing
  commerce messages use `double`. Introduce one shared `Money` message using
  signed 64-bit minor units plus allowlisted ISO currency, then use it for the
  product/cart/order/pricing/payment fields that participate in this checkout
  path. Do not convert a floating-point catalog value at the gateway.
- Retire and reserve the replaced floating-point field numbers and names. This
  is a coordinated new-system contract cutover: do not publish old and new
  monetary fields together, add conversion fallbacks, or reuse retired tags.
- Use enums/closed messages for operation kind and lifecycle values rather than
  free-form status/payment strings at trust boundaries.
- Bound and validate idempotency keys, discount codes, cancellation reason, and
  notes; do not use open maps/`Struct` for customer-controlled mutable fields.
- Other protobuf evolution is additive. Never reuse removed field numbers or
  names; descriptor tests pin the exact-money and public-safe shapes.
- Quote/precondition fingerprints are opaque, unforgeable or server-verifiable,
  short-lived values; they contain no customer data when decoded/logged by a
  client.

## Security and generation

- Register new methods in `KnownGRPCMethods` and customer role permissions.
- Keep every order method out of `DefaultPublicMethods`.
- Regenerate Go protobuf/grpc code, update mappers and contract inventory.
- Add descriptor/security tests proving no identity selector and no public
  exposure.

## Acceptance

`make proto`, `go test ./...`, and `go build ./...` pass. Builder RBAC and drift
checks report no issues. Contract tests prove checkout concurrency input,
self-scoped update/cancel shapes, bounded fields, and absence of a hard-delete
RPC.

Contract tests additionally prove exact-money types, explicit update-field
presence, quote/update/cancel fingerprint requirements, self-scoped operation
status, additive protobuf numbering, and that all preview/status RPCs are
non-mutating and non-public by default.
