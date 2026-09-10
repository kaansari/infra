# Phase 2 order lifecycle PR plan

This plan extends the completed product catalog and self-cart milestone into a
customer-owned product-to-order lifecycle for ChatGPT, Codex, and compatible
MCP clients.

The earlier product/cart PRs are currently stored in
[`../phase1/`](../phase1/). These order PRs continue that implemented foundation
and must not reintroduce the removed customer-ID-shaped cart contracts.

## Validated ownership

`ceerat-platform-builder-agent` and current code inspection establish:

- product catalog and cart: `service.ServiceManager`;
- checkout and orders: `order.OrderManager`;
- backend implementation: `services-repo/services/ceerat-user-service`;
- public AI adapter: `apps-repo/ai/ceerat-agent-gateway`;
- public protocol: HTTPS MCP with delegated OAuth;
- internal protocol: authenticated private gRPC;
- persistence: the order-owned PostgreSQL tables in the user service.

Do not create a new service, REST API, browser UI, legacy adapter, generic AI
HTTP tool, or direct database path.

## Single-path new-system rule

Every Phase 2 order capability has one canonical path:

```text
public AI -> ceerat-agent-gateway MCP
          -> authenticated private order.OrderManager gRPC
          -> ceerat-user-service order repository
          -> canonical PostgreSQL schema
```

When a customer order RPC, protobuf field, database column, gateway adapter,
tool definition, scope entry, or inventory record is superseded by this plan,
remove it in the coordinated cutover. Do not retain it behind a feature flag,
compatibility alias, fallback, rollback mode, dual read/write, shadow path, or
deprecated inventory entry. A deployment with mismatched contract/service/
gateway versions must fail its gate instead of routing to an older behavior.

Current admin/agent operations or service-line order operations may remain only
when they implement a distinct, explicitly documented present-day capability.
They must not be invoked as fallback implementations of product checkout,
customer update, cancellation, or operation reconciliation.

## Customer lifecycle

```text
products/cart
  -> pricing quote
  -> prepared and confirmed checkout
  -> pending-payment customer order
  -> get/list
  -> prepared and confirmed bounded update
  -> prepared and confirmed cancellation
```

Product-order creation means atomic checkout from the authenticated customer's
cart. The model cannot construct line items, prices, totals, customer identity,
status, or payment state. Orders are retained as business/audit records;
customer "delete" is modeled as cancellation, never physical deletion.


## Cross-cutting invariants

These invariants apply to PRs 08–14 and are release blockers, not optional
implementation details:

- **Money is exact and server-owned.** Reuse the canonical money type (integer
  minor units or exact decimal plus ISO currency); never use binary floating
  point for price, discount, tax, shipping, or totals. Define and test rounding,
  overflow, zero/negative-total, and currency-mismatch behavior.
- **A reviewed preview cannot silently change at confirmation.** Quote/update
  previews return an opaque pricing/precondition fingerprint and expiry. Confirm
  must either apply the exact reviewed economic/state outcome or fail safely as
  stale before mutation; it may never substitute newly recomputed totals without
  another preview.
- **Identity and authorization are re-evaluated on every call.** Preparations are
  bound to authenticated subject and OAuth client, but confirmation still checks
  the current token, required scope, subject, client, and resource state. A
  revoked/expired token cannot consume or execute a preparation.
- **Preparations are short-lived, single-use, and tamper-resistant.** Bind the
  normalized request, resource version, server quote/precondition fingerprint,
  subject, OAuth client, expiry, and a digest. Atomic consumption happens only
  when mutation dispatch is accepted; deterministic pre-dispatch rejection must
  not create an ambiguous write outcome.
- **Every write is reconcilable.** Idempotency state persists long enough to
  outlive preparation expiry, client retry windows, process restarts, and
  `OUTCOME_UNKNOWN` investigation. A self-scoped operation-status read must be
  available so an uncertain checkout/update/cancel can be reconciled without a
  blind retry.
- **Concurrency behavior is deterministic.** Use documented lock ordering,
  bounded transaction/dependency timeouts, compare-and-swap versions, and safe
  deadlock/serialization handling. Retrying a transaction internally must never
  create two externally visible effects.
- **Pagination is stable and subject-bound.** Opaque page tokens bind the caller,
  filters, sort order, and cursor position; concurrent inserts must not cause
  duplicates, cross-customer leakage, or arbitrary reordering.
- **Sensitive data stays out of observability and evidence.** Addresses, notes,
  raw tokens, credentials, connection strings, internal payment/provider data,
  and full cart/order bodies are excluded from logs and acceptance artifacts.
  Correlation uses request IDs and safe identifiers only.
- **Deployment skew is tested.** The current commerce contract has no canonical
  exact-money type and uses `double`; PR 09 therefore introduces the one
  canonical exact-money message and replaces affected commerce money fields as
  a coordinated new-system contract change. Retired field numbers/names are
  reserved and are not served in parallel. Deploy contracts/migrations/service
  before exposing new public tools, verify exact commits, and test the supported
  service/gateway version pair before enabling human writes.

## Review additions incorporated

The security/architecture review is part of this canonical plan and is mapped
to the implementing PRs as follows:

1. Exact money, deterministic rounding, currency, overflow, and total
   invariants: PRs 09–11 and 14.
2. Pricing/precondition fingerprints that prevent a reviewed preview from
   changing silently at confirmation: PRs 09, 10, 12–14.
3. Read-only service preview RPCs for update and cancellation: PRs 09, 10, 13,
   and 14.
4. Self-scoped `GetMyOrderOperationStatus` and `orders_operation_status` for
   uncertain-write reconciliation without blind retry: PRs 09, 10, and 12–14.
5. Atomic preparation consumption/dispatch plus current OAuth validation on
   confirmation: PRs 08, 10, and 12–14.
6. Explicit idempotency retention/cleanup and post-commit/pre-response crash
   recovery: PRs 10, 12–14.
7. Lock ordering, bounded transaction timeouts, deadlock/serialization handling,
   and race tests: PRs 10 and 14.
8. Subject/filter-bound stable pagination and page-token tamper/concurrency
   tests: PRs 11 and 14.
9. Safe protobuf evolution, reserved retired money fields, no dual legacy
   projection, and supported deployment-skew gates: PRs 09, 10, and 14.
10. Live stale-preview, fault-injection, token-revocation, concurrent-confirm,
    reconciliation, and cleanup evidence: PRs 12–14.
11. Explicit builder context, evidence, ownership, security, architecture, RBAC,
    inventory, and drift gates: every PR.

These are release blockers. None authorizes browser UI, REST, real payment
integration, admin tools, hard deletion, or a legacy compatibility surface.

## PR order

1. [PR 08 — OAuth scopes](08-order-oauth-scopes.md)
2. [PR 09 — self-order gRPC contracts](09-self-order-grpc-contract.md)
3. [PR 10 — order service and migration hardening](10-self-order-service.md)
4. [PR 11 — order read MCP tools](11-order-read-mcp-tools.md)
5. [PR 12 — quote and checkout MCP tools](12-order-checkout-mcp-tools.md)
6. [PR 13 — update and cancel MCP tools](13-order-update-cancel-mcp-tools.md)
7. [PR 14 — live acceptance and milestone](14-order-live-acceptance.md)

Each PR must begin with builder context/evidence/ownership checks, preserve the
MCP -> OAuth -> gateway -> private gRPC -> service -> database boundary, update
the affected source-of-truth documentation and inventories, and pass its local
gate before the next PR starts.

## Required delivery workflow learned from product/cart

The product/cart rollout exposed several integration steps that unit tests do
not replace. Apply this sequence to every order PR:

1. Record the expected repository commit and generated contract version before
   deployment. Verify Render actually runs that commit; a failed deployment may
   leave the previous binary serving traffic.
2. Apply explicit PostgreSQL migrations and run committed preflight SQL before
   deploying a binary that requires the new schema. Do not rely on ORM
   auto-migration for named constraints/indexes.
3. Deploy in dependency order: contracts/vendor updates, database migration,
   `ceerat-user-service`, then `ceerat-agent-gateway`.
4. After an OAuth scope change, reconcile Keycloak, run the policy smoke test,
   verify protected-resource metadata, and obtain a fresh user authorization.
   Existing access/refresh tokens do not acquire newly optional scopes.
5. When a confidential OAuth client or revoker secret changes, synchronize the
   exact value in Keycloak, ChatGPT configuration, and Render, then restart the
   consuming service. Never print the value in evidence.
6. Verify the public live `tools/list` schema directly after gateway deployment.
   Hosted ChatGPT app versions may cache tool definitions: refresh/version the
   app and confirm its Version ID changes before opening a new test chat.
7. Prefer separate prepare and confirm tools. Avoid top-level polymorphic
   (`oneOf`) inputs for hosted-client compatibility. Keep schemas flat and
   closed and repeat exact-shape enforcement at runtime.
8. Public `/healthz` or `/readyz` is insufficient unless it probes the private
   dependency. Perform an authenticated read through gateway -> gRPC -> service
   before any write test.
9. On `DEPENDENCY_UNAVAILABLE`, stop writes, locate the gateway request ID, and
   inspect both gateway and user-service logs. Distinguish service unavailable,
   old/unimplemented binary, schema-preflight failure, and timeout.
10. Seed and record reversible disposable state before consequential testing.
    Capture initial cart/order versions, use unique idempotency keys, and restore
    the initial state after the test.
11. Keep automated, operator, ChatGPT, and Codex checks separate in the evidence
    matrix. A conversational success statement is not deployment evidence.
12. Update builder durable standards only after the behavior is human-validated.

Every live-test instruction must include an exact prompt, expected tool sequence,
stop condition, allowed writes, cleanup, and safe evidence fields. Never ask a
hosted model to improvise a destructive test.

## Deliberate exclusions

- hard deletion of orders;
- arbitrary customer status changes;
- editing snapshotted product lines after checkout;
- real payment-provider integration or payment credentials;
- admin/agent order-management MCP tools;
- the legacy `ceerat-agent-service` tool inventory;
- REST APIs and browser UI;
- compatibility aliases, dual-read/write, legacy fields, or data backfills for
  a predecessor order model.
- feature-flagged, shadow, rollback, or deprecated copies of superseded customer
  order paths.
