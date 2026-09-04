# Phase 2 PR 06: Cart mutation MCP tools

Repository: `apps-repo`  
Depends on: Phase 2 PR 05

## Objective

Add authenticated, self-scoped cart tools backed by the hardened gRPC methods:

```text
products_cart_add_item
products_cart_update_item
products_cart_remove_item
products_cart_clear
```

All require `ceerat.products.cart.write` and call only the corresponding self-scoped
`ServiceManager.*MyCart*` RPCs. Readback additionally follows the established
cart-read policy.

## Public schemas and safety

- Never expose `customer_id`, owner, price, totals, discount, inventory, role,
  scope, or user-selected authority.
- Accept only opaque product/variant/item identifiers, bounded quantity,
  bounded notes if retained, opaque idempotency key, and expected cart version.
- `add` supports products only in this phase; service items remain deferred.
- `products_cart_clear` requires `confirmed: true` and a short-lived, user/client-bound
  preparation that previews item count and current total without sensitive data.
- Evaluate prepare/confirm for remove if the item is costly or nonrecoverable;
  at minimum require explicit item identification and return the resulting cart.
- Map stale version to a fresh-read instruction, duplicate success to the stored
  result, invalid product to corrected arguments, insufficient scope to consent,
  and uncertain commit to stop/check-cart—not blind retry.

## Changes and tests

Extend the gateway platform adapter, strict tool schemas, annotations, scope
map, confirmation/preparation state, rate limits, audit events, response DTOs,
and active inventory. Browser UI and legacy-agent callers are out of scope;
this PR changes only the MCP gateway. Test unknown fields, ownership, input
bounds, scope, confirmation, expiry, replay, client/user binding, idempotency,
stale version, downstream timeout, uncertain outcome, and redaction.
Register every tool as `domain: products`, emit optional
`ceerat/domain: products` metadata, and include it in the Products capability
group. Tests must prove changing or omitting metadata cannot alter routing,
scope enforcement, ownership, confirmation, or service authorization.

## Builder/security gate

Run the common workflow plus:

```bash
ceerat-builder app-surface ceerat-agent-gateway --output json
ceerat-builder app-match "cart mutation MCP" --output json
ceerat-builder evidence request "confirmed idempotent self-cart MCP writes" --output json
```

## Acceptance

The model can modify only its authenticated user's cart; service-owned values
cannot be overridden; repeated or concurrent calls do not duplicate unintended
effects; destructive clear is confirmed; and errors accurately distinguish
not-started, completed, and outcome-unknown. Gateway and platform gates pass.

## Integration test

Through MCP JSON-RPC and the real private gRPC/service/PostgreSQL path:

1. authenticate synthetic User A and read the cart version;
2. add a disposable product and repeat the identical idempotency key;
3. prove one effect exists and the same result is returned;
4. race two mutations at one expected version and prove only one commits;
5. update and remove using returned versions;
6. prepare/confirm clear, reject replay, and restore the initial cart;
7. attempt the preparation/key/item as User B and prove denial;
8. inject timeouts before and after commit and distinguish not-started from
   outcome-unknown, followed by cart reconciliation.

Assert schemas, gRPC requests, SQL parameters, errors, logs, and audit events
contain no caller-selected user/customer ID or credential.
For every mutation, assert a pre-dispatch decision and final outcome share one
request ID, include `domain=products`, safe cart versions and hashed references,
and distinguish replay, conflict, denial, completed, and outcome-unknown.
