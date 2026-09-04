# CEERAT Phase 2 product and cart MCP PR plan

Phase 2 extends the frozen identity boundary with the existing CEERAT product
catalog and the authenticated customer's cart. It is an MCP- and gRPC-first
platform phase. It does not add or migrate browser applications, checkout,
payments, orders, subscriptions, administrative catalog mutation, TXSE market
data, social login, Kubernetes, or legacy `ceerat-agent-service` tools.

## Dependency order

| Order | PR | Repository | Outcome |
| --- | --- | --- | --- |
| 1 | [OAuth scopes](01-product-cart-oauth-scopes.md) | `infra` | Register product/cart scopes and consent text |
| 2 | [Catalog reads](02-product-catalog-mcp-tools.md) | `apps-repo` | Add bounded `products_list` and `products_get` MCP tools |
| 3 | [Self-cart gRPC contract](03-self-cart-grpc-contract.md) | `contracts-repo` | Add explicit identity-derived cart RPCs with no customer selector |
| 4 | [Self-cart service and storage](04-self-cart-service.md) | `services-repo` | Apply explicit SQL migration and implement safe self-cart operations |
| 5 | [Self-cart MCP read](05-self-cart-mcp-read.md) | `apps-repo` | Add `products_cart_get` over the self-scoped RPC |
| 6 | [Cart write tools](06-cart-mutation-mcp-tools.md) | `apps-repo` | Add bounded add/update/remove/confirmed-clear tools |
| 7 | [Live acceptance](07-product-cart-live-acceptance.md) | `infra` | Codex/ChatGPT two-user evidence and Phase 2 milestone |

Merge and deploy in this order. With no branch environment, validate each PR
locally, merge one repository at a time, wait for the owning Render service to
be ready, run its live smoke test, and only then begin the dependent PR.

## Frozen architecture and boundaries

```text
ChatGPT/Codex
  -> HTTPS MCP + user OAuth bearer token
ceerat-agent-gateway
  -> authenticated private gRPC + internal user session
service.ServiceManager
  -> RBAC + customer ownership + validation + transactions
product/cart repositories
```

## Products tool domain

MCP tool discovery is flat, so every Phase 2 tool uses the portable
`products_` prefix:

```text
products_list
products_get
products_cart_get
products_cart_add_item
products_cart_update_item
products_cart_remove_item
products_cart_clear
```

The gateway registry additionally assigns `domain: products`, publishes
optional `ceerat/domain: products` metadata, and groups these tools under a
Products section in `describe_ceerat`. Names and metadata aid discovery only;
OAuth scopes and service authorization remain authoritative. Product scopes
share the same family: `ceerat.products.read`,
`ceerat.products.cart.read`, and `ceerat.products.cart.write`.

- External OAuth terminates at `ceerat-agent-gateway`.
- Gateway-to-service calls use the existing authenticated workload identity and
  short-lived internal user session.
- `service.ServiceManager` owns catalog visibility, cart ownership, inventory,
  pricing, totals, concurrency, idempotency, and persistence.
- Public cart schemas never accept `customer_id`, `user_id`, tenant, role,
  scope, price, discount, totals, inventory overrides, or grant authority.
- Product and variant IDs select merchandise, never identity or authorization.
- MCP cart operations call only explicit `GetMyCart`/`*MyCartItem` private
  RPCs. The customer-ID-shaped cart RPCs and request messages are removed;
  there is one platform ownership model.
- No component calls the database except the owning service repository.
- Public errors use the existing LLM-safe envelope and never expose gRPC,
  database, topology, credentials, cross-customer records, or raw dependencies.

## Mandatory builder-agent workflow

Every PR must use `ceerat-platform-builder-agent` for context, architecture,
security, boundaries, ownership, and post-change consistency. Run from that
repository before implementation:

```bash
ceerat-builder check-context
ceerat-builder codex-context --output json
ceerat-builder app-context ceerat-agent-gateway --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder rbac check --output json
ceerat-builder evidence request "Phase 2 product catalog and self-cart MCP" --output json
ceerat-builder docs all --output json
```

Also run the PR-specific commands in each document. Builder output is evidence,
not permission to bypass requirements or service ownership.

Every PR review must explicitly answer:

1. Where does the external OAuth token terminate?
2. What authenticates the gateway-to-service call?
3. Which service owns authorization, ownership, validation, and persistence?
4. Can a model-controlled field select identity, authority, price, or totals?
5. Is the operation read-only, retry-safe, idempotent, confirmed where
   destructive, and truthful under an uncertain outcome?
6. Can errors, logs, audit records, or evidence expose secrets or another user?
7. Does the change preserve MCP → gateway → private gRPC → service storage?

After implementation and tests:

```bash
ceerat-builder check drift --output json
ceerat-builder check apps --output json
make verify-platform
```

After each PR is deployed and human-validated, update its owning API/security
documentation and the applicable builder standard. Do not publish unvalidated
behavior as a durable platform rule.

Existing browser UIs are not Phase 2 callers or acceptance gates. A later UI
project may discover and consume the completed gRPC/API surface; it must not
drive, duplicate, or weaken the domain contract.

## Phase 2 definition of done

The product/cart milestone is complete only when PR 07 records redacted passing
evidence for tool discovery, OAuth scopes, pagination, active-product
visibility, self-cart ownership, idempotent/concurrent writes, confirmation,
two-user isolation, rate limits, safe errors, audit correlation, logout, and
cleanup from both Codex and ChatGPT. Phase 1 remains frozen throughout.

## Database and test policy

PR 04 owns the atomic service-and-schema change because both live in
`ceerat-user-service`; code must not deploy before its required schema. Add a
sortable SQL migration under `services/ceerat-user-service/migrations/` and a
matching GORM model. Production applies the explicit migration before starting
the new service binary; `AutoMigrate` is not the sole production mechanism.

Every implementation PR adds unit and boundary tests. PRs 04–07 also add
integration coverage across generated gRPC contracts, disposable PostgreSQL,
the real service/repository, gateway adapter, MCP JSON-RPC, OAuth scopes, and
safe errors. Mock-only success is insufficient.

## Mandatory ChatGPT/Codex operation logging

OpenAI-compatible tool behavior requires accurate schemas, authentication,
annotations, and structured results; OpenAI does not make the model an audit
authority. CEERAT therefore applies its own server-side audit standard to every
MCP protocol and tool operation, whether accepted, rejected, rate-limited,
failed, timed out, or outcome-unknown.

Log at minimum:

```text
timestamp
server-generated request_id and trace/correlation_id
protocol operation (initialize, tools/list, tools/call)
tool name and domain=products
OAuth client_id and pseudonymous actor/customer reference when authenticated
authorization/scope decision (never the token or claims payload)
operation class: discovery | read | write | destructive
target type and hashed/opaque target reference
confirmation/preparation decision when applicable
idempotency-key hash and cart versions when applicable
rate-limit decision and safe dimension category
downstream service/method name
operation_state: not_started | completed | outcome_unknown
outcome, stable error code, latency, and retry classification
```

Never log authorization headers, cookies, access/refresh tokens, authorization
codes, client/workload/SMTP secrets, raw OAuth claims, passwords, complete tool
arguments/results, notes/prompts, emails, database URLs, SQL values, private
addresses, stack traces, or cross-customer data. Product/cart IDs are logged only
as approved opaque or keyed-hash references. The server-generated request ID is
returned in every success/error envelope so ChatGPT, Codex, and operators can
correlate a result without exposing credentials.

Emit an attempt/decision event before a consequential dispatch and a completion
event afterward. For reads, an audit-sink outage is observable and bounded by
documented policy. Writes and destructive operations fail closed before dispatch
if the required durable audit attempt cannot be recorded. Audit emission must
not turn a known completed write into a retryable failure; use
`outcome_unknown` and reconciliation where final state cannot be proven.

Tests capture logs/audit records and assert one correlated lifecycle per request,
all required fields, correct rejection outcomes, no raw bodies or credentials,
safe concurrent correlation, retention/access controls, and behavior when the
audit sink is unavailable.
