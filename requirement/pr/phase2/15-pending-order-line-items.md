# Phase 2 PR 15: Pending-order product-line amendments

Repositories: `contracts-repo`, `services-repo`, `apps-repo`, `infra`  
Depends on: PRs 09–14

## Objective

Extend the existing self-scoped order update flow so an authenticated customer
can amend product lines on an owned order while it is both `pending_payment`
and `unpaid`. Support all three required outcomes:

- add a catalog product variant as a new line, or increase its existing line;
- remove an existing order-product line; and
- set an existing line to a different positive quantity.

Quantity is mutable only through the reviewed order-update transaction. A
requested quantity of zero is rejected rather than overloaded as removal; the
caller must use the explicit remove operation. Negative quantities, client
prices, arbitrary product snapshots, and direct line-row mutation are invalid.

Reuse the established public tools and private gRPC operations:

```text
orders_update_prepare -> PreviewMyOrderUpdate
orders_update_confirm -> UpdateMyOrder
```

Do not add separate public add/remove/quantity tools, REST endpoints, generic
order-line CRUD RPCs, legacy adapters, or parallel mutation paths.

## Builder context and ownership gate

The `ceerat-platform-builder-agent` evidence and impact checks identify:

- contract owner: `order.OrderManager` in `contracts-repo`;
- service owner: `services-repo/services/ceerat-user-service/orders`;
- product source of truth: the catalog owned by `service.ServiceManager`;
- public adapter: `apps-repo/ai/ceerat-agent-gateway`; and
- canonical boundary: OAuth MCP -> authenticated private gRPC -> service-owned
  transaction -> PostgreSQL.

Before implementation, run builder context, evidence, contract impact,
gRPC-security, RBAC, inventory, and drift checks. Treat the builder's generated
CRUD suggestions only as inventory hints: this PR deliberately extends the
existing self-scoped prepare/confirm contract and must not create generic
`Create/Get/List/Update/DeleteOrderProduct` methods. Keep both gRPC methods
protected and preserve interceptor order JWT -> RBAC -> logging -> handler.

## Contract design

Extend `MyOrderUpdatePatch` with repeated, bounded product-line changes. Use a
typed operation enum and one message with operation-dependent validation:

```proto
enum MyOrderProductChangeOperation {
  MY_ORDER_PRODUCT_CHANGE_OPERATION_UNSPECIFIED = 0;
  MY_ORDER_PRODUCT_CHANGE_OPERATION_ADD = 1;
  MY_ORDER_PRODUCT_CHANGE_OPERATION_SET_QUANTITY = 2;
  MY_ORDER_PRODUCT_CHANGE_OPERATION_REMOVE = 3;
}

message MyOrderProductChange {
  MyOrderProductChangeOperation operation = 1;
  string order_product_id = 2;
  string product_variant_id = 3;
  int32 quantity = 4;
}
```

Validation rules:

- `ADD` requires `product_variant_id` and quantity `1..99`; it forbids
  `order_product_id`. If the same variant already exists, normalize the result
  to one line with the increased final quantity.
- `SET_QUANTITY` requires an owned `order_product_id` and final quantity
  `1..99`; it forbids `product_variant_id`.
- `REMOVE` requires an owned `order_product_id`; it forbids variant and
  quantity inputs.
- Reject unspecified operations, duplicate/conflicting changes to the same
  line or variant, more than 25 changes, and a result exceeding 100 total units
  or 50 lines.
- The resulting order must contain at least one product or service line.
- IDs are opaque. Missing and foreign line IDs both return customer-safe
  `NOT_FOUND` without revealing ownership.

Extend `PreviewMyOrderUpdateResponse` with complete normalized before/after
customer-safe line projections, not merely the input delta. Continue returning
the normalized patch, resulting exact pricing, opaque pricing fingerprint, and
preview expiry. Reserve any retired protobuf numbers and regenerate committed
Go outputs; do not preserve a second legacy projection.

## Catalog, snapshot, and pricing policy

The server resolves every added variant from the active customer-visible
catalog at preparation and confirmation. The caller supplies only the variant
ID and desired quantity. The service owns name, SKU, model, attributes,
availability, unit price, currency, discount eligibility, tax, shipping, and
all order snapshots.

Preparation constructs the complete candidate line set and reprices it through
the canonical order pricing engine. Confirmation re-locks the order, rechecks
state/version and catalog eligibility, and verifies the reviewed fingerprint.
It either applies the exact reviewed line set and totals atomically or fails
`not_started`; it must never silently substitute a new price or variant.

Historical snapshot fields on unchanged lines remain stable. Added lines get a
new server-authored snapshot. Quantity changes update line totals only. Removed
lines are physically removed from the mutable pending order within the same
transaction; the durable operation/preparation audit retains safe identifiers
and hashes without retaining sensitive request bodies.

## Transaction, concurrency, and idempotency

Confirmation must:

1. validate the current token, `ceerat.orders.write`, subject, and OAuth client;
2. atomically claim the bound single-use preparation;
3. lock the owned order and its product lines using documented lock order;
4. require `pending_payment`, `unpaid`, and the reviewed order version;
5. validate the full normalized line result and fingerprint;
6. insert/update/delete lines, apply pricing, and increment the order version
   exactly once in one database transaction; and
7. persist the replayable operation result before returning.

The preparation digest binds subject, OAuth client, operation kind, order ID,
order version, normalized non-line patch, normalized full line result, exact
pricing, fingerprint, idempotency key, and expiry. Concurrent update/update,
line-update/cancel, and payment-state changes produce one deterministic winner.
Never retry an `outcome_unknown` confirmation; reconcile it through
`orders_operation_status` with the original `update` idempotency key.

No schema migration is expected if the canonical order-product table already
supports inserts, deletes, quantity, exact unit price, and exact total price.
Implementation must prove this with a committed preflight. If any required
constraint or index is missing, add an explicit idempotent migration, preflight,
and rollback before deploying the service.

## MCP schema and agent behavior

Extend `orders_update_prepare` with optional `product_line_changes`, a bounded
array of closed objects. Keep `orders_update_confirm` unchanged. The schema and
descriptions must tell the model to read the order first, use current opaque
line IDs for set/remove, use catalog variant IDs for add, and stop after preview
until the user explicitly approves.

The preview must clearly report:

- normalized change operations;
- complete before and after line summaries with quantities and exact money;
- complete before and after pricing;
- order version, pricing fingerprint, preparation ID, and expiry; and
- safe warnings such as removed line, changed quantity, or catalog price used.

Use `ceerat.orders.write`; no new OAuth scope is necessary. Update protected
resource/app metadata only if the tool inventory changes. Refresh/version the
ChatGPT app after the schema change and verify the imported schema rather than
assuming the hosted tool cache refreshed.

## Errors, logging, and privacy

Map validation, state, and concurrency failures to the existing structured MCP
error envelope with accurate `operation_state`, `retryable`, `agent_action`,
safe details, and request ID. Distinguish invalid change shape, line not found,
variant unavailable, quantity/limit violation, stale order version, stale
pricing fingerprint, ineligible order state, idempotency conflict, dependency
unavailable, and outcome unknown.

Log tool/RPC name, request ID, subject-safe identifier, OAuth client, order ID,
operation counts, old/new order version, result state, error code, duration, and
replay flag. Do not log tokens, notes, full line bodies, customer addresses,
catalog cost/supplier data, or preparation payloads.

## Tests

### Contract and security

- Protobuf validation for every operation shape and boundary.
- No identity, price, total, status, payment, snapshot, or customer fields in
  caller input.
- Both gRPC methods remain protected, known to RBAC, and customer-authorized
  only through self-scoped ownership enforcement.
- Generated code, mappers, contract inventory, service inventory, gateway tool
  inventory, and drift checks pass.

### Service and database

- Add a new variant and add an already-present variant.
- Set quantity upward and downward; reject zero, negative, and over-limit.
- Remove one line; reject removal of the final remaining order line.
- Combine nonconflicting add/set/remove changes in one atomic update.
- Reject duplicate/conflicting changes, inactive/missing variants, foreign line
  IDs, currency mismatch, client-authored prices, stale version/fingerprint,
  and every non-`pending_payment` or paid state before mutation.
- Verify catalog snapshots, exact repricing, tax, discounts, shipping, rounding,
  order/line totals, and one version increment.
- Verify idempotent replay, changed-input key conflict, preparation expiry and
  binding, token revocation between prepare/confirm, restart persistence, and
  operation-status reconciliation.
- Race add-vs-add, set-vs-remove, update-vs-cancel, payment-vs-update, and double
  confirmation under the race detector.
- Migration/preflight/rollback/reapply tests when schema work is required.

### Gateway and live acceptance

Run schema/inventory, authentication, scope, closed-input, confirmation,
redaction, audit-correlation, dependency, and unknown-outcome tests. Then use a
disposable unpaid pending order through Codex and ChatGPT:

1. Read the order and record version, lines, quantities, and exact pricing.
2. Prepare adding one inexpensive active variant; inspect and confirm; reread.
3. Prepare increasing that line's quantity; inspect and confirm; reread.
4. Prepare decreasing its quantity; inspect and confirm; reread.
5. Prepare removing that line; inspect and confirm; reread and prove the
   original order state is restored except for monotonic versions/audit.
6. Force a stale preview and prove confirmation fails without mutation.
7. Exercise a controlled unknown outcome and reconcile without blind retry.

Each consequential step uses a fresh idempotency key and a separate human
confirmation prompt. Capture only safe request IDs, versions, totals, operation
states, and deployed commit/version evidence.

## Documentation and completion gate

Update contract/service/app inventories and docs in the same PR. After automated
tests and human live validation pass, update the Phase 2 milestone and reusable
`ceerat-platform-builder-agent` standards. Run:

```text
make proto
go test ./...
go build ./...
make verify-platform
ceerat-builder rbac check --output json
ceerat-builder check apps --output json
ceerat-builder check drift --output json
ceerat-builder verify contract-and-service order.OrderManager --output json
```

Record the supported contracts/service/gateway commit tuple and Render
deployment evidence. This PR is incomplete until private gRPC tests and fresh
ChatGPT/Codex app-schema acceptance both pass.

## Out of scope

- paid, processing, shipped, fulfilled, cancelled, or refunded orders;
- service-line amendments;
- direct line CRUD, hard order deletion, arbitrary status/payment changes;
- caller-authored pricing or snapshots, inventory reservation, refunds, or real
  payment-provider behavior;
- admin MCP tools, REST, browser UI, legacy compatibility, flags, dual paths,
  fallbacks, or deprecated aliases.

## Implementation record (2026-09-13)

Implemented by extending the existing `MyOrderUpdatePatch`,
`PreviewMyOrderUpdate`, `UpdateMyOrder`, `orders_update_prepare`, and
`orders_update_confirm` path. No RPC or public tool was added. The service now
normalizes explicit add, remove, and set-quantity changes, validates catalog
variants and inventory, constructs complete candidate lines, reprices them,
and atomically replaces the pending order's product-line set at confirmation.

The preview returns complete before/after customer-safe products and pricing.
The gateway binds the normalized changes in its durable preparation digest and
continues to require explicit confirmation. PostgreSQL migration and preflight
enforce positive bounded quantities and add the order/variant lookup index.
Automated contract, service, gateway, build, RBAC, drift, and live acceptance
results must be appended before this PR is marked complete.

The first live preparation exposed a gateway boundary regression: the imported
schema accepted `product_line_changes`, but runtime validation omitted that
field from its `at_least_one_change_required` decision. The request failed
safely as `not_started` (`req_401ba40e5467e502b898d08a8eccefc6`), and no order
changed. The correction makes product-line changes satisfy the update presence
rule and independently validates each closed add/set-quantity/remove shape
before gRPC dispatch. A regression test now covers both a valid line-only
update and an invalid remove carrying quantity.
