# Phase 2 PR 11: Order read MCP tools

Repository: `apps-repo`  
Depends on: PR 10

## Objective

Add an Orders domain to `ceerat-agent-gateway` with customer-safe reads backed
only by private authenticated `order.OrderManager` gRPC:

```text
orders_list -> ListMyOrders
orders_get  -> GetMyOrder
```

Both require `ceerat.orders.read`. Update `describe_ceerat`, domain metadata,
the exact tool inventory, gateway documentation, and app inventory. Do not add
these tools to legacy `ceerat-agent-service`.

## Builder gate

Run builder context/evidence/ownership, app-inventory, OAuth/RBAC, and drift
checks before adding tools. Confirm the gateway is only an authenticated adapter
to private `order.OrderManager` gRPC and that response projection/redaction is
owned at the public adapter boundary.

## Schemas and projection

- `orders_list`: bounded `page_size`, opaque `page_token`, allowlisted customer
  status filter, stable pagination.

  Use a deterministic tie-breaker (for example creation time plus opaque order
  ID). The page token binds authenticated subject, normalized filters, sort,
  cursor, and expiry; changing any bound input rejects the token rather than
  reinterpreting it.
- `orders_get`: one opaque `order_id`.
- Responses expose customer-meaningful order number/status, snapshotted lines,
  pricing summary, payment-state summary, version, and timestamps.

- Monetary output uses the canonical exact representation and explicit currency;
  output schema tests forbid floating-point totals and contradictory component
  sums.
- Omit internal user/customer IDs, idempotency records, supplier/cost/storage
  data, raw payment/provider values, database fields, and other customers.

Use flat closed input schemas compatible with validated hosted MCP clients and
repeat runtime unknown-field/type/bounds enforcement. Reserved MCP `_meta`
remains separate.


Return one consistent safe envelope across order tools: `ok`, `data`/safe
`error`, `schema_version`, and `meta` containing tool, CEERAT `request_id`, and
truthful `operation_state`. Read failures are never labeled `outcome_unknown`
because no mutation was dispatched.

## Tests

Test OAuth scope denial, identity-shaped inputs, pagination bounds, status
allowlist, own-order projection, concealed foreign/not-found orders, gRPC error
mapping, timeouts, rate limits, output schema, and two-event correlated redacted
auditing. Run the full gateway test/build and builder app/drift checks.

Also test page-token tampering, token reuse under a different subject/filter,
concurrent inserts between pages, deterministic ordering, exact-money output,
large/empty result sets, and that addresses/notes are projected only where the
customer contract explicitly allows them and never appear in logs.

After Render deploys, compare the live unauthenticated `tools/list` definition
to the committed schema and confirm the gateway's expected commit. Refresh or
version the ChatGPT development app before its first order test. In a new chat,
invoke `orders_list` and then `orders_get` for one returned order; if none exist,
report the empty result and create disposable state only in the later checkout
PR. Do not treat tool discovery alone as proof that private gRPC dispatch works.

## Implementation record (2026-09-11)

Implemented in `ceerat-agent-gateway` with 18 total tools. `orders_list` and
`orders_get` are grouped under `orders`, require `ceerat.orders.read`, forward
the internal bearer token only to `ListMyOrders`/`GetMyOrder`, and return the
standard safe MCP envelope. Closed-schema, scope, self-scope, bounds, status,
not-found concealment, exact-money projection, timeout, rate-limit, and
redacted-audit tests pass. The gateway vendor tree was refreshed to the PR 09
exact-money/order contract; product and cart projections were updated to emit
the same canonical money representation rather than preserve a parallel float
contract.

Automated implementation gates completed: full gateway tests and build,
application inventory validation, OAuth/RBAC validation, and contract/service
drift validation. Render deployment and the documented live ChatGPT list/get
acceptance remain intentionally separate from this source implementation
record.
