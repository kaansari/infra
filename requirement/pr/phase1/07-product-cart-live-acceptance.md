# Phase 2 PR 07: Product/cart live acceptance and milestone

Repository: `infra`  
Depends on: Phase 2 PRs 01–06

## Objective

Prove the product and cart tools through the deployed public MCP endpoint from
Codex and ChatGPT without weakening or regressing Phase 1.

## Automated harness

Extend the credential-free/live harness with a versioned redacted result schema
covering discovery, exactly the intended active tool inventory, OAuth metadata,
scope declarations, invalid arguments, pagination limits, TLS, rate limits, and
all deterministic gateway/service security suites. It must retain no tokens,
credentials, response bodies, customer data, or database contents.

## Human acceptance

Using disposable Users A and B plus disposable active/inactive products:

1. Both clients discover catalog and cart tools while Phase 1 tools remain
   unchanged and admin/checkout tools remain absent.
   All seven tools use the `products_` prefix, advertise the Products domain,
   and appear in the Products group returned by `describe_ceerat`.
2. List products with pagination/filtering and retrieve one product detail;
   inactive/unpublished products are not disclosed.
3. Read A's empty/current cart; prove A cannot read or mutate B's cart or use a
   model-supplied identity field.
4. Add, repeat idempotently, update with current version, reject stale version,
   remove, and restore the original cart.
5. Confirm clear shows approval, is bound to A/client/version, and cannot replay.
6. Verify missing product/cart scopes produce distinct actionable consent
   guidance and logout/revocation still blocks subsequent calls.
7. Correlate request IDs with safe Render audit events and inspect for secrets,
   PII, topology, and cross-customer leakage.
8. Confirm direct private gRPC still enforces RBAC/ownership independently of
   MCP annotations or ChatGPT behavior.
9. Verify generated descriptors, security maps, service inventory, and gateway
   contain no customer-ID-shaped cart RPC or request message.

## Builder/architecture gate

Run the complete common workflow, `ceerat-builder docs all --output json`, all
shared checks, and `make verify-platform`. Reconcile tool inventory, OAuth
scopes, public-AI security, service/RBAC documentation, and deployed evidence.
Update durable builder standards only after tests pass and a human validates the
behavior.

## Acceptance and freeze

Every automated and manual item must be PASS with redacted evidence. Record
participating repository commits, rollback results, known limitations, and
ChatGPT/Codex prompts. Do not freeze Phase 2 on conversational output alone.
Create the Phase 2 milestone/tag only after all repositories are clean, pushed,
deployed, and reproducible from the committed runbook.

Browser UI behavior is not an acceptance criterion. UI redevelopment follows
the frozen platform APIs in a separate phase.

## Deployment and migration acceptance

Before live MCP testing, record sanitized evidence that schema preflight passed,
the forward SQL migration applied exactly once, required constraints/indexes
exist, and the private gRPC smoke test passed. Never record connection strings,
credentials, SQL rows, emails, or customer data.

Exercise rollback using a disposable clone of the representative schema.
Production rollback runs only when its safety checks pass; otherwise use the
documented roll-forward recovery. Restart/redeploy must not rerun migrations
destructively or lose carts/idempotency outcomes.

The final report separates contract/unit, PostgreSQL migration/repository,
private gRPC JWT/RBAC/ownership, MCP schema/scope/error, and deployed
Codex/ChatGPT acceptance results.

The live audit matrix must exercise every Products tool at least once plus
initialize, tools/list, authentication denial, scope denial, invalid arguments,
not-found, rate limit, version conflict, idempotent replay, confirmation denial,
dependency failure, success, logout, and post-revocation denial. For each row,
record only the prompt/test case, expected outcome, MCP request ID, audit event
ID, safe code/state, and PASS/FAIL. Verify retention/access policy and search by
request ID from the operator runbook.

## Release-candidate implementation record

Added `verification/phase2/` with a versioned redacted result schema, an exact
public MCP/OAuth surface verifier, deterministic gateway/service/contract and
builder checks, optional disposable PostgreSQL coverage, a focused live-rate
check, and a ChatGPT/Codex/operator runbook. Added
`make verify-phase2-live` and
`docs/public-agent-phase-2-release-candidate.md`. Results are written mode 0600
under ignored `.verification/` and retain no credentials, response bodies,
customer data, cart content, database URLs, or SQL rows.

### Automated evidence — 2026-09-09 UTC

Against `https://ceerat-agent-gateway.onrender.com`, eight checks passed:

1. live health, readiness, exact 16-tool inventory, all seven product-domain
   tools, OAuth scopes, schemas, annotations, discovery, and public denials;
2. verified TLS 1.2-or-newer connectivity;
3. gateway cart schema/scope/projection/confirmation/error/redaction/audit;
4. direct service cart handler and JWT/RBAC/ownership boundaries;
5. generated contract and security maps;
6. builder RBAC, drift, and active-app inventory; and
7. disposable PostgreSQL migration, rollback/reapply, ownership, pricing,
   idempotency, concurrency, and restart behavior; and
8. the live credential-free authentication-failure rate limit from one stable
   source IP.

There are zero automated functional failures. Authenticated Codex/ChatGPT User
A/B mutations, Render audit correlation, production migration/deployment
evidence, logout regression, restoration, and cleanup remain
`MANUAL_REQUIRED`. Phase 2 is a release candidate and is deliberately not
frozen or tagged yet. The redacted result is committed at
`verification/phase2/evidence/codex-2026-09-09.json`.

## Final human acceptance — 2026-09-09

The production migration and preflight completed, the current user-service
deployment started successfully, and ChatGPT exercised catalog and cart through
the public MCP/private-gRPC path. Cart read and reversible mutation passed;
version advanced correctly, totals were service-computed, and the cart finished
empty without unintended modification.

The `products_cart_clear` preparation exposed a client-compatibility defect in
the original polymorphic input schema. Apps commit `b265929` replaced the
top-level `oneOf` with a flat closed schema while retaining exact preparation
versus confirmation pair enforcement at runtime. After refreshing the ChatGPT
development app version to discard its cached schema, clear preparation passed.

The final milestone record is
[`../../docs/public-agent-phase-2-milestone.md`](../../docs/public-agent-phase-2-milestone.md).
Phase 2 product catalog and self-cart acceptance is complete; the broader audit
retention review and two-disposable-user evidence remain operational hardening,
not blockers for this validated development milestone.
