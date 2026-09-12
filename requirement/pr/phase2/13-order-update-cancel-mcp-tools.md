# Phase 2 PR 13: Pending-order update and cancellation MCP tools

Repository: `apps-repo`  
Depends on: PR 12

## Objective

Expose bounded customer maintenance through explicit prepare/confirm pairs:

```text
orders_update_prepare -> PreviewMyOrderUpdate
orders_update_confirm -> UpdateMyOrder
orders_cancel_prepare -> PreviewMyOrderCancellation
orders_cancel_confirm -> CancelMyOrder
```

All require `ceerat.orders.write`. There is intentionally no `orders_delete`,
arbitrary status setter, line editor, payment-state editor, or admin operation.

## Builder gate

Run builder context/evidence/ownership, app-inventory, OAuth/RBAC, state-machine,
and drift checks before exposing mutations. Confirm update/cancel remain
self-scoped service operations and that prepare paths are read-only previews,
not mutation calls hidden behind a dry-run flag.

## Update policy

Only owned, unpaid `pending_payment` orders may be updated. Accepted changes are
bounded notes, shipping-method selection, and discount code. Preparation calls
the read-only service preview, returns the exact normalized patch, exact-money
before/after pricing summary, pricing fingerprint, order version, and expiry.
Confirmation binds all of those reviewed values and fails before mutation if the
order version, pricing inputs, shipping eligibility, discount eligibility, or
currency changed. Product lines and snapshotted addresses are immutable after
checkout. Omitted and explicitly cleared mutable fields have distinct semantics.

## Cancellation policy

Cancellation preparation calls the read-only service preview and returns order
number, current status, amount, the safe effect on any nonterminal payment
session, a precondition fingerprint, order version, and expiry. Confirmation
transitions the order to `cancelled`; it never deletes rows. It revalidates both
version and precondition fingerprint so payment/session state cannot change
silently between preview and confirm. Paid, fulfilled, shipped, already
cancelled, or terminal orders fail before mutation with actionable guidance.

Use separate flat closed schemas for prepare and confirm. Every mutation has a
current order version, idempotency key, bound single-use preparation, explicit
confirmation, safe final projection, and truthful `not_started` versus
`outcome_unknown` behavior.


Preparations bind authenticated subject, OAuth client, operation kind, order ID,
order version, exact normalized patch/reason, pricing or precondition
fingerprint, idempotency key, digest, and expiry. Confirm re-checks current OAuth
scope before dispatch. Raw notes, cancellation text, addresses, and provider
session values never appear in audit logs or error details.

An `OUTCOME_UNKNOWN` update/cancel response must identify the operation kind and
idempotency key for `orders_operation_status`. The client reconciles first; it
never retries the confirm or creates a new idempotency key until status proves
`not_started`.

## Tests

Test ownership, scope, state-transition matrix, optimistic conflict, replay and
key conflict, patch allowlist/presence semantics, server repricing and exact
money, stale pricing/precondition fingerprints, terminal-state rejection,
payment-session handling, confirmation binding/expiry/replay, token revocation
between prepare/confirm, timeout outcome plus operation-status reconciliation,
redaction, rate limits, and audit correlation. Add races for update-vs-update,
update-vs-cancel, cancel-vs-payment-state-change, and double confirmation. Update
app/gateway docs and inventory; run full gateway and builder checks.

Publish each prepare and confirm operation as its own flat schema from the
start. After deployment, inspect live `tools/list`, refresh/version the hosted
app, and confirm its Version ID changed. The manual test must use the disposable
pending order created by PR 12: read its current version, prepare/confirm one
allowed update, reread, prepare cancellation, stop for explicit approval, then
confirm and reread. Never reuse a stale order version or an idempotency key
across different inputs.

The live test must also force one stale update preview and one stale cancellation
preview and prove both fail before mutation, then exercise one controlled
post-dispatch unknown outcome and reconcile it via `orders_operation_status`.

## Implementation record (2026-09-11)

Implemented the four independent order-domain tools in the existing gateway and
mapped them exclusively to the self-scoped private gRPC methods above. All use
`ceerat.orders.write`; operation-status reconciliation remains read-only under
`ceerat.orders.read` and now accepts checkout, update, and cancel kinds.

Update input is limited to presence-aware notes, shipping method, and discount
code. Cancellation accepts only a bounded reason. PostgreSQL-backed preparation
state binds user, OAuth client, operation kind, order ID/version, normalized
patch or reason, before/after exact pricing where applicable, service-issued
fingerprint, idempotency key, digest, and expiry. Confirmation atomically moves
the preparation to dispatching before calling gRPC and returns an explicit
`replayed` boolean. No legacy, generic status, delete, line, payment, identity,
address, or client-priced path was added.
