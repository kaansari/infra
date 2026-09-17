# Contract, Service, and Gateway Review Remediation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the protobuf, user-service, and MCP gateway review findings through a dependency-ordered series of independently reviewable pull requests.

**Architecture:** Keep the contracts repository as the canonical transport and policy source. Keep business truth, persistence, ownership, and state transitions in the user service. Keep the gateway responsible for MCP protocol behavior, authentication handoff, safe presentation, confirmation, and policy projection; it must not become a second pricing or authorization authority.

**Tech Stack:** Go 1.26.2+, Protocol Buffers, gRPC, PostgreSQL/GORM, Typesense, Keycloak/OIDC, MCP HTTP gateway, Go race tests, builder drift checks.

**Spec:** `requirement/proto-review.md`, `requirement/pr/codereview/service.md`, and `requirement/pr/codereview/gateway.md`.

## Global Constraints

- Do not deploy or push as part of implementation unless explicitly requested.
- Preserve protobuf wire compatibility: reserve removed field numbers and names; do not reuse them.
- Self-service identity comes from authenticated context; administrative APIs may retain explicit target IDs.
- The user service remains authoritative for ownership, RBAC, state transitions, inventory, pricing, and persistence.
- The gateway must never log or persist raw OAuth tokens, credentials, cookies, request bodies, or unnecessary customer PII.
- Every PR must run the smallest affected tests before commit and the full repository gates before merge.
- Do not remove existing RPCs solely for naming or architectural cleanliness; use additive versioned migration where clients depend on them.
- Every PR must update the owning repository README/security/API documentation, `contracts-repo/docs/contract-inventory.json` or its replacement, the relevant `ceerat-platform-builder-agent/.ceerat-agent/*` standard or inventory guidance, and any scripts, fixtures, deployment manifests, or requirements that reference the changed behavior. A PR is incomplete while stale references remain.
- Every PR must run a repository-wide stale-reference search across `*.go`, `*.proto`, `*.pb.go`, `*.md`, `*.json`, `*.sh`, `*.py`, `*.rb`, `Makefile`, Dockerfiles, and builder-agent documentation; the PR description must record the search pattern and zero remaining unintended matches.

---

## PR 01: Canonicalize the contracts module and generated imports

**Repositories:** `contracts-repo`, `services-repo`, `apps-repo`, `infra`

**Depends on:** None. This is the foundation for every later PR.

**Files:**

- Modify: `contracts-repo/packages/ceerat-contracts/go.mod`
- Modify: every `contracts-repo/packages/ceerat-contracts/proto/**/*.proto` `go_package`
- Regenerate: every `contracts-repo/packages/ceerat-contracts/proto/**/*.pb.go` and `*_grpc.pb.go`
- Modify: `contracts-repo/packages/ceerat-contracts/mapper/*.go` and mapper tests
- Modify: `contracts-repo/packages/ceerat-contracts/security/*_test.go`
- Modify: service and gateway `go.mod`, imports, `replace` directives, Docker/build files, and vendored contract packages
- Modify: `infra/Makefile`, builder checks, inventories, and any scripts containing the old module path
- Create: a CI check that fails if `github.com/kaansari/ceerat-platform/packages/ceerat-contracts` appears outside an explicitly documented migration fixture

**Deliverable:** `github.com/kaansari/ceerat-contracts` is the only contracts module identity. The old self-dependency is removed, generated packages import the canonical path, and all three consumers build from the same contract source.

**Tests and gates:**

- `go test -race ./...` in contracts, services, and gateway modules.
- `go vet ./...` in services and gateway.
- `make verify-render-native`.
- `ceerat-builder check drift --output json`.
- `rg` CI check for the old module path.
- Verify that vendored and Docker build paths resolve the canonical package without a second contracts module.

**Review boundary:** No business behavior changes. If a generated diff changes wire descriptors beyond import paths, stop and review the generator inputs before merging.

**Documentation and stale-reference updates:** Update `contracts-repo/README.md`, the generated contract inventory, service/gateway module import examples, Docker/build context documentation, `infra/requirement/*` references, and `ceerat-platform-builder-agent/.ceerat-agent/module-generation-standard.md`. Update builder code or checks that embed the old module path. Add the old-path scan to the documented CI command.

## PR 02: Remove caller-controlled authority from protobuf self-service APIs

**Repositories:** `contracts-repo`, `services-repo`

**Depends on:** PR 01.

**Files:**

- Modify: `contracts-repo/packages/ceerat-contracts/proto/order/order.proto`
- Modify: self-service messages in `career.proto`, `ai.proto`, `customer.proto`, and any request carrying owner selectors
- Modify: `contracts-repo/packages/ceerat-contracts/security/self_order_contract_test.go`, `self_cart_security_test.go`, and new self-service descriptor tests
- Modify: corresponding service handlers and request mappers
- Modify: generated clients and service tests

**Contract changes:**

- Remove `status` from `CreateMyOrderRequest`; reserve field `6` and name `status`.
- Remove owner selectors only from self-service methods; reserve removed fields where wire compatibility requires it.
- Keep explicit `user_id`/`customer_id` in administrative or deliberately cross-user methods, with tests documenting that classification.
- Do not rename existing deployed RPCs solely for style; introduce `GetMy...` aliases only where the old method cannot be safely constrained.

**Deliverable:** A self-service request cannot select lifecycle, ownership, role, scope, payment, or server-calculated fields through its protobuf shape.

**Tests and gates:**

- Reflection tests enumerate every self-service RPC and reject forbidden fields.
- A service test sends a non-initial order status and proves the service still creates only the server-selected initial state.
- Generated clients compile in services and gateway.
- `go test -race ./...` for contracts and services.

**Documentation and stale-reference updates:** Update the affected protobuf/API sections in `contracts-repo/README.md`, `contract-inventory.json`, service API/security docs, gateway tool/API documentation, phase requirements that mention `CreateMyOrder` or self-service identity, and `ceerat-platform-builder-agent/.ceerat-agent/security-rbac-standard.md`. Update generated inventories and every script or fixture that serializes the changed request shape.

## PR 03: Close service authorization and identity fail-open paths

**Repositories:** `services-repo`, `contracts-repo`

**Depends on:** PR 01 and PR 02.

**Files:**

- Modify: `services/ceerat-user-service/internal/models/models.go`
- Modify: `seed.go`, `rbac.go`, OAuth identity resolver, and customer authorization helpers
- Modify: migrations for role-default removal and managed RBAC permission reconciliation
- Modify: OAuth/admin/bootstrap documentation and configuration
- Add: service authorization and bootstrap tests

**Deliverable:**

- New users cannot silently become admins because a role field was omitted.
- Managed/system RBAC permissions are reconciled: missing permissions are inserted and obsolete system permissions are removed without deleting custom-role permissions.
- Admin and agent OAuth identities do not require customer records; customer profiles remain required only for customer-domain operations.
- Missing authentication context and unowned customer rows fail closed.
- The first administrator bootstrap binds an explicit issuer and subject rather than relying on an unused local password or email collision behavior.

**Tests and gates:**

- Database migration test proves the role default is removed and existing roles are preserved.
- RBAC reconciliation tests cover add, remove, custom-role preservation, and concurrent startup.
- OAuth resolver tests cover customer, agent, admin, missing customer, email conflict, and issuer/subject binding.
- Customer ownership tests reject missing context and blank-owner rows.
- `go test -race ./...` and service security verification.

**Documentation and stale-reference updates:** Update the service OAuth/bootstrap, RBAC, ownership, and migration docs; `docs/security/*`; relevant `requirement/pr/*` files; builder-agent security/RBAC standards and service inventory guidance; seed/migration scripts; local-stack examples; and incident/runbook references. Remove examples that imply `admin` is a database default or that every OAuth user is a customer.

## PR 04: Make service writes explicit and concurrency-safe

**Repositories:** `contracts-repo`, `services-repo`

**Depends on:** PR 02 and PR 03.

**Files:**

- Modify: product/customer/order update request messages in `contracts-repo/packages/ceerat-contracts/proto/**/*.proto`
- Add: explicit `ProductPatch`, `CustomerProfilePatch`, and required-version/idempotency fields where needed
- Modify: product, customer, order handlers and repositories
- Modify: gateway platform client and prepare/confirm code to send patches and expected versions
- Add: migrations or indexes required for atomic version checks and idempotency uniqueness

**Deliverable:** Omitted fields remain unchanged; child collections are not deleted because a resource was partially supplied; profile and catalog updates use conditional writes; order creation ignores caller lifecycle state and chooses a valid initial state.

**Required semantics:**

- Use `google.protobuf.FieldMask` or explicit wrapper/optional fields for scalar patch presence.
- Use explicit child collection operations where omission must not mean deletion.
- Use `UPDATE ... WHERE id = ? AND version = ?` or an equivalent transaction and map a conflict to `codes.Aborted`.
- Make idempotency `same key + same request = replay` and `same key + different request = conflict`.
- Replace count-plus-one order numbers with a sequence or atomic counter.

**Tests and gates:**

- Concurrent profile update test proves one writer receives a conflict and cannot overwrite the other.
- Product patch tests prove omitted fields and child collections survive.
- Idempotency race tests prove no raw unique-constraint error escapes.
- Order-number concurrency test proves uniqueness under parallel creation.
- `go test -race ./...` across contracts, services, and gateway.

**Documentation and stale-reference updates:** Update protobuf API examples, service write/concurrency/idempotency docs, gateway prepare/confirm examples, database migration notes, builder-agent module-generation and service standards, generated inventories, and all scripts/fixtures that construct full resources or expect unconditional updates.

## PR 05: Repair service pagination, errors, and search lifecycle

**Repositories:** `services-repo`, `contracts-repo`

**Depends on:** PR 04.

**Files:**

- Modify: order, career, catalog, customer, and job repository cursor implementations
- Modify: product search adapter and `ListProducts` service behavior
- Modify: service error mapping boundary and handler error returns
- Modify: Typesense index rebuild code and migrations/configuration
- Add: search and pagination contract tests

**Deliverable:** Every cursor matches its declared sort, search page one and later pages use the same backend semantics, repository/provider errors become stable safe gRPC statuses, and index rebuilds cannot silently truncate or expose an empty partial collection.

**Required semantics:**

- Use opaque compound cursors containing the sort key and tie-breaker, for example `(created_at, id)`.
- Include the selected sort/backend in search cursors and reject incompatible cursor reuse.
- Set Typesense page and next-page behavior explicitly; never switch from Typesense page one to PostgreSQL page two.
- Use versioned collections with count verification and atomic alias switching for rebuilds.
- Map not-found, conflict, invalid input, forbidden, dependency, and unknown-outcome errors to stable gRPC codes and safe messages.

**Tests and gates:**

- Multi-page tests for every sort direction and concurrent inserts.
- Search tests covering Typesense and PostgreSQL fallback with identical ordering and cursors.
- Error scanner proving raw SQL/provider details do not reach clients.
- Rebuild tests covering more than 10,000 records, failed indexing, and alias rollback.

**Documentation and stale-reference updates:** Update service API and operations docs with cursor formats, error categories, search backend behavior, and index rollout/rollback procedures. Update Typesense startup/rebuild scripts, health checks, builder-agent service standards, contract inventory examples, and requirements that describe pagination or search acceptance.

## PR 06: Complete or explicitly gate PreferenceService

**Repositories:** `contracts-repo`, `services-repo`, `apps-repo`, `infra`

**Depends on:** PR 01 and PR 03.

**Decision required inside the PR:** Either implement and register the existing PreferenceService, or remove it from advertised inventories/scopes until implementation is ready. Do not leave the contract, scopes, and runtime in different states.

**Files:**

- Modify: preference service registration in `services/ceerat-user-service/main.go`
- Add/modify: preference handler and service implementation using the existing repository/migrations
- Modify: gateway scope/tool catalog and contracts policy metadata
- Modify: builder/service inventories and documentation

**Tests and gates:**

- Contract-to-registration test proves every advertised RPC is implemented.
- OAuth/RBAC tests cover preference scopes and customer ownership.
- MCP tools/list and tools/call tests agree with runtime availability.
- If deferred, tests prove preference scopes are absent from discovery and inventories.

**Documentation and stale-reference updates:** Update `requirement/pref.md`, phase 3 preference requirements, service/gateway READMEs, OAuth scope documentation, contract and service inventories, builder-agent preference ownership/service guidance, local verification scripts, and discovery fixtures. If deferred, document the explicit deferred state in each of those locations.

## PR 07: Secure gateway-to-service transport and identity/session semantics

**Repositories:** `contracts-repo`, `services-repo`, `apps-repo`, `infra`

**Depends on:** PR 01, PR 03, and PR 04.

**Files:**

- Modify: gateway gRPC client configuration and service gRPC server credentials
- Add: local TLS/mTLS certificates and loopback-safe test configuration; never commit private production keys
- Modify: gateway auth principal to distinguish OAuth subject, CEERAT user ID, issuer, session ID, and client ID
- Modify: connection state/revocation code and Keycloak revocation adapter
- Modify: connection tool schemas for explicit confirmation or prepare/confirm flow
- Modify: audience configuration and OAuth integration fixtures

**Deliverable:** Reusable bearer tokens are protected in transit; identity fields are not silently overwritten; local connection state and Keycloak revocation have one documented scope; destructive revocation requires explicit confirmation; gateway and service agree on audience semantics.

**Tests and gates:**

- TLS/mTLS handshake and certificate-rotation tests.
- A token with distinct `sub` and CEERAT user claim proves ownership uses the documented field.
- Revocation tests cover one-client and session-wide semantics, including sibling connections.
- Confirmation/replay tests reject unconfirmed revocation.
- End-to-end token tests cover gateway → gRPC with the configured audience set.

**Documentation and stale-reference updates:** Update the canonical OAuth/gRPC architecture, deployment runbook, Keycloak/client configuration docs, TLS/mTLS local-stack scripts, revocation incident procedures, gateway tool documentation, service security docs, builder-agent security profile, and all audience/session/identity examples. Remove examples that describe plaintext bearer-token transport if they are no longer accurate.

## PR 08: Generate the gateway policy projection from canonical contracts

**Repositories:** `contracts-repo`, `apps-repo`

**Depends on:** PR 01, PR 02, PR 06, and PR 07.

**Files:**

- Add: generated or checked-in policy projection containing gRPC method, required scopes, public/protected state, mutability, confirmation requirement, and safe operation state
- Modify: `contracts-repo/packages/ceerat-contracts/security` policy metadata
- Replace: gateway hand-maintained `requiredScope`, `downstreamMethod`, and supported-scope tables
- Add: gateway policy generation/check command and tests

**Deliverable:** The gateway cannot silently drift from service scope policy. The known `orders_quote_cart` mismatch is corrected by generation/checking rather than a one-off constant edit.

**Tests and gates:**

- Generation is deterministic and produces no diff on a clean tree.
- Every gateway tool maps to one canonical gRPC method and policy.
- Every protected canonical method used by the gateway has matching scope and confirmation metadata.
- A deliberate scope mismatch fails CI.

**Documentation and stale-reference updates:** Update the generated policy/catalog format, MCP tool documentation, contract inventory, gateway README, service scope/RBAC docs, builder-agent policy and inventory guidance, `verify-api.py` scenarios, and every script or fixture that names a required scope, downstream method, mutability, or confirmation requirement.

## PR 09: Reduce gateway state, improve readiness, and remove duplicated business truth

**Repositories:** `apps-repo`, `services-repo`, `infra`

**Depends on:** PR 04, PR 05, PR 07, and PR 08.

**Files:**

- Modify: gateway preparation schema and migrations to store normalized patches, owner binding, expected version, expiry, and digests rather than full profile PII
- Modify: gateway cleanup worker and migration lifecycle
- Modify: `/readyz` and container readiness configuration
- Remove gateway pricing/inventory business calculations that duplicate service truth; retain structural validation and safe presentation
- Replace cart-clear `float64` values with `Money`-compatible fields
- Add downstream dependency checks with short deadlines

**Deliverable:** Gateway state contains only what is needed to confirm a request, readiness reflects actual dependency reachability, and service-owned business calculations are not reimplemented in MCP code.

**Tests and gates:**

- Schema migration and redaction tests prove profile PII is not persisted in new preparations.
- Expiry cleanup runs periodically and is safe across multiple gateway instances.
- `/healthz` remains shallow liveness; `/readyz` fails when gRPC/JWKS/limiter dependencies are unavailable.
- Pricing and money tests prove the gateway preserves service results and currencies.
- Secret/PII scanner covers database fixtures, logs, traces, and MCP responses.

**Documentation and stale-reference updates:** Update gateway schema/migration docs, readiness and deployment manifests, incident lookup instructions, privacy/data-retention documentation, Money examples, builder-agent architecture and service standards, local-stack lifecycle scripts, smoke tests, and public-surface verification fixtures.

## PR 10: Make contract, implementation, inventory, and documentation checks generated

**Repositories:** `contracts-repo`, `services-repo`, `apps-repo`, `infra`

**Depends on:** PR 01 through PR 09 as applicable; can begin the tooling spike after PR 01.

**Files:**

- Add: protobuf descriptor inventory generator
- Add: contract-to-handler registration checker
- Add: contract-to-OAuth-scope/RBAC checker
- Replace: manually maintained `contract-inventory.json` sections with generated output
- Pin: protoc, protoc-gen-go, protoc-gen-go-grpc, and lint/breaking-check tool versions
- Update: READMEs, service logging/security docs, gateway incident lookup instructions, and builder standards after human validation

**Deliverable:** New RPCs cannot merge without implementation, registration, policy, inventory, and documentation evidence. Generated output is reproducible in CI.

**Tests and gates:**

- Clean regeneration produces no diff.
- Adding a fixture RPC without a handler or policy fails the checker.
- Breaking field removal without a reserved number/name fails the compatibility check.
- `go test -race ./...`, `make verify-grpc-oauth`, `make verify-api-security`, and `ceerat-builder check drift --output json` run in CI or the documented local equivalent.

**Documentation and stale-reference updates:** Update `ceerat-platform-builder-agent/.ceerat-agent/module-generation-standard.md`, `service-standards.md`, `security-rbac-standard.md`, architecture guidance, generated inventory documentation, `infra/requirement/agent.md`, CI_README, Makefile/verification README files, and all command examples. The generated checker must report which source files, scripts, docs, inventories, and builder references it validated.

## Merge order

1. PR 01: canonical contracts identity.
2. PR 02: self-service authority fields.
3. PR 03: service authorization/bootstrap fail-closed behavior.
4. PR 04: explicit write and concurrency semantics.
5. PR 05: pagination, errors, and search lifecycle.
6. PR 06: PreferenceService completion or explicit deferral.
7. PR 07: gateway transport and identity/session semantics.
8. PR 08: generated gateway policy projection.
9. PR 09: gateway state/readiness/business-boundary cleanup.
10. PR 10: generated drift and reproducibility enforcement.

PR 06 can run in parallel with PR 04 and PR 05 after PR 03 if its scope decision is independent. PR 10's tooling prototype can start after PR 01, but its merge gate should wait until the policy and registration shapes stabilize.

## Review checklist for every PR

- [ ] The PR states which review findings it closes and which it intentionally defers.
- [ ] Protobuf changes reserve removed fields and names.
- [ ] The service enforces the invariant independently of the protobuf shape.
- [ ] Gateway checks are not treated as authoritative for service-owned business state.
- [ ] Logs, errors, fixtures, and persisted state contain no raw secrets or unnecessary PII.
- [ ] Tests cover concurrency where the PR changes ownership, pagination, idempotency, revocation, or versioning.
- [ ] Local sanitized evidence is captured before any deployment or push.
- [ ] No deployment or push occurs without explicit authorization.
