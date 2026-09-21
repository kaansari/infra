# Keycloak Browser Application Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all browser-app legacy authentication and stale service adapters with two Keycloak PKCE clients, current protected gRPC calls, and a rebuilt agent/admin-only chat service.

**Architecture:** The user service provisions identity from a validated OAuth-client policy, both Go web apps operate as OAuth BFFs that forward the original token to private gRPC, and the internal chat service accepts only active agent/admin tokens. Route inventories bind every page to canonical contracts, scopes, RBAC, and ownership rules.

**Tech Stack:** Go, gRPC, protobuf, Keycloak 26, OAuth 2.0/OIDC authorization code with PKCE S256, PostgreSQL, Render/local infra, JavaScript, HTML templates.

**Spec:** `docs/superpowers/specs/2026-09-19-keycloak-browser-app-cutover.md`

## Global Constraints

- No legacy authentication, compatibility endpoint, fallback credential, deprecated route, dual behavior, or migration flag remains.
- `ceerat-web-ui` provisions pending agents; `ceerat-customer-ui` provisions active customers.
- Roles and statuses come only from server-side policy keyed by validated OAuth client ID.
- Customer UI has no AI chat; agent chat accepts active agent/admin identities only.
- Original Keycloak tokens are forwarded unchanged and production private gRPC requires TLS.
- Every page route maps to current known, scoped, role-authorized gRPC methods.
- Secrets and credentials never enter source, browser JSON, logs, command arguments, or retained evidence.

## Review Focus

- A client-ID swap cannot provision or access the other portal's role.
- Pending agents cannot obtain sessions or call any protected business/chat method.
- Customer handlers cannot select another user's customer, cart, order, resume, application, preference, or calendar data.
- Deleted password and chat endpoints return 404 and have no hidden route aliases.
- Route inventory drift fails when contracts, scopes, RBAC, server routes, or browser calls diverge.

---

### Task 1: Client-aware OAuth provisioning

**Files:**
- Modify: `../services-repo/services/ceerat-user-service/user/oauth_identity.go`
- Modify: `../services-repo/services/ceerat-user-service/user/repository.go`
- Modify: `../services-repo/services/ceerat-user-service/user/oauth_identity_postgres_test.go`
- Modify: `../services-repo/services/ceerat-user-service/main.go`
- Modify: `../contracts-repo/packages/ceerat-contracts/security/grpc_methods.go`
- Modify: `../contracts-repo/packages/ceerat-contracts/security/oauth_scope_policy.go`
- Modify: service and contract inventories

**Interfaces:**
- Produces: `ProvisioningPolicy{Role string, Status string, CreateCustomer bool}` selected by validated client ID.
- Produces: safe identity result `account_pending` for newly provisioned pending agents.

- [ ] Add failing tests for pending-agent creation, active-customer creation, no customer row for agents, overlap/unknown-policy startup failure, email collision, immutable existing binding, and forged role/status input absence.
- [ ] Run focused user/security tests and confirm the new policy cases fail.
- [ ] Pass a validated policy into identity resolution, persist role/status atomically with identity mapping, and create customer rows only for customer policy.
- [ ] Add current-user/profile permissions for active agents with canonical profile scopes; do not add pending-user business permissions or public methods.
- [ ] Map pending identities to a stable safe error without logging claims or credentials.
- [ ] Run focused tests, all user-service tests, contract security tests, RBAC check, and drift check.

### Task 2: Keycloak clients and reproducible reconciliation

**Files:**
- Modify: `dev/keycloak/ceerat-realm.json`
- Create: `dev/keycloak/reconcile-browser-clients.rb`
- Create: `deploy/render/keycloak/clients/ceerat-web-ui.json`
- Create: `deploy/render/keycloak/clients/ceerat-customer-ui.json`
- Modify: `deploy/render/keycloak/reconcile-live-realm.sh`
- Modify: `deploy/render/keycloak/realm_config_test.rb`
- Modify: `start-stack.sh`

**Interfaces:**
- Produces: public PKCE clients `ceerat-web-ui` and `ceerat-customer-ui` with exact callbacks and canonical optional scopes.

- [ ] Add failing realm tests for exact local/hosted callbacks, PKCE S256, token auth `none`, disabled implicit/direct/service-account flows, exact origins, scopes, registration, and Google broker support.
- [ ] Run realm tests and confirm both missing clients fail.
- [ ] Add both definitions and idempotent local/live reconciliation without client secrets.
- [ ] Add user-service allowed-client and provisioning-policy environment values to local and Render configuration.
- [ ] Run realm tests twice against local Keycloak and prove no duplicate clients/scopes.

### Task 3: Web UI OAuth and agent access boundary

**Files:**
- Modify: `../apps-repo/apps/ceerat-web-ui/internal/config/config.go`
- Create: `../apps-repo/apps/ceerat-web-ui/internal/server/oauth.go`
- Modify: `../apps-repo/apps/ceerat-web-ui/internal/server/server.go`
- Modify: `../apps-repo/apps/ceerat-web-ui/internal/server/server_test.go`
- Modify: `../apps-repo/apps/ceerat-web-ui/internal/apiclient/client.go`
- Modify: login/register/preferences templates and browser assets
- Delete: `../apps-repo/apps/ceerat-web-ui/web/chatgpt-client`

**Interfaces:**
- Consumes: `ceerat-web-ui` token and safe `account_pending` result.
- Produces: `/oauth/login`, `/oauth/register`, `/oauth/google`, `/oauth/callback`, `/logout`, and `/pending`.

- [ ] Add failing tests for PKCE/state, Google hint, registration action, pending page, active agent/admin acceptance, customer denial, secure cookies, CSRF, logout, and production HTTPS/TLS refusal.
- [ ] Delete password login/register/change-password routes, DTOs, adapters, forms, and configuration.
- [ ] Implement OAuth callback/session flow and exact agent/admin page gates.
- [ ] Replace `/chatgpt-client` with the single current agent chat page and API defined in Task 6.
- [ ] Run web UI tests and search for deleted route names, password fields, legacy token parsing, and fallback URLs; require no matches outside removal tests/docs.

### Task 4: Customer UI OAuth and customer-only boundary

**Files:**
- Modify: `../apps-repo/apps/ceerat-customer-ui/internal/config/config.go`
- Create: `../apps-repo/apps/ceerat-customer-ui/internal/server/oauth.go`
- Modify: `../apps-repo/apps/ceerat-customer-ui/internal/server/server.go`
- Modify: `../apps-repo/apps/ceerat-customer-ui/internal/server/server_test.go`
- Modify: `../apps-repo/apps/ceerat-customer-ui/internal/apiclient/client.go`
- Modify: login/register/preferences templates and browser assets
- Delete: `../apps-repo/apps/ceerat-customer-ui/web/chatgpt-client`

**Interfaces:**
- Consumes: `ceerat-customer-ui` token and active customer provisioning.
- Produces: Keycloak OAuth routes and customer-only sessions.

- [ ] Add failing tests for PKCE/state, registration, Google hint, active customer acceptance, agent/admin denial, secure cookies, CSRF, logout, and production HTTPS/TLS refusal.
- [ ] Delete password login/register/change-password and every customer chat route, handler, client, template, asset, configuration value, and test fixture.
- [ ] Implement OAuth callback/session flow and require active customer plus owned customer profile.
- [ ] Run customer UI tests and deterministic searches proving deleted password/chat surfaces do not exist.

### Task 5: Current gRPC adapters and page inventory

**Files:**
- Refactor: both apps' `internal/apiclient/client.go` into domain-focused files
- Create: `../apps-repo/docs/browser-grpc-route-inventory.json`
- Create: `../apps-repo/internal/inventory/browser_routes_test.go`
- Modify: all page templates and JavaScript that reference API routes or stale fields

**Interfaces:**
- Produces: route records `{app, route, role, grpc_methods, scopes, ownership}` verified against canonical security maps.

- [ ] Generate a failing inventory test that compares registered server routes and browser fetch paths with the checked-in route records and canonical gRPC/security inventories.
- [ ] Replace agent adapters with current operational RPC request/response fields and original-token metadata.
- [ ] Replace customer adapters with `My*`/self-scoped RPCs and remove browser-supplied owner identifiers.
- [ ] Fix every page group: profile, customers, services/connections, products/catalog, cart/checkout/payment, orders, preferences, career profiles/resumes/employment, jobs/cart/applications, calendar, companies/jobs/application operations, pricing, and agent chat.
- [ ] Add mapper tests for money minor units, enum/status values, versions, pagination, optional fields, and timestamps.
- [ ] Run both complete app suites and the route inventory test until every route maps to a current method/scope/RBAC rule.

### Task 6: Rebuild internal agent/admin chat service

**Files:**
- Modify: `../apps-repo/ai/ceerat-agent-service/internal/httpapi/server.go`
- Modify: `../apps-repo/ai/ceerat-agent-service/internal/platform/client.go`
- Refactor: `../apps-repo/ai/ceerat-agent-service/internal/agent`
- Modify: agent-service tests and configuration
- Modify: `../apps-repo/docs/app-surface-inventory.json`

**Interfaces:**
- Consumes: original `ceerat-web-ui` bearer and current agent/admin gRPC permissions.
- Produces: one agent/admin chat API and current `AIThreadService` persistence; no customer or compatibility endpoints.

- [ ] Add failing tests for missing/invalid/wrong-client tokens, pending/customer denial, active agent/admin allowance, exact tool scopes, RBAC denial, bounded schemas, and log redaction.
- [ ] Delete customer chat, `/chatgpt-client` prompt adapters, legacy JWT handling, legacy tool aliases, and fallback behavior.
- [ ] Wire shared OAuth validation, identity resolution, role/status checks, current tool policies, original-token gRPC forwarding, and thread APIs.
- [ ] Update web UI chat proxy to the one current endpoint and enforce same-origin mutations.
- [ ] Run agent-service and web UI integration tests plus inventory drift checks.

### Task 7: Local full-stack acceptance

**Files:**
- Create: `dev/keycloak/smoke-browser-apps.py`
- Modify: `start-stack.sh`, `status.sh`, and app run scripts
- Modify: local runbooks

**Interfaces:**
- Produces: redacted local acceptance report with no credentials, claims, cookies, codes, verifiers, or tokens.

- [ ] Start a clean local database, Keycloak, user service, both UIs, and rebuilt agent service from current source.
- [ ] Register through web UI, verify pending-agent denial, activate through protected admin gRPC, then verify agent operational pages and chat.
- [ ] Register a separate customer through customer UI and verify profile, products, cart/checkout, orders, preferences, career, applications, and calendar ownership flows.
- [ ] Verify Google routes reach Keycloak with exact client and broker hint; perform full Google login when provider credentials are configured.
- [ ] Verify wrong client/role/status/scope, anonymous, cross-origin, and cross-owner attempts fail with safe responses.
- [ ] Rerun reconciliation and acceptance to prove idempotency.

### Task 8: Gates, inventories, and documentation

**Files:**
- Modify: both app READMEs and architecture docs
- Modify: service API/security/testing docs and inventories
- Modify: `../apps-repo/docs/app-surface-inventory.json`
- Modify after human validation: builder architecture, security/RBAC, service, and UI standards

**Interfaces:**
- Produces: final source-of-truth documentation and verified builder context.

- [ ] Update service and app inventories from implemented routes and methods; document Keycloak-only credential ownership and pending-agent approval.
- [ ] Run `gofmt`, all affected Go tests, builds, Keycloak tests, route inventory tests, `git diff --check`, and searches for every deleted legacy surface.
- [ ] Run builder `check-context`, `rbac check`, `check drift`, and `check apps`.
- [ ] Run `make verify-platform` from infra and resolve all failures in changed files before acceptance.
- [ ] Obtain human validation of both portals and agent chat, then update only reusable rules in existing builder-agent standards.
