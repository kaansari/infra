# Phase 2 PR 14: Order live acceptance and milestone

Repository: `infra`  
Depends on: PRs 08–13

## Objective

Prove the complete product -> cart -> order lifecycle through deployed ChatGPT
and Codex while independently validating private gRPC security and PostgreSQL
behavior. Freeze the milestone only after automated and human evidence passes.

## Builder gate

Run builder context/evidence/ownership and release-manifest checks first. Freeze
the expected contracts, migration, service, gateway, OAuth, and hosted-app
versions that this acceptance run is intended to validate; do not mix evidence
from different deployed tuples.

## Automated gate

Extend the redacted Phase 2 harness to verify:

- exact public tool/domain/scope inventory and absence of legacy/admin/payment
  tools;
- flat closed schemas, annotations, output envelopes, required confirmation,
  and client-schema compatibility;
- contract descriptors, known/public method maps, customer RBAC, and absence of
  identity selectors or hard-delete RPCs;
- migration/preflight/rollback/reapply on disposable PostgreSQL;
- service ownership, transactionality, versioning, idempotency, state machine,
  restart persistence, and concurrency;
- exact-money/currency invariants, quote/precondition fingerprints, stale-preview
  rejection, and deterministic rounding;
- idempotency retention/cleanup and self-scoped operation-status reconciliation
  across service/gateway restarts;
- gateway authentication/scope/input/error/rate/audit behavior;
- token expiry/revocation between prepare and confirm, preparation subject/client
  binding, single-use atomic consumption, and tamper rejection;
- stable subject/filter-bound pagination under concurrent order inserts;
- TLS, OAuth metadata, Phase 1, catalog, cart, and revocation regression.

Evidence files remain mode 0600 and contain no tokens, credentials, connection
strings, customer data, cart/order contents, addresses, or raw log bodies.

## Human ChatGPT/Codex acceptance

Using disposable users/products and reversible data:

1. Refresh/version each hosted app after tool-schema changes and verify the
   imported tool list.
2. List/get only the caller's orders with bounded pagination.
3. Build a cart, quote it, prepare checkout, inspect preview, confirm, and prove
   exactly one pending-payment order was created and the cart cleared.
4. Replay the checkout safely and reject a reused key with changed input.
5. Update an allowed field through prepare/confirm and verify order version and
   server totals.
6. Reject cross-user IDs, model-supplied identity/prices/totals/status/lines,
   stale versions, invalid transitions, and missing scopes before mutation.
7. Cancel through prepare/confirm, prove the row remains as `cancelled`, and
   reject repeat/terminal mutation safely.
8. Change a server-owned pricing/precondition input after a reviewed preview and
   prove confirmation fails `not_started` without silently changing totals or
   state.
9. Exercise a controlled pre-dispatch dependency failure and a separate
   post-dispatch response failure. Confirm accurate `not_started` versus
   `outcome_unknown`, reconcile the latter via `orders_operation_status`, and
   prove exactly one externally visible effect.
10. Attempt concurrent/double confirmation and update-vs-cancel races; prove
    optimistic versioning/idempotency produces one deterministic winner and safe
    loser responses.
11. Revoke or expire the relevant OAuth grant between prepare and confirm and
    prove confirmation fails before dispatch without bypassing current auth.
12. Correlate every public request ID through gateway and gRPC audit logs and
    verify redaction.
13. Confirm logout/revocation blocks subsequent order calls and operation-status
    reads as dictated by the current scopes.

Use committed prompts for each step. Every prompt must say “Using only CEERAT,”
name the allowed tools/actions, forbid unrequested writes, and require complete
safe envelopes/request IDs. Run the read-only prompt first. Run each prepared
write as two separate prompts so the human sees the preview before approval.

## Deployment and troubleshooting gate

Record PASS for each item before human writes:

- Keycloak reconciliation and OAuth-policy smoke test;
- fresh grant containing all order scopes;
- protected-resource metadata containing the same scopes;
- database migration and preflight;
- Render user-service and gateway commits match the release manifest;
- user-service startup and private gRPC smoke test;
- live public `tools/list` matches the committed inventory;
- ChatGPT/Codex app definitions were refreshed after schema changes; and
- authenticated order read succeeds through the complete dependency path;
- quote/preview responses contain exact-money currency plus required fingerprints
  and expiry, and a deliberately stale fingerprint is rejected pre-mutation;
- `orders_operation_status` is live and subject-scoped before any fault-injected
  write test; and
- database/service/gateway clocks are within the documented tolerance used for
  token, quote, and preparation expiry decisions.

For every failure, preserve only request ID, timestamp, component, safe error
code/state, deployed commit, and disposition. `DEPENDENCY_UNAVAILABLE` with
`not_started` permits a bounded read retry after dependency diagnosis; it does
not permit a write retry. A wrapper validation error has no CEERAT request ID
and must be diagnosed by comparing the hosted app schema with live
`tools/list`.

Do not classify a client timeout alone as `not_started`. Only the component that
knows dispatch/commit state may make that determination. If certainty cannot be
established, preserve `outcome_unknown` until the operation-status path or
operator correlation resolves it.

## Committed hosted-client prompts

Read-only readiness:

```text
Using only CEERAT, check authentication and list my orders with page_size 5.
If an order exists, retrieve only the first order. Make no write, preparation,
logout, or revocation call. Report PASS/FAIL per call, scopes, operation state,
and CEERAT request IDs.
```

Checkout preparation:

```text
Using only CEERAT, read my cart, quote it with the stated shipping selection,
and prepare checkout using the current cart version and a fresh idempotency key.
Stop after the preview. Do not confirm checkout or modify the cart. Report the
preview, preparation expiry, operation states, and request IDs.
```

Checkout confirmation (send only after reviewing the preview):

The preview recorded for this prompt must include cart version, exact currency
and component totals, pricing fingerprint, expiry, and preparation ID. If any of
those differ from the reviewed preview, do not send the confirmation prompt.


```text
Using only CEERAT, confirm exactly preparation ID <ID> with confirmed=true.
Do not perform any other write. Then read the returned order and cart. Report
the order/cart versions, safe totals/status, operation states, and request IDs.
If the confirmation outcome is unknown, do not retry it.
```


Unknown-outcome reconciliation:

```text
Using only CEERAT, check the status of the prior order operation using its exact
operation kind and idempotency key. Make no write, prepare, confirm, logout, or
revocation call. Report the operation state, resulting safe order if completed,
and CEERAT request ID. Do not retry the original mutation.
```

Update and cancellation use the same two-prompt pattern: first read and prepare,
explicitly stop, then confirm exactly one reviewed preparation. Replace `<ID>`
manually; never ask the model to choose an unreviewed preparation.

## Freeze

Record repository commits, migration/preflight result, deployed versions,
sanitized request IDs, prompts, PASS/FAIL matrix, limitations, and recovery
steps in a Phase 2 order milestone document. Include a cleanup ledger mapping
each disposable cart/order/idempotency operation to its final state, plus proof
that no pending preparation, nonterminal payment placeholder, or unreconciled
`outcome_unknown` record remains before freeze. Record the exact supported
contracts/service/gateway commit tuple so rollback or forward-fix decisions do
not depend on an ambiguous "latest" deployment.

Update TXSE/product requirements, service/gateway docs, inventories, and durable
builder standards only after human validation. Run `make verify-platform`,
builder docs/RBAC/drift/apps checks, all repository tests/builds, and the live
harness.

Browser UI, REST, real payments, fulfillment, refunds, admin MCP, and physical
order deletion remain out of scope.
