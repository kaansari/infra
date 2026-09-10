# Phase 2 PR 10: Transactional self-order service

Repository: `services-repo`  
Depends on: PR 09

## Objective

Harden and complete `order.OrderManager` in `ceerat-user-service` for atomic,
customer-owned checkout, update, and cancellation using the new contracts.

## Builder gate

Run builder context/evidence/ownership, service-boundary, RBAC, persistence, and
drift checks before implementation. Confirm `ceerat-user-service` owns the
canonical order tables and that no gateway-side pricing, direct database path,
or second order writer exists. Record migration ownership and transaction
boundaries in the PR evidence.

## Persistence and migration

Add a sortable explicit PostgreSQL migration, rollback/roll-forward notes, and
production preflight for:

- canonical integer-minor-unit and ISO-currency columns for every product,
  variant, cart, order line, order pricing, and payment amount used by this
  product-to-order path; remove the replaced floating-point columns in the same
  new-system cutover after validated conversion of current development data;
- non-null order version with default 1;
- unique customer/operation/idempotency-key records with request hash, outcome,
  expiry, and reconciliation state;
- indexes for customer order pagination and idempotency reconciliation;
- constrained order and payment-state values needed by this lifecycle.

- durable operation outcome records sufficient to reconcile checkout, update,
  and cancellation after gateway/service restart without storing raw request
  bodies or sensitive customer snapshots in the idempotency table.

This is a new system: migrate the one canonical schema directly. Do not add
legacy columns, compatibility triggers, dual writes, fallback reads, or data
translation for predecessor contracts. Test empty and representative current
schemas, repeat migration idempotently, and exercise rollback on a disposable
database. Production migration/preflight precedes deployment.

The deployment runbook must provide both approaches used by operators: a
noninteractive command with Render's external PostgreSQL connection fields and
an interactive `psql` `\i /absolute/path/to/migration.sql` path. It must run the
preflight file immediately afterward and document its expected success output.
No credential may be committed or pasted into test evidence.


Define idempotency retention explicitly: it must outlive the longest preparation
TTL, client retry/reconnect window, and operator reconciliation window. Expiry
cleanup is bounded, indexed, observable, and must never remove an in-flight or
`outcome_unknown` record. Migration/preflight also verifies money/currency
constraints, version constraints, unique idempotency scope, and absence of
orphaned operation records.

## Service behavior

- Derive customer/user from authenticated context for every `My` method.
- Checkout locks the cart, verifies `expected_cart_version`, validates active
  products/variants and available quantity, calculates all amounts server-side,
  snapshots product/address/pricing data, creates one order, and clears/increments
  the cart in one transaction.

- Checkout also verifies the unexpired `pricing_fingerprint` against the exact
  current server-owned pricing inputs. If catalog price, discount eligibility,
  shipping eligibility, tax basis, address facts, currency, or other economic
  input changed, fail before mutation and require a new quote/preview.
- Replaying the same checkout key/input returns the original outcome; reuse with
  different input returns an idempotency conflict.

- Persist the idempotency claim and final result in the same transactional
  boundary as the business mutation whenever possible. If a process dies after
  commit but before response, `GetMyOrderOperationStatus` must deterministically
  return the committed result without performing the mutation again.
- Update preview is read-only and validates ownership/state plus the exact
  bounded patch. Update confirmation is allowed only for an owned, unpaid
  `pending_payment` order, uses compare-and-swap versioning, verifies the
  unexpired pricing fingerprint from the reviewed preview, updates only approved
  fields, and reprices from immutable order/address/catalog rules inside one
  transaction. A pricing drift is a stale-preview failure, not a silent total
  change.
- Cancellation preview is read-only. Cancel is a state transition, not deletion.
  Confirmation revalidates the reviewed precondition fingerprint and rejects
  paid, fulfilled, shipped, already-cancelled, or otherwise terminal orders and
  invalidates any nonterminal placeholder payment session transactionally.
- Repository queries include owner predicates; not-found responses do not reveal
  another customer's order.

- All monetary arithmetic uses the canonical exact representation with explicit
  currency, documented tax/discount/shipping rounding order, checked overflow,
  and invariants such as nonnegative component amounts and a reproducible total.
- Define one lock order for cart, order, idempotency, and payment-session rows;
  set bounded transaction/statement timeouts; and classify deadlock/serialization
  failures. Internal retries are allowed only when the attempt is proven to have
  made no external effect.
- `GetMyOrderOperationStatus` reads only the authenticated customer's operation
  record, handles `not_found`, `in_progress`, `completed`, and genuinely
  `outcome_unknown` states, and returns the same safe result on repeated reads.
- Normalize and validate customer text without logging it. Notes and addresses
  are treated as sensitive; audit events contain safe field names/change types,
  versions, operation kind, and request IDs rather than raw values.

Map failures to precise gRPC codes (`Unauthenticated`, `PermissionDenied`,
`InvalidArgument`, `NotFound`, `Aborted`, `AlreadyExists`,
`FailedPrecondition`, `Unavailable`, `Internal`) without leaking database text.

## Tests and documentation

Add handler, repository, real PostgreSQL, private gRPC JWT/RBAC, two-customer
isolation, concurrency, idempotency, transaction rollback, restart persistence,
and redacted audit tests. Update API, testing, security, logging, architecture,
migration, and service inventory documents. Run service tests/build plus builder
contract/service, RBAC, and drift gates.

Add fault-injection tests at pre-lock, post-idempotency-claim, pre-commit,
post-commit/pre-response, and dependency-timeout boundaries. Add simultaneous
checkout, update-vs-cancel, and double-confirm tests; exact-money/rounding and
price-drift tests; token subject isolation for operation status; and restart
reconciliation proving an uncertain response never creates a duplicate order or
second state transition.

Before marking this PR deployed, verify the latest Render service commit and
startup logs. A failed deployment that leaves the previous binary live is a
failure, even when Render health still appears green. Add a private gRPC smoke
test for one new method and a dependency-aware readiness/operator check.

Keep order tools disabled/unadvertised until the migration, matching service
binary, private gRPC smoke test, and pricing-fingerprint path are live. This
is a dependency-ordered single cutover; do not implement temporary contract,
repository, schema, or behavior fallbacks during rollout.
