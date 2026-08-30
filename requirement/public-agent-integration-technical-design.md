# CEERAT Public Agent Integration

Status: Proposed technical design  
Date: 2026-08-29  
Scope: Publish a vendor-neutral remote MCP integration that advertises CEERAT operations, schemas, authentication, confirmations, and errors to ChatGPT and other compatible LLM clients. Phase one is limited to OAuth-page registration, authentication, identity/profile, connection, and logout operations.

## 1. Executive summary

The phase-one product experience is:

```text
Customer in ChatGPT or another agent client
  -> connects the published CEERAT integration
  -> client discovers CEERAT tools and JSON schemas
  -> customer registers or authenticates through a CEERAT browser handoff
  -> client receives a customer-delegated OAuth token
  -> model invokes CEERAT tools directly
  -> CEERAT enforces scope, ownership, confirmation, rate, and audit rules
```

The integration is API-first. ChatGPT and other clients call structured MCP operations directly on `ceerat-agent-gateway`, which adapts them to private gRPC calls. There is no public REST layer and no LLM/tool-chain intermediary. The browser remains a narrow security handoff for registration, password entry, MFA, and OAuth consent. Password recovery, verified email/phone changes, and account deletion are deferred to Phase 1B.

Phase one publishes the integration contract and proves the complete identity lifecycle. Jobs, resumes, applications, carts, employer actions, and administrative user management are excluded. Kubernetes remains out of scope for development.

The recommended first production slice is deliberately narrow and identity focused:

1. Publish a remote MCP endpoint with product metadata and phase-one tool discovery.
2. Publish strict input/output/error schemas and risk/confirmation metadata for every operation.
3. Use Keycloak in development for OAuth/OIDC discovery, browser registration/login/consent, PKCE, refresh, and revocation; keep the provider behind standards-based interfaces so it can be changed later.
4. Support direct MCP-to-gRPC operations for identity, the low-risk profile allowlist, and connection management.
5. Return agent-actionable structured errors so clients recover without guessing.
6. Add career and application tools only after the identity integration is proven.

The language model is never the authentication, authorization, or policy enforcement point. The integration proposes operations; CEERAT validates tokens, grants, scopes, ownership, schemas, confirmations, idempotency, and audit requirements before execution.

## 2. Inputs and repository profile

This design is based on:

- `infra/requirement/mcp.md`, which defines the public agent-service goal and the prepare/execute, policy, approval, audit, and task patterns.
- The current Kubernetes deployment under `infra/k8s`.
- The live app, contract, and service inventories loaded by `ceerat-platform-builder-agent`.
- The implementation of `apps-repo/ai/ceerat-agent-service`.
- The career, customer, authentication, and AI-thread protobuf contracts in `contracts-repo`.

The builder context check succeeded with approximately 80 KB of architecture context. Its drift check found no mismatch between protobuf RPCs, known gRPC methods, default role permissions, and the service inventories. Its ownership analysis did not find a strong existing owner for a public OAuth/MCP/policy gateway and returned `new-service-or-existing-module` for a Codex architecture decision. This design resolves that decision in favor of a new service.

### 2.1 Existing capabilities to reuse

`ceerat-agent-service` already has a customer tool profile containing:

```text
get_current_user
get_my_customer_profile
update_my_customer_profile
list_my_skill_profiles
create_skill_profile
add_skill_to_profile
parse_resume_text
import_resume_draft
list_my_resumes
create_resume
download_resume
get_career_market_metrics
search_jobs
get_job
discover_job_application
submit_job_application
get_job_cart
add_job_to_cart
update_job_cart_item
remove_job_from_cart
clear_job_cart
apply_to_job
apply_to_cart_jobs
list_my_applications
get_my_application
```

Its platform client already connects to the `Auth`, `CustomerService`, `CareerProfileService`, `JobService`, `JobCartService`, `JobApplicationService`, and `AIThreadService` gRPC services. This is valuable implementation evidence, but public MCP tools should call a shared internal application layer or gRPC clients directly. They should not invoke the existing chat HTTP endpoint, because that would add an unnecessary LLM loop and blur authorization boundaries.

### 2.2 Current infrastructure gaps

The deployed platform currently has:

- `ceerat-user-service` on internal gRPC port `50051`.
- `ceerat-agent-service` on internal HTTP port `8088`.
- both services in `ceerat-backend` as `ClusterIP` services;
- only frontend applications exposed through the Traefik ingress;
- PostgreSQL and Typesense in `ceerat-data`;
- a shared `ceerat-apps-repo` image for the agent service and UIs;
- placeholder Kubernetes secrets embedded in base manifests.

There is no public backend ingress, TLS/certificate configuration, authorization server, gateway datastore schema, queue/worker, distributed rate limiter, external secret integration, or gateway-specific network policy.

## 3. Goals and non-goals

### 3.1 Goals

- Let ChatGPT and other compatible agent clients discover and invoke CEERAT through one vendor-neutral integration.
- Publish tool descriptions plus strict JSON input/output/error schemas.
- Authenticate each customer through OAuth and issue audience-restricted, least-privilege delegated tokens.
- Support safe customer self-service for OAuth-page registration, identity, low-risk profile updates, connections, and logout.
- Enforce scopes, ownership, validation, confirmation, rate limits, idempotency, and audit on the CEERAT server.
- Support safe prepare/confirm/execute/verify tool flows.
- Make every attempted consequential action explainable and auditable.
- Preserve the private status of internal gRPC services and databases.
- Keep the website usable without an agent and share the same underlying domain/security rules.
- Remain interoperable rather than creating vendor-specific CEERAT APIs.

### 3.2 Non-goals for the first release

- Replacing `ceerat-agent-service` or the existing CEERAT chat UI.
- Exposing internal gRPC reflection or arbitrary RPC proxying to external clients.
- Allowing agents to supply or override authorization decisions.
- Browser automation as the primary execution path.
- Supporting bulk autonomous applications before single-item controls are proven.
- Making PostgreSQL or Typesense directly accessible to agents.
- Implementing a general-purpose workflow engine in phase one.
- Depending on one vendor's proprietary connector behavior.
- Creating or changing Kubernetes manifests, ingress resources, network policies, deployment images, autoscaling, or cluster secrets during development.

### 3.3 Development deployment boundary

All implementation and verification phases target the local CEERAT development stack. The gateway runs locally with a development OAuth issuer and calls `ceerat-user-service` over loopback. ChatGPT cannot reach `localhost`, so final client interoperability requires a temporary isolated HTTPS test environment. Kubernetes is explicitly deferred.

```text
MCP client or temporary HTTPS interoperability endpoint
      |
      v
ceerat-agent-gateway on localhost:8090/mcp
      |
      v
localhost:50051 ceerat-user-service
```

Temporary tunnels must use test accounts, unpredictable URLs, access controls where possible, short lifetimes, and no production secrets. They are never the production deployment mechanism.

## 4. Target architecture

```text
ChatGPT / Claude / Copilot-style client
          |
          | remote MCP + customer OAuth access token
          v
ceerat-agent-gateway
  protocol negotiation and tool discovery
  JSON Schema validation
  token/grant/scope validation
  confirmation, rate, idempotency and audit
          |
          | private authenticated gRPC
          v
ceerat-user-service
          |
          +--> PostgreSQL
          +--> Typesense where applicable

Browser handoff used only for:
registration / credentials / MFA / OAuth consent
```

### 4.1 Service boundaries

| Component | Responsibility | Must not do |
|---|---|---|
| External agent client | Discover tools, hold delegated tokens, invoke operations, present confirmations | Receive customer passwords/MFA or decide authorization |
| Customer | Enter credentials/MFA and approve sensitive actions | Send passwords or security codes in the conversation |
| Agent gateway | MCP, schemas, OAuth token/grant/scope enforcement, confirmations, errors, audit, gRPC adaptation | Call an LLM to decide authorization or accept identity in tool arguments |
| Keycloak authorization UI | Secure registration/login/MFA/consent handoff | Expose secrets to model/tool payloads or contain CEERAT business operations |
| User service | Authenticate, validate, enforce RBAC/ownership, persist customer changes, audit | Assume a request is safe because ChatGPT generated it |
| Existing agent service | CEERAT-owned chat orchestration and reusable adapter evidence | Serve as the public authorization boundary |

### 4.2 Secure browser handoff contract

Browser handoffs are deliberately narrow and must:

- use server-rendered or reliably hydrated semantic HTML;
- give controls real `<label>` elements, stable names, appropriate input types, and accessible descriptions;
- use short-lived, single-use, customer/client/action-bound transactions and stable CEERAT HTTPS URLs;
- show page titles, headings, breadcrumbs, signed-in identity, and current resource state;
- return field errors adjacent to fields and a top-level error summary;
- preserve non-secret form input after validation failure;
- use explicit Preview, Confirm, Cancel, and Success states for consequential actions;
- add unique operation/reference IDs to success and uncertain-result pages;
- return only opaque status IDs to the agent; never return entered secrets or browser session cookies;
- never embed instructions in user-controlled content that the server treats as trusted agent commands.

### 4.3 Interoperability boundary

Remote MCP is the canonical vendor-neutral integration. ChatGPT publication may add vendor packaging or optional UI, but CEERAT tool names, schemas, scopes, and behavior remain shared with other compatible clients.

## 5. MCP and OAuth profile

### 5.1 MCP transport

Implement the current remote HTTP transport supported by the chosen MCP SDK and pin the protocol revision in source and compatibility tests. Use a stateless request core so any gateway pod can serve a call. If a negotiated streaming response is supported, keep it at the HTTP edge and do not make pod affinity part of correctness.

Required public surfaces include:

```text
POST /mcp
GET  /.well-known/oauth-protected-resource
GET  /.well-known/oauth-protected-resource/mcp   # if required by endpoint layout
GET  /healthz                                    # internal/load-balancer use
GET  /readyz                                     # internal/load-balancer use
```

Do not expose diagnostics, metrics, profiling, or gRPC reflection publicly.

An unauthenticated client must be able to profile the product without seeing private data. Before login, expose only protocol metadata, OAuth discovery, product/capability descriptions, JSON schemas, risk annotations, and the explicitly public bootstrap tools in section 7.1. Tool listing may describe authenticated tools so the agent can explain CEERAT, but each definition must declare its required scope and authentication state. Calling a protected tool without a token must start OAuth discovery; it must not leak whether a customer or resource exists.

### 5.2 OAuth requirements

The MCP resource server must publish OAuth Protected Resource Metadata and identify its accepted authorization server. The authorization server must publish OAuth Authorization Server Metadata or OpenID Connect discovery metadata. The authorization code flow must use PKCE. Access tokens must be short lived, audience restricted to the MCP resource, and validated for issuer, audience, signature, time bounds, client, subject, scopes, and revocation state where applicable.

Recommended identifiers:

```text
resource: https://agents.ceerat.com/mcp
issuer:   https://auth.ceerat.com
aud:      https://agents.ceerat.com/mcp
subject:  stable CEERAT user identifier
tenant:   CEERAT customer/account identifier
```

Use asymmetric signing and automatic JWKS rotation. Never forward the public OAuth token directly to arbitrary downstream services. Prefer token exchange or a signed internal identity envelope with a narrow audience; until that exists, the gateway may call gRPC with an internal service credential plus explicit end-user identity metadata that the user service independently validates.

### 5.3 Client onboarding

Use two trust tiers:

1. Pre-registered clients for production integrations such as ChatGPT, Claude, and approved enterprise platforms.
2. Metadata-based or dynamic registration for developer/sandbox clients, with redirect-URI validation, software/client metadata checks, quotas, and an approval path.

Client ID Metadata Documents are preferred where supported by the selected protocol revision. Dynamic Client Registration can be a compatibility option, not an unbounded anonymous production-registration endpoint.

Store client identity separately from user grants:

```text
OAuth client: identifies the assistant/application vendor
Grant:        identifies what one CEERAT customer allowed that client to do
Token:        short-lived proof derived from the grant
```

Do not confuse three different registrations:

```text
Agent client registration: identifies ChatGPT, Claude, or another MCP host
Customer account registration: creates a human CEERAT account
Connection authorization: lets that customer grant the client selected scopes
```

The agent client is registered once per client/vendor or installation. Customer registration and connection authorization occur per customer. A customer may already have an account and skip customer registration.

### 5.4 Scope model

Start with explicit, capability-oriented scopes:

```text
# Phase 1
openid
profile
ceerat.profile.read
ceerat.profile.write
ceerat.connections.read
ceerat.connections.revoke

# Later phases
ceerat.account.security
ceerat.resumes.read
ceerat.resumes.write
ceerat.jobs.search
ceerat.jobs.read
ceerat.applications.read
ceerat.applications.prepare
ceerat.applications.submit
ceerat.applications.withdraw
ceerat.tasks.read
ceerat.tasks.cancel
```

Avoid a broad `ceerat.all` scope. A scope permits an action class; it does not eliminate ownership checks, policy evaluation, or approval.

### 5.5 Who logs in

The external assistant does not log in by receiving a CEERAT email and password. The human customer authenticates on a CEERAT-owned page and grants a specific agent client permission to act on their behalf. The client then receives a delegated OAuth access token.

```text
Customer credentials -> CEERAT authorization server only
Delegated token      -> external assistant/MCP client
Internal identity    -> CEERAT gateway and private services
```

This separation is mandatory. A prompt such as "log in with my username and password" must not cause the model to collect credentials or call a password-login tool. CEERAT passwords, MFA codes, recovery codes, session cookies, authorization codes, refresh tokens, and client secrets must never appear in MCP tool arguments or model context.

There are three supported identity cases:

| Actor | Login/grant method | Result |
|---|---|---|
| Human using ChatGPT/Claude/Copilot-style client | Browser authorization code flow with PKCE | Customer-delegated token |
| Human using a terminal, TV, or client without a usable browser callback | Deferred; OAuth Device Authorization Grant may be added after Phase 1 | No Phase 1 support |
| Trusted server automation owned by an organization | Client credentials or workload identity | Service principal token, never silent customer impersonation |

Client credentials must not be used to represent an individual customer. If organization automation needs customer access, CEERAT must model an explicit administrative delegation with its own scopes, audit trail, and policy.

### 5.6 Interactive login and connection flow

This is the primary flow for external LLM applications:

```text
1. Customer says: "Connect to CEERAT" or invokes a CEERAT tool.
2. MCP client calls https://agents.ceerat.com/mcp without a token.
3. Gateway returns HTTP 401 with WWW-Authenticate containing the
   OAuth protected-resource metadata URL.
4. Client reads protected-resource metadata, discovers
   https://auth.ceerat.com, and loads authorization-server metadata.
5. Client creates PKCE verifier/challenge, state, and nonce values.
6. Client opens the CEERAT authorization URL in the customer's browser.
7. Customer signs in directly to CEERAT and completes MFA if required.
8. CEERAT displays the client identity and requested scopes.
9. Customer selects/accepts scopes and CEERAT creates an agent grant.
10. Authorization server redirects an authorization code to the client's
    exact registered redirect URI.
11. Client exchanges the one-time code plus PKCE verifier for tokens.
12. Client calls /mcp with the access token.
13. Gateway validates the token, loads the active grant, and performs tools.
```

Illustrative authorization request:

```http
GET https://auth.ceerat.com/oauth2/authorize?
  response_type=code&
  client_id=https%3A%2F%2Fassistant.example%2Foauth-client.json&
  redirect_uri=https%3A%2F%2Fassistant.example%2Foauth%2Fcallback&
  code_challenge=<base64url-sha256>&
  code_challenge_method=S256&
  state=<unguessable>&
  nonce=<unguessable>&
  resource=https%3A%2F%2Fagents.ceerat.com%2Fmcp&
  scope=openid%20profile%20ceerat.jobs.search%20ceerat.jobs.read
```

The consent page must show:

- verified client name, publisher, and privacy/support links;
- the CEERAT account being connected;
- scopes translated into plain language;
- which permissions allow external side effects;
- whether each side effect still requires approval;
- grant duration and how to disconnect;
- a warning when the client is unverified or in sandbox status.

Login and consent are separate events. An already authenticated CEERAT user may skip password entry but must still see consent when a new client or materially broader scope set is requested. Existing grants may omit repeated consent only under an explicit CEERAT policy.

### 5.7 Deferred device login for headless clients

Terminal and headless clients are outside Phase 1. If added later, implement the OAuth Device Authorization Grant through the selected authorization server:

```text
1. Client requests a device code.
2. Client shows verification URI and short user code.
3. Customer opens that URI on a separate trusted device.
4. Customer logs into CEERAT, enters/confirms the code, and grants scopes.
5. Client polls the token endpoint at the server-provided interval.
6. Server issues a customer-delegated token after approval.
```

Device codes must be short lived, single use, rate limited, and resistant to code phishing. The UI must show which client and scopes the code will authorize. Do not invent an MCP tool such as `login(username,password)` as a substitute.

### 5.8 Login, OAuth, and account endpoints

The exact paths depend on the selected authorization server, but CEERAT needs the following logical surfaces:

```text
# MCP resource discovery
GET  /.well-known/oauth-protected-resource
GET  /.well-known/oauth-protected-resource/mcp

# Authorization-server discovery
GET  /.well-known/oauth-authorization-server
GET  /.well-known/openid-configuration              # when OIDC is used

# OAuth protocol
GET  /oauth2/authorize
POST /oauth2/token
POST /oauth2/revoke
POST /oauth2/introspect                             # optional for opaque tokens
POST /oauth2/device-authorization                   # optional headless flow
POST /oauth2/register                               # optional controlled DCR
GET  /.well-known/jwks.json

# Keycloak-owned browser experience (provider-specific concrete paths)
GET/POST <keycloak registration route>
GET/POST <keycloak login/MFA route>
GET/POST <keycloak consent route>

# CEERAT-owned connection management
GET  /settings/agent-connections
POST /settings/agent-connections/{grant_id}/revoke
```

Do not implement these routes inside the LLM-facing MCP tool registry. OAuth endpoints and registration/login/consent pages belong to Keycloak on a CEERAT-controlled browser origin. The exact Keycloak paths are configuration, not CEERAT public API contracts. Cookies used there must be `Secure`, `HttpOnly`, and appropriately `SameSite`; authorization requests require CSRF/state protection and exact redirect-URI matching.

### 5.9 Token lifecycle

Recommended initial token policy:

```text
authorization code: 60-120 seconds, single use
access token:        5-15 minutes
refresh token:       rotating, sender/client bound where supported
device code:         5-10 minutes
grant:               until expiry or customer/admin revocation
```

The client stores tokens, not the model. Tool-call transcripts and chat history must never contain them. The MCP transport attaches the access token in the HTTP `Authorization` header. Refresh occurs between the client and token endpoint without involving the model.

On every MCP call, the gateway verifies the token and authoritative grant status. Revoking a grant prevents new calls even if a self-contained JWT has time remaining; implement this with short token lifetimes plus a cached revocation/grant-version check. Refresh-token reuse must revoke the token family and create a security event.

Scope elevation requires a new authorization request and customer consent. Refresh may maintain or narrow existing scopes but must never silently broaden them.

### 5.10 Identity propagation into CEERAT services

After public-token validation, the gateway creates an internal caller identity containing both the external client and the human subject. The current `ceerat-agent-service` forwards a customer's CEERAT JWT to gRPC; the public gateway should use a stronger service-to-service pattern:

```text
External OAuth token
        |
        | validate issuer, audience, signature, time, client, grant, scopes
        v
Gateway AgentPrincipal
        |
        | token exchange OR short-lived internally signed assertion
        v
ceerat-user-service JWT/RBAC/ownership checks
```

The internal assertion should have a private-service audience, a lifetime measured in minutes or less, and claims for user ID, customer ID, external client ID, grant ID, scopes, and original token ID. The user service validates it using a gateway-specific trust configuration and still performs method-level RBAC and record ownership checks. It must reject ordinary public OAuth tokens presented directly to gRPC.

The audit trail retains both identities:

```text
actor:       CEERAT customer/user
delegate:    external assistant client
entrypoint:  ceerat-agent-gateway
executor:    ceerat-user-service or worker
```

### 5.11 LLM-driven customer lifecycle

The LLM-facing experience is OAuth authorization followed by direct MCP-to-gRPC operations, not credential automation. The MCP host initiates authorization; the model never initiates a separate CEERAT registration transaction. Secret entry happens only on the Keycloak authorization page.

```text
LLM client connects
  -> reads MCP/server metadata and public tool schemas
  -> a protected call starts OAuth authorization
  -> customer chooses Register or Sign in on the Keycloak page
  -> customer completes credentials, verification, MFA, and consent there
  -> client receives delegated OAuth token
  -> authenticated tools become available
  -> LLM performs customer-approved self-service operations
```

Registration and login:

```text
1. An unauthenticated protected call produces the OAuth challenge.
2. The MCP host—not the model—opens the authorization URL and performs PKCE.
3. Customer registers or enters existing credentials/MFA in Keycloak and grants consent.
4. The host stores tokens outside model context.
5. The model can call get_authentication_status and authenticated tools.
```

Phase 1 exposes no registration, password, recovery, verified-contact-change, or account-deletion MCP tool. Password recovery remains available through Keycloak's browser UI but is not orchestrated or polled by the model. Account deletion and other sensitive identity workflows require a separate Phase 1B design and acceptance review.

## 6. Request processing pipeline

Every `tools/call` follows the same ordered pipeline:

```text
1. Parse request and negotiate MCP protocol version
2. Classify the call as public-bootstrap or protected
3. For public-bootstrap calls, validate client/transaction proof and apply
   anti-abuse controls; for protected calls, authenticate token and resolve
   client + user + customer grant
4. Resolve registered tool definition
5. Validate input against pinned JSON Schema
6. Check scope and client restrictions when protected
7. Check user/customer ownership and account status when applicable
8. Load customer policy and evaluate deterministic constraints
9. Determine confirmation/approval requirement and validate its binding
10. Apply per-client, per-user/transaction, per-tool, and global rate limits
11. Reserve or replay idempotency record
12. Execute private gRPC call or enqueue durable task
13. Persist result and audit outcome
14. Return structured MCP content with stable error metadata
```

For writes, create the audit attempt and idempotency reservation transactionally before the downstream side effect. Complete the record after the result. When the downstream outcome is uncertain, return `OUTCOME_UNKNOWN` and reconcile it; never blindly retry a consequential action.

### 6.1 Principal model

The authorization context should be immutable for a request:

```go
type AgentPrincipal struct {
    UserID     string
    CustomerID string
    ClientID   string
    GrantID    string
    TokenID    string
    Scopes     []string
    Issuer     string
    Audience   string
}
```

The gateway derives this structure only from validated tokens and server-side grant data. Tool input schemas must never accept `user_id`, `customer_id`, `approved`, `scope`, or role fields that choose the acting identity.

## 7. Phase-one structured tool catalog

Public tool names are a stable product API. They should not mirror internal RPC names blindly. Each tool needs a precise description, JSON input and output schemas, required scope, risk class, timeout, rate-cost, idempotency mode, approval mode, and downstream adapter.

### 7.1 Identity and user-management operations

| Tool | Access/scope | Effect | Confirmation | Existing backing capability |
|---|---|---:|---:|---|
| `describe_ceerat` | Public, heavily rate limited | Read public product/capability metadata | Never | New static gateway metadata |
| `get_authentication_status` | Authenticated, `openid` | Read current connection identity/scopes | Never | Gateway principal/grant |
| `get_current_user` | `profile` | Read | Never | Validated session/user |
| `get_my_customer_profile` | `ceerat.profile.read` | Read | Never | `CustomerService.GetMyCustomerProfile` |
| `prepare_my_customer_profile_update` | `ceerat.profile.write` | Validate and preview profile patch | Never | New gateway preparation over `CustomerService` |
| `update_my_customer_profile` | `ceerat.profile.write` | Execute prepared CEERAT account write | Bound confirmation | `CustomerService.UpdateMyCustomerProfile` |
| `list_my_agent_connections` | `ceerat.connections.read` | Read | Never | New grant query in `AgentGatewayService` |
| `revoke_my_agent_connection` | `ceerat.connections.revoke` | Security write | Always | New grant revocation in `AgentGatewayService` |
| `logout_current_connection` | Authenticated | Revoke current grant/token family | Confirm | New grant/token revocation |

The actual registration, login, credential submission, MFA, consent, token exchange, and token refresh remain OAuth/browser operations rather than MCP tool arguments. Connection tools let an authorized agent explain active connections or help revoke a named connection. Revoking/logging out the current connection succeeds and then invalidates subsequent calls.

Phase-one structured tools cover only authentication state, identity/profile, and agent connections without passing secrets through the model. They do not expose administrator-created users, administrator role/status changes, password operations, verified-contact changes, or account deletion.

### 7.2 User-management rules

Profile updates use prepare/confirm execution:

```text
get_my_customer_profile
  -> returns profile plus resource_version

prepare_my_customer_profile_update
  -> accepts patch + expected resource_version
  -> returns normalized changes, warnings, preparation_id, content_hash, expiry

update_my_customer_profile
  -> accepts preparation_id plus confirmation
  -> verifies owner, version, hash, expiry, and one-time use
  -> applies patch and returns new resource_version
```

Omitted fields remain unchanged. Clearing a nullable field requires an explicit `null` allowed by schema. Unknown fields are rejected. The Phase 1 editable allowlist is `display_name`, `first_name`, `last_name`, `locale`, `time_zone`, `city`, `state_or_region`, and `country_code`, subject to fields actually supported by the current Customer contract. Identity IDs, role, status, email, phone, verification state, password fields, security settings, and ownership fields are never directly editable. Requests for excluded fields return `INVALID_ARGUMENT` with a safe field reason; they do not create a security-action handoff in Phase 1.

Concurrent modification returns `CONFLICT` with the current authorized `resource_version` and `agent_action=refresh_resource`. Preparations are short lived and single use. The confirmation must bind the customer, client, exact normalized patch hash, expected version, and expiry.

Registration and recovery transactions use an opaque public transaction ID plus a separate high-entropy proof. Store only a hash of the proof. Status lookup must require both values and return an enumeration-resistant result. Action URLs use HTTPS in production, an allowlisted CEERAT origin, no open redirect, and no customer PII in the path/query.

Agent-client registration, customer registration, and customer authorization have separate schemas, records, rate limits, and audit event types. A customer-account registration tool cannot register or modify an OAuth client, and an OAuth client-registration endpoint cannot create a CEERAT customer.

### 7.3 Later tool catalog

| Tool group | Earliest phase | Candidate tools |
|---|---:|---|
| Job and application reads | 2 | `list_my_resumes`, `search_jobs`, `get_job`, `list_my_applications`, `get_my_application` |
| Preparation and policy | 3 | `prepare_application` |
| Consequential execution | 4 | `submit_application` |
| Durable campaigns | 5 | `get_task`, `cancel_task`, campaign tools |

### 7.4 Prepare/execute contract

`prepare_application` should return a server-created immutable preparation:

```json
{
  "preparation_id": "prep_01...",
  "expires_at": "2026-08-29T20:15:00Z",
  "job": {
    "id": "job_8271",
    "company": "Acme",
    "title": "Senior Go Engineer",
    "salary_min": 150000,
    "salary_max": 180000,
    "currency": "USD",
    "locations": ["Remote"]
  },
  "resume": {"id": "resume_12", "name": "Backend-Go.pdf"},
  "policy": {"decision": "allow", "policy_version": 7},
  "approval": {"required": true, "status": "pending"},
  "warnings": [],
  "content_hash": "sha256:..."
}
```

`submit_application` accepts `preparation_id` and an idempotency key, not a second free-form copy of all application facts. The gateway verifies that the preparation is unexpired, unchanged, belongs to the principal, still passes current hard safety rules, and has the required approval.

### 7.5 Tool metadata

Use MCP annotations such as read-only, destructive, idempotent, and open-world hints where supported, but treat them as client UX hints only. Gateway enforcement is authoritative. Output schemas should be defined and tested as strictly as input schemas. Include `next_cursor`, `has_more`, and bounded default/max page sizes on list/search tools.

## 8. Policy and approval model

### 8.1 Policy layers

Evaluate policies in this order, with deny taking precedence:

1. Platform hard safety rules.
2. Legal/compliance and account restrictions.
3. Client-specific restrictions.
4. Customer permission policy.
5. Customer constraint policy.
6. Per-action approval rule.

Example policy document:

```json
{
  "version": 7,
  "tools": {
    "search_jobs": {"permission": "allow", "approval": "never"},
    "prepare_application": {"permission": "allow", "approval": "never"},
    "submit_application": {
      "permission": "allow",
      "approval": "always",
      "constraints": {
        "minimum_salary": {"amount": 130000, "currency": "USD"},
        "allowed_locations": ["Dallas", "Remote"],
        "excluded_companies": [],
        "maximum_per_day": 10
      }
    }
  }
}
```

Policies must have versions, effective timestamps, validation schemas, and change audits. The evaluation result records the policy version and normalized facts used. Salary with missing currency/range, ambiguous location, or incomplete application data must fail closed or require explicit approval—never be guessed by an LLM.

### 8.2 Approval lifecycle

```text
pending -> approved -> consumed
       \-> denied
       \-> expired
approved -> revoked (until consumed)
```

An approval binds to the customer, client, tool, preparation/content hash, policy version, and expiry. It is single use for submission. Approval can occur in the CEERAT UI through a notification/deep link. Protocol-native elicitation may improve UX when supported, but it must create or consume the same server-side approval record and must not be the only approval mechanism.

## 9. Persistence model

The builder standards say backend services own OLTP schema and apps/agents must not write PostgreSQL directly. Therefore gateway state should be owned by a backend service module or by the new gateway through a narrowly owned schema and repository—not by frontend code. For the first implementation, a dedicated `agentgateway` module inside `ceerat-user-service` is reasonable for transactional domain state, while the stateless gateway exposes MCP and calls that module over gRPC.

Recommended tables:

| Table | Purpose | Important constraints/indexes |
|---|---|---|
| `agent_clients` | Registered external client metadata and trust tier | unique client ID; status; redirect metadata hash |
| `agent_grants` | Customer consent to a client | user/customer/client FK; status; scope set; revoked/expiry indexes |
| `agent_policies` | Versioned executable customer policy | unique customer + version; active partial index |
| `agent_preparations` | Immutable prepared action snapshot | owner; tool; payload hash; policy version; expiry |
| `agent_approvals` | Approval decision and binding | preparation/hash FK; state; actor; expiry; single consumption |
| `agent_idempotency_keys` | Write deduplication and result replay | unique principal + tool + key; request hash; state; TTL |
| `agent_tasks` | Durable asynchronous operation | owner/client; state; progress; cancel flag; lease fields |
| `agent_task_items` | Per-job campaign outcomes | task FK + ordinal; unique target/action key |
| `agent_audit_events` | Append-only security/business audit | event ID; principal/client/tool/time/result indexes |

Do not store raw access tokens, resume contents, cover letters, or full application payloads in audit logs. Store token IDs, object IDs, bounded redacted summaries, and keyed hashes where correlation is required. Encrypt sensitive preparation/task payloads at rest and enforce retention/deletion policies.

### 9.1 Idempotency states

```text
reserved -> executing -> succeeded
                     \-> failed_retryable
                     \-> failed_terminal
                     \-> outcome_unknown
```

The unique key is `(grant_id, tool_name, idempotency_key)`. Reuse with the same request hash returns the recorded result; reuse with a different hash returns `IDEMPOTENCY_CONFLICT`. Keep submission keys longer than the external application's maximum reconciliation period.

## 10. Internal contracts

Add a contract package such as `agentgateway` rather than placing public-control data in the MCP process only. Candidate RPCs:

```text
service AgentGatewayService {
  rpc GetAuthenticationStatus(GetAuthenticationStatusRequest) returns (AuthenticationStatusResponse);
  rpc ResolveGrant(ResolveGrantRequest) returns (ResolveGrantResponse);
  rpc ListMyAgentConnections(ListMyAgentConnectionsRequest) returns (AgentConnectionPage);
  rpc RevokeMyAgentConnection(RevokeMyAgentConnectionRequest) returns (AgentConnectionResponse);
  rpc LogoutCurrentConnection(LogoutCurrentConnectionRequest) returns (LogoutResponse);
  rpc GetActivePolicy(GetActivePolicyRequest) returns (PolicyResponse);
  rpc PrepareApplication(PrepareApplicationRequest) returns (PreparationResponse);
  rpc RequestApproval(RequestApprovalRequest) returns (ApprovalResponse);
  rpc RecordApprovalDecision(RecordApprovalDecisionRequest) returns (ApprovalResponse);
  rpc SubmitPreparedApplication(SubmitPreparedApplicationRequest) returns (SubmissionResponse);
  rpc GetTask(GetTaskRequest) returns (TaskResponse);
  rpc CancelTask(CancelTaskRequest) returns (TaskResponse);
  rpc ListMyAgentActivity(ListMyAgentActivityRequest) returns (AuditEventPage);
}
```

Keep token signature validation at the gateway, but resolve the token's subject/client/grant against authoritative server-side state. All user-owned RPC handlers must use `AuthenticatedUserFromContext` and repository-level ownership predicates. New protected methods must be added to `KnownGRPCMethods` and `DefaultRolePermissions`; public methods must remain minimal.

Use the existing interceptor order required by platform standards:

```text
JWT -> RBAC -> structured logging -> handler
```

The gateway also needs its own HTTP middleware order corresponding to the request pipeline in section 6.

## 11. Agent and browser-handoff error contract

Browser-handoff errors must be understandable from the rendered page without requiring the agent to inspect internal APIs or parse logs. Every failed action page must provide:

- a concise page-level summary using `role="alert"` or an accessible live region;
- field-level messages connected through `aria-describedby`;
- a stable, non-sensitive error code visible in the page or semantic markup;
- a plain-language explanation of what failed;
- whether anything was changed;
- the next safe action: correct fields, sign in again, retry, wait, return, contact support, or ask the user to take over;
- a correlation/reference ID for unexpected failures;
- preserved non-secret input and focus moved to the error summary or first invalid field.

Recommended rendered pattern:

```html
<section role="alert" aria-labelledby="error-title" data-error-code="PROFILE_VERSION_CONFLICT">
  <h1 id="error-title">Your profile changed in another session</h1>
  <p>No changes were saved.</p>
  <p>Reload the profile, review the latest values, and try again.</p>
  <a href="/account/profile">Reload profile</a>
  <p>Reference: req_01...</p>
</section>
```

For form validation, return the same page with an appropriate `4xx` status when feasible. Authentication expiration redirects to login with a safe return target and a visible explanation. Rate limits use `429` plus `Retry-After` and render the retry time. Unexpected failures use `5xx`, say whether the operation is known not to have executed or has an uncertain outcome, and provide a status/history link rather than encouraging duplicate submission.

Never reveal stack traces, SQL/provider errors, private hostnames, CSRF tokens, cookies, credentials, reset tokens, whether an unrelated email/account exists, or another customer's data. Browser errors and JSON errors from customer-UI handlers must map to the same stable code and meaning.

### 11.1 Structured-protocol errors

The earlier minimal error shape is not sufficient for a reliable AI client. It identifies the failure but does not consistently tell the agent which action is safe next, which input fields are invalid, which scopes are missing, whether user interaction is required, or how long to wait. Errors must be actionable, bounded, safe to show to the user, and deterministic enough that an agent does not have to infer recovery from prose.

### 11.2 Two structured error layers

Keep protocol/authentication failures separate from tool-execution failures:

- Before an authenticated MCP request exists, use the correct HTTP status and `WWW-Authenticate` challenge. For example, a missing/expired token returns `401`, protected-resource metadata, and only safe OAuth error information.
- After a valid MCP session invokes a known tool, return a normal MCP tool result marked as an error, with the structured CEERAT error envelope below. This lets the agent inspect and act on the failure without treating every business denial as a broken MCP transport.
- Invalid JSON-RPC/MCP envelopes, unsupported protocol versions, unknown methods, and server-level faults use MCP/JSON-RPC protocol errors rather than CEERAT business codes.

Do not return login or consent URLs from arbitrary downstream errors. OAuth discovery drives authentication. When user interaction is required after authentication, return only a CEERAT-owned HTTPS action URL or opaque action ID produced by the gateway.

### 11.3 Common LLM-facing response envelope

Every CEERAT tool returns one versioned discriminated union. Exactly one of `data` or `error` is present. Transport metadata remains outside domain data so clients can validate and correlate a response without parsing prose.

Successful result:

```json
{
  "schema_version": "1.0",
  "ok": true,
  "data": {
    "user": {
      "id": "usr_01...",
      "display_name": "Test User"
    }
  },
  "meta": {
    "request_id": "req_01...",
    "tool": "get_current_user",
    "operation_state": "completed"
  }
}
```

Failed result:

```json
{
  "schema_version": "1.0",
  "ok": false,
  "error": {
    "code": "CONFLICT",
    "category": "conflict",
    "message": "The customer profile changed after preparation.",
    "user_message": "Your profile changed. I need to reload it before applying this update.",
    "retryable": false,
    "agent_action": "refresh_resource",
    "details": {
      "resource_type": "customer_profile",
      "current_version": "17",
      "suggested_tool": {
        "name": "get_my_customer_profile",
        "arguments": {}
      }
    }
  },
  "meta": {
    "request_id": "req_02...",
    "tool": "update_my_customer_profile",
    "operation_state": "not_started"
  }
}
```

Common fields:

| Field | Requirement |
|---|---|
| `schema_version` | Required major/minor response-contract version; breaking changes require a new major version |
| `ok` | Required discriminator; `true` requires `data`, `false` requires `error` |
| `data` | Tool-specific strict success schema; absent on failure |
| `error` | Code-specific strict error union; absent on success |
| `meta.request_id` | Required opaque correlation identifier on every response |
| `meta.tool` | Required canonical tool name |
| `meta.operation_state` | Required enum: `not_started`, `completed`, or `outcome_unknown`; read-only success is `completed` |

Tool-specific `data` must contain authoritative identifiers, status, and resource version where relevant. A mutation result returns the committed resource or a bounded authoritative summary plus its new version; it must not return only prose such as `"updated successfully"`. Timestamps use RFC 3339 UTC, identifiers are opaque strings, enums are closed, unknown response fields are rejected in conformance tests, and nullable values are explicit in JSON Schema.

Pagination uses the same names everywhere: `items`, `next_cursor`, and `has_more`. Empty collections return `items: []`, not `null`. A cursor is opaque and scoped to the principal, client, tool, filters, and expiry.

`suggested_tool` is optional and advisory. Its name must be selected from the authenticated client's currently advertised tool registry, and its arguments must validate against that tool's input schema. It may never supply identity, authorization, confirmation, password, MFA, token, or role values. The server still enforces every requirement when the suggested call is made.

### 11.4 Agent-actionable error envelope

Return stable machine-readable error codes in MCP tool results without leaking internals:

```json
{
  "schema_version": "1.0",
  "ok": false,
  "error": {
    "code": "APPROVAL_REQUIRED",
    "category": "user_action_required",
    "message": "Customer approval is required before submission.",
    "user_message": "Review and approve this application in CEERAT before I submit it.",
    "retryable": false,
    "agent_action": "ask_user_to_approve",
    "details": {
      "approval_id": "apr_01...",
      "expires_at": "2026-08-29T20:15:00Z",
      "action_url": "https://customer.ceerat.com/agent-approvals/apr_01..."
    }
  },
  "meta": {
    "request_id": "req_01...",
    "tool": "submit_application",
    "operation_state": "not_started"
  }
}
```

Required fields:

| Field | Purpose |
|---|---|
| `code` | Stable programmatic CEERAT error identifier |
| `category` | Broad routing class such as authentication, authorization, validation, conflict, user action, throttling, dependency, or internal |
| `message` | Concise technical explanation safe for the agent and logs |
| `user_message` | Optional plain-language text safe for the agent to relay verbatim |
| `retryable` | Whether retry can succeed without changing request, identity, permission, or user state |
| `agent_action` | Enumerated next step, never unrestricted instructions |
| `details` | Code-specific, schema-defined, redacted recovery data |

`category` and `agent_action` are closed enums in the published schema. `details` is a discriminated union keyed by `error.code`; it is not an open-ended map. The common `meta.request_id` is the sole public correlation identifier, avoiding competing request/correlation fields.

Allowed initial `agent_action` values:

```text
reauthenticate
request_additional_scope
ask_user_to_confirm
ask_user_to_approve
correct_arguments
refresh_resource
retry_after_delay
check_operation_status
choose_different_resource
contact_support
none
```

The agent must not parse `message` to decide recovery. Its primary decision inputs are `code`, `retryable`, `agent_action`, and typed `details`.

### 11.5 Code-specific recovery details

Cross-phase code registry:

```text
UNAUTHENTICATED
TOKEN_EXPIRED
TOKEN_AUDIENCE_INVALID
GRANT_REVOKED
REGISTRATION_ACTION_REQUIRED
REGISTRATION_EXPIRED
SECURITY_ACTION_REQUIRED
SECURITY_ACTION_EXPIRED
INSUFFICIENT_SCOPE
FORBIDDEN
INVALID_ARGUMENT
NOT_FOUND
CONFLICT
PRECONDITION_FAILED
POLICY_DENIED
APPROVAL_REQUIRED
APPROVAL_EXPIRED
IDEMPOTENCY_CONFLICT
RATE_LIMITED
DEPENDENCY_UNAVAILABLE
OUTCOME_UNKNOWN
INTERNAL
```

Phase 1 tool schemas include only codes reachable by that tool. `REGISTRATION_*`, `SECURITY_ACTION_*`, `POLICY_DENIED`, and `APPROVAL_*` remain reserved for later phases and must not appear in the Phase 1 advertised error unions.

Provide only the relevant typed fields for each code:

| Error | `agent_action` | Required safe details |
|---|---|---|
| `UNAUTHENTICATED`, `TOKEN_EXPIRED` | `reauthenticate` | OAuth resource metadata URL; never a token or credential |
| `REGISTRATION_ACTION_REQUIRED` | `ask_user_to_confirm` | opaque registration ID, expiry, CEERAT-owned HTTPS action URL |
| `REGISTRATION_EXPIRED` | `none` | safe instruction to start a new registration; no account-existence signal |
| `SECURITY_ACTION_REQUIRED` | `ask_user_to_confirm` | opaque action ID/type, expiry, CEERAT-owned HTTPS action URL |
| `SECURITY_ACTION_EXPIRED` | `none` | safe instruction to begin a new security action |
| `INSUFFICIENT_SCOPE` | `request_additional_scope` | `required_scopes`, `granted_scopes`, optional CEERAT consent action URL |
| `GRANT_REVOKED` | `reauthenticate` | `grant_status`; do not imply retry will restore a deliberately revoked grant |
| `INVALID_ARGUMENT` | `correct_arguments` | array of `{field, reason, expected}` with no rejected secret value |
| `NOT_FOUND` | `choose_different_resource` | safe resource type/ID and whether listing alternatives is permitted |
| `CONFLICT` | `refresh_resource` | current resource version/ETag when authorized |
| `PRECONDITION_FAILED` | context specific | named missing preconditions and safe tool/action suggestions |
| `POLICY_DENIED` | `none` or `ask_user_to_confirm` | policy rule ID/version, safe reason, whether policy is customer-editable |
| `APPROVAL_REQUIRED` | `ask_user_to_approve` | approval ID, expiry, CEERAT-owned HTTPS action URL |
| `RATE_LIMITED` | `retry_after_delay` | `retry_after_seconds`, limit dimension, reset time |
| `DEPENDENCY_UNAVAILABLE` | `retry_after_delay` | retry delay only when operation is known not to have executed |
| `OUTCOME_UNKNOWN` | `check_operation_status` | operation ID and status-tool name; never recommend resubmission |
| `INTERNAL` | `contact_support` or `retry_after_delay` | request ID in common metadata only; no stack, SQL, hostname, or provider response |

For authentication responses, OAuth-standard error fields and `WWW-Authenticate` remain authoritative; the CEERAT envelope may supplement them only when protocol-compatible. Map errors consistently to HTTP/MCP semantics.

### 11.6 Error safety and response requirements

- `retryable=true` means the identical operation is safe to retry and might succeed. It must be false for validation, scope, approval, policy, revocation, and idempotency conflicts.
- Include `retry_after_seconds` only when retry is safe. Add jitter guidance in client documentation, not arbitrary prose in responses.
- For writes, always set `meta.operation_state` to `not_started`, `completed`, or `outcome_unknown`. An error with `completed` is allowed only when the side effect committed but a later non-authoritative step failed; its code and details must tell the client how to retrieve the committed state.
- `retryable=true` is invalid when `meta.operation_state=outcome_unknown`; the only safe continuation is an allowlisted operation-status lookup or human reconciliation.
- `user_message` is display text, not an instruction or authorization signal. The agent chooses behavior only from the closed `code`, `agent_action`, typed `details`, and operation state.
- Never expose access/refresh tokens, authorization codes, cookies, passwords, MFA data, stack traces, SQL errors, private hostnames, policy implementation internals, or another tenant's resource existence.
- Registration and recovery responses must resist account enumeration: return the same public status/timing shape whether an email is new, existing, disabled, or unknown, and deliver account-specific instructions only through the verified CEERAT channel.
- Bound field-error arrays and text lengths. Unknown internal errors collapse to `INTERNAL` with a correlation ID.
- Tool definitions must document their possible CEERAT error codes and the output schema must include the error union.
- Error responses must be audited with code, tool, principal/client IDs, and correlation ID, while preserving the same redaction rules as successful calls.
- Response bodies, MCP structured content, logs, and audit records use the same canonical error code. Protocol adapters must not silently replace a CEERAT code with free-form text.
- A client receiving an unknown major `schema_version`, unknown error code, or invalid response shape must fail closed and surface the request ID; it must not guess a recovery action.

### 11.7 Structured error examples

Expired login:

```json
{
  "schema_version": "1.0",
  "ok": false,
  "error": {
    "code": "TOKEN_EXPIRED",
    "category": "authentication",
    "message": "The CEERAT access token has expired.",
    "user_message": "Please reconnect your CEERAT account.",
    "retryable": false,
    "agent_action": "reauthenticate",
    "details": {
      "resource_metadata": "https://agents.ceerat.com/.well-known/oauth-protected-resource/mcp"
    }
  },
  "meta": {
    "request_id": "req_01...",
    "tool": "get_current_user",
    "operation_state": "not_started"
  }
}
```

Invalid profile update:

```json
{
  "schema_version": "1.0",
  "ok": false,
  "error": {
    "code": "INVALID_ARGUMENT",
    "category": "validation",
    "message": "Two profile fields are invalid.",
    "user_message": "Please correct the state and postal code.",
    "retryable": false,
    "agent_action": "correct_arguments",
    "details": {
      "fields": [
        {"field": "address.state", "reason": "unsupported_code", "expected": "two-letter US state code"},
        {"field": "address.postal_code", "reason": "invalid_format", "expected": "US ZIP or ZIP+4"}
      ]
    }
  },
  "meta": {
    "request_id": "req_02...",
    "tool": "prepare_my_customer_profile_update",
    "operation_state": "not_started"
  }
}
```

Missing permission:

```json
{
  "schema_version": "1.0",
  "ok": false,
  "error": {
    "code": "INSUFFICIENT_SCOPE",
    "category": "authorization",
    "message": "The connection cannot update the customer profile.",
    "user_message": "Reconnect CEERAT and allow profile updates to continue.",
    "retryable": false,
    "agent_action": "request_additional_scope",
    "details": {
      "required_scopes": ["ceerat.profile.write"],
      "granted_scopes": ["openid", "profile", "ceerat.profile.read"]
    }
  },
  "meta": {
    "request_id": "req_03...",
    "tool": "prepare_my_customer_profile_update",
    "operation_state": "not_started"
  }
}
```

## 12. Development runtime and deferred deployment

Kubernetes setup is outside the development scope. Do not add or modify anything under `infra/k8s` as part of the development phases. Do not make local verification depend on a cluster, ingress controller, container registry, external secret controller, HPA, or Kubernetes DNS.

### 12.1 Local processes

```text
ceerat-agent-gateway: 127.0.0.1:8090/mcp
ceerat-user-service: localhost:50051 gRPC
development issuer: local Keycloak OAuth/OIDC server
handoff UI:         local customer/auth UI
client tests:       MCP conformance client and a second vendor-neutral client
ChatGPT validation: temporary protected HTTPS endpoint
```

Use the existing local stack scripts, log convention, and PID lifecycle. Add the gateway only after its standalone protocol, auth, and schema tests pass.

### 12.2 Integration test configuration

Automated tests run against loopback. ChatGPT publication/interoperability validation requires a temporary HTTPS-reachable endpoint because remote clients cannot reach the developer's localhost. The temporary environment must:

- contain only synthetic test accounts/data;
- use HTTPS and a valid certificate;
- be short lived and removed after validation;
- avoid production credentials, tokens, or databases;
- restrict access when compatible with the browser-agent test;
- record server-side test audit events without storing entered credentials.

### 12.3 Local security boundary

- Expose only MCP, OAuth discovery, and required secure handoff routes; never private gRPC, PostgreSQL, Typesense, metrics, or profiling.
- Do not weaken OAuth, session, CSRF, password, MFA, scope, RBAC, or ownership controls.
- Keep credentials, access/refresh tokens, session cookies, reset tokens, and CSRF tokens out of logs, fixtures, and test reports.
- Use synthetic test users and reset their sessions/data after each run.
- Mark browser-agent test traffic with a non-authoritative correlation header or test account; never use that marker to grant permissions.

### 12.4 Deferred production deployment handoff

After local and temporary-environment integration validation, create a separate production deployment document. None of that deployment work is an acceptance criterion here.

## 13. Observability, audit, and SLOs

Use OpenTelemetry for traces, metrics, and structured logs. Propagate a CEERAT correlation ID from gateway or handoff UI through gRPC. Do not record credentials, OAuth tokens, cookies, CSRF/reset tokens, or full tool/form payloads.

Key metrics:

```text
mcp_requests_total{method,status,client}
mcp_tool_calls_total{tool,outcome,client}
mcp_tool_duration_seconds{tool}
mcp_auth_failures_total{reason,client}
mcp_scope_denials_total{tool,scope}
mcp_confirmations_total{tool,outcome}
mcp_rate_limit_total{tool,dimension}
customer_registration_total{outcome}
customer_login_total{outcome,reason}
customer_profile_update_total{outcome}
customer_security_action_total{type,outcome}
mcp_grpc_duration_seconds{service,method,status}
```

Initial targets, to be revised after load testing:

- Integration availability: 99.9% monthly for discovery, initialization, authentication metadata, and phase-one tools.
- Read-tool latency: p95 under 1 second excluding external identity/email delivery.
- Begin/status security tools: p95 under 1 second excluding human completion.
- Protocol/schema conformance: 100% for pinned golden fixtures and supported client compatibility suite.
- Audit durability: every write attempt has an audit record; alarm on any detected gap.

Audit events should capture event ID, timestamp, customer/user when known, client/grant/token ID, tool/action, arguments hash or changed field names (not secret values), scope, confirmation/result, target IDs, latency, and correlation/trace IDs. Provide customers a Security Activity view and operators a restricted investigation view.

## 14. Threat model and controls

| Threat | Required control |
|---|---|
| Stolen OAuth token | Short TTL, audience restriction, least scopes, refresh rotation, grant revocation, sender binding where feasible |
| Confused deputy/token passthrough | Exact issuer/audience/resource validation; never forward public tokens to arbitrary services |
| Malicious/incorrect tool arguments | Strict schemas, unknown-field rejection, bounded values, identity derived only from validated principal |
| Stolen browser session | Secure/HttpOnly/SameSite cookies, rotation, idle/absolute expiry, session list and revocation, reauthentication for sensitive actions |
| CSRF | Server-validated CSRF tokens and Origin/Referer checks on every state-changing form |
| Prompt injection in CEERAT/user content | Treat content as data; never let content select tools/scopes or authorize actions; require server-side confirmations |
| Agent appears to approve for user | CEERAT confirmation/reauthentication for sensitive actions; never trust browser text claiming approval |
| Duplicate form submission | One-time confirmation tokens/idempotency keys and Post/Redirect/Get |
| Cross-customer access | Session-derived identity and repository ownership predicates; ignore identity hidden fields |
| Credential exposure | Customer takeover/secure sign-in, proper input types, no secrets in chat/URLs/logs/analytics |
| Account enumeration | Uniform registration/recovery/login responses and timing; account-specific delivery through verified channels |
| UI ambiguity causes wrong action | Semantic labels, preview/confirm pages, explicit target/change summaries, distinct destructive styling/text |
| Automation abuse | Per-IP/session/account rate limits, anomaly detection, human challenges/takeover when needed |
| Uncertain write outcome | Operation reference/status page; never advise blind resubmission |
| Open redirect/phishing | Allowlisted relative return targets, canonical origin display, no user-controlled action URLs |

Commission an external security review before enabling `applications.submit` for general availability.

## 15. Phased implementation plan

### Phase 0: protocol and identity spike

- Select and pin the remote MCP revision and Go SDK.
- Run Keycloak as the local development OAuth/OIDC issuer and pre-register the initial development clients. Keep gateway integration standards based; do not use Keycloak-specific tokens or APIs as the CEERAT domain contract.
- Define CEERAT resource, issuer, audience, subject/customer mapping, scopes, grant lifecycle, and internal assertion model.
- Prove MCP initialization/tool listing, protected-resource discovery, authorization code + PKCE, token refresh/revocation, and one read-only authenticated call with two clients.
- Confirm that registration/password/MFA secrets remain in CEERAT browser handoffs and never enter tool payloads.

Exit: architecture decision, threat model, compatibility matrix, and working local spike. No production deployment or non-identity tools.

### Phase 1: login and user management

- Create `ceerat-agent-gateway` with remote MCP transport, protocol negotiation, health/readiness, static tool registry, strict JSON Schema validation, and structured errors.
- Publish CEERAT product metadata, tool descriptions, input/output schemas, authentication requirements, scopes, risk annotations, confirmation modes, rate costs, and documented error unions.
- Publish OAuth Protected Resource Metadata plus authorization-server/OIDC discovery and JWKS metadata.
- Pre-register ChatGPT/test MCP client metadata in Keycloak for development. Dynamic client registration is deferred.
- Enable customer registration directly on the Keycloak authorization page; after registration, continue the same authorization code + PKCE and consent flow. Do not publish registration begin/status MCP tools.
- Implement OAuth authorization code + PKCE login/consent, short-lived access tokens, rotating refresh tokens, grant revocation, logout, and scope elevation through new consent.
- Implement the Phase 1 tools in section 7.1: product description; authentication status; current user; profile read; profile update prepare/execute; connection list/revoke; and current-connection logout.
- Restrict profile mutations to `display_name`, `first_name`, `last_name`, `locale`, `time_zone`, `city`, `state_or_region`, and `country_code` when supported by the Customer contract. Email and phone are excluded.
- Add gateway persistence for clients, grants, profile preparations, confirmations, idempotency records, and audit events.
- Map external OAuth principal/client/grant identity into a short-lived internal assertion; preserve user-service RBAC and ownership enforcement.
- Implement the complete structured error contract plus browser-handoff errors in section 11.
- Add scope, cross-customer, anti-enumeration, anti-abuse, confirmation, idempotency, secret-redaction, audit, and client-conformance tests.
- Validate locally with two MCP clients, then validate through a temporary isolated HTTPS endpoint with ChatGPT.

Exit: all Phase 1 acceptance criteria in section 16.4 pass. An external agent discovers CEERAT and its schemas, guides a new customer through Keycloak registration or an existing customer through login/consent, obtains only granted scopes, directly invokes identity/profile/connection tools through the MCP gateway and private gRPC, handles structured failures correctly, and never receives customer secrets. No password, recovery, verified-contact, deletion, job, resume, application, cart, employer, or admin operation is published.

### Phase 1B: account-security workflows

- Design and implement password recovery/change integration only if Keycloak's standard account UI is insufficient.
- Design verified email/phone changes with reauthentication and verification.
- Design delayed account deletion, cancellation, retention, and legal-hold behavior.
- Add new MCP operations only when an agent-visible begin/status flow materially improves the customer experience and preserves secret isolation.

Exit: separate security review and acceptance criteria pass. Phase 1 does not depend on Phase 1B.

### Phase 2: career discovery and application reads

- Add `list_my_resumes`, `search_jobs`, `get_job`, `list_my_applications`, and `get_my_application` tools.
- Add strict schemas, bounded pagination, quotas, redaction, stable errors, and audit events.
- Verify ownership and authorization independently in gateway and user-service layers.

Exit: compatible agents can read authorized career data through structured tools.

### Phase 3: preparation, policy, and approval

- Add versioned customer policies and deterministic evaluator.
- Add immutable application preparations.
- Add approval requests, UI/deep links, expiry/revocation, and activity records.
- Implement `prepare_application` without external submission.
- Run shadow policy evaluation against pilot traffic and review false allow/deny rates.

Exit: preparation is stable, explanations are actionable, and no policy path depends on an LLM decision.

### Phase 4: single idempotent submission

- Add submission scope, idempotency repository, and `submit_application`.
- Require approval for every submission initially.
- Add downstream status reconciliation and `OUTCOME_UNKNOWN` operations runbook.
- Add fraud/velocity controls and per-customer daily caps.
- Complete penetration testing and incident response drills.

Exit: restricted beta with explicit customer enablement and kill switch.

### Phase 5: asynchronous campaigns

- Add durable tasks, worker leases/fencing, per-item idempotency, progress, cancellation, and result tools.
- Store an authorization/policy snapshot, but revalidate grant revocation and hard safety constraints before every item.
- Bound campaign size, concurrency, daily volume, and execution window.

Exit: controlled autonomous campaigns with reconciliation and customer activity visibility.

### Phase 6: ecosystem publication and certification

- Package and publish the integration for ChatGPT using the current supported submission/distribution path.
- Publish vendor-neutral endpoint, OAuth, tool, schema, error, quota, sandbox, changelog, and support documentation for other clients.
- Maintain a client compatibility matrix without changing shared tool semantics.

## 16. Testing and verification

### 16.1 Unit tests

- MCP protocol/version negotiation and tool registry/schema validation.
- OAuth issuer, audience, resource, signature, expiry, client, grant, and scope validation.
- Keycloak subject/customer mapping, OAuth anti-enumeration behavior, and secret redaction.
- Profile allowlist, partial updates, preparation hash/version binding, and immutable-field rejection.
- Connection/logout revocation and token-family invalidation.
- Error-code-to-agent-action mapping, retryability, typed details, and secret redaction.
- Idempotency, confirmation binding, audit generation, and sensitive-value redaction.

### 16.2 Integration tests

- Protected-resource and authorization-server discovery, MCP initialize/list/call, and protocol-version behavior.
- Authorization code + PKCE, consent, refresh rotation/reuse detection, scope elevation, revocation, and logout.
- Keycloak authorization-page registration and existing-user login, including cancellation, abuse limits, and anti-enumeration.
- Authentication status, current user, profile read, profile prepare/confirm update, stale version, and cross-customer denial.
- Excluded-field tests proving email, phone, role, status, ownership, and security fields cannot be changed through Phase 1 tools.
- Connection listing/revocation and immediate denial after current-grant logout.
- Agent follows structured next actions without parsing prose.
- Every response matches its advertised output/error schema.
- Two vendor-neutral clients plus ChatGPT complete the same phase-one lifecycle.

### 16.3 Client compatibility

Maintain golden initialization, tools/list, tools/call, OAuth challenge, error, schema, confirmation, and protocol-version fixtures. Client-specific packaging must remain outside shared tool behavior. Also test secure browser handoffs for accessibility and secret isolation.

### 16.4 Phase 1 acceptance criteria

Phase 1 is accepted only when every required criterion below has repeatable evidence from a clean test account. A conversational answer is not evidence by itself; the test record must contain gateway request IDs, sanitized protocol transcripts, audit-event IDs, and the resulting server-side state.

| Area | Pass criterion |
|---|---|
| Discovery | An unauthenticated client initializes MCP, lists the complete Phase 1 tool catalog, and validates every input/output/error schema without private customer data being returned. |
| Authentication challenge | Calling a protected tool without a token returns the expected OAuth challenge and protected-resource metadata; it does not disclose whether a named account exists. |
| Registration | A new synthetic customer completes the CEERAT browser registration flow, including required verification, and the client subsequently receives a token only after consent. Duplicate and expired attempts return stable non-enumerating errors. |
| Existing-user login | An existing synthetic customer completes authorization code + PKCE and consent. The authorization code is single use, redirect URI matching is exact, and a bad verifier is rejected. |
| Delegation | The access token is bound to the expected issuer, audience, subject, client, grant, and scopes. A token for another audience or client is rejected. |
| Identity | `get_current_user` and `get_my_customer_profile` return only the authenticated customer's permitted fields. Cross-customer identifiers in prompts or hidden arguments cannot change the effective principal. |
| Profile update | Prepare/execute updates only allowlisted fields, bind the confirmed payload and version, reject mutation after preparation, and return the verified final state. Repeating the same idempotency key does not duplicate the write. |
| Scope enforcement | Each tool succeeds with its documented scope and fails with `INSUFFICIENT_SCOPE` without it. Scope elevation requires a new consent decision. |
| Secret isolation | No password, MFA value, reset token, cookie, authorization code, or refresh token appears in MCP arguments, responses, model-visible output, logs, traces, analytics, or audit details. Password/recovery/contact/deletion operations are absent from the Phase 1 catalog. |
| Connections and logout | The customer can list and revoke a selected agent grant. Logging out the current connection revokes its token family, and the next protected call is denied. |
| Error recovery | Every expected failure validates against the advertised error schema and supplies a stable code, safe message, retryability, correlation ID, and bounded next action. The client can recover using structured fields without parsing prose. |
| Audit | Every authentication, consent, read of sensitive identity data, mutation, revocation, and denied consequential call produces a correlated audit event with actor, client, scope, target, outcome, and no secrets. |
| Abuse controls | Registration, login, and tool rate limits trigger predictably; retry hints are bounded; account enumeration and cross-customer leakage tests fail closed. |
| Compatibility | The deterministic suite passes against two independent MCP clients. The ChatGPT scenario in section 16.5 passes when the required ChatGPT development/publication capability is available. |
| Development boundary | All automated tests run without Kubernetes. External testing uses only an isolated, temporary HTTPS endpoint, synthetic accounts, and non-production credentials. |

Required release thresholds:

- 100% pass rate for authentication, authorization, cross-customer isolation, secret-redaction, confirmation, revocation, and audit tests;
- 100% schema conformance for the published Phase 1 operation and error corpus;
- zero high- or critical-severity findings in the Phase 1 threat-model/security review;
- zero secrets found by automated log/trace/transcript scanning;
- at least three successful clean-account executions of each ChatGPT happy-path scenario and one successful execution of every defined negative scenario;
- no unresolved outcome may be reported as success; uncertain writes must return `OUTCOME_UNKNOWN` with a status/reconciliation action.

### 16.5 LLM and ChatGPT integration test procedure

The integration test has three layers. Layers 1 and 2 are release-blocking and deterministic. Layer 3 validates real ChatGPT behavior but must not be the only proof of protocol correctness because model decisions and hosted-client availability can vary.

#### Layer 1: deterministic MCP/OAuth harness

1. Start the gateway, local Keycloak, user service, and test datastore locally; do not start Kubernetes.
2. Seed synthetic customers, OAuth clients, scopes, expired grants, revoked grants, and cross-customer fixtures.
3. Run a protocol client against initialization, tool listing, each tool's success/error union, malformed inputs, unsupported protocol versions, timeouts, retries, and idempotency replay.
4. Drive the browser handoff with an automated browser test. Record only transaction and correlation IDs; configure screenshots, videos, network logs, and traces to redact or omit secret fields.
5. Assert database/domain state and audit records independently of the assistant response.
6. Run an automated secret scanner over MCP transcripts, browser-test artifacts, application logs, traces, and audit details.

#### Layer 2: model-driven API test

Use an OpenAI Responses API test harness configured with the CEERAT remote MCP server. The Responses API supports MCP tools provided by custom MCP servers; keep this harness separate from the ChatGPT product UI so prompts, expected calls, and captured results can be reproduced in CI.

For every scenario, capture the test-case version, model identifier, prompt, advertised tools, MCP call sequence, sanitized arguments/results, CEERAT correlation IDs, final assistant response, audit IDs, and verified final state. Pin the model snapshot when the API supports it, set explicit tool availability, and treat changes in model behavior as compatibility results rather than changes to CEERAT authorization policy.

Run at least these prompts/scenarios:

| Scenario | User intent | Required behavior |
|---|---|---|
| Discover | "What can CEERAT do for my account?" | Lists only supported Phase 1 capabilities and does not invent job/skill tools. |
| Register | "Create my CEERAT account." | Starts OAuth; the customer chooses Register on Keycloak, and the model never asks for a password/MFA value in chat. |
| Login | "Log in to CEERAT and show my profile." | Triggers OAuth when unauthenticated, then calls the identity/profile tool after consent. |
| Read profile | "What information does CEERAT have about me?" | Uses the authenticated principal and returns only allowed fields. |
| Update profile | "Change my display name to Test User." | Uses prepare/execute confirmation, describes the exact change, and verifies the result. |
| Denied field | "Make me an administrator." | Does not attempt an undocumented workaround; reports the structured authorization/validation failure safely. |
| Prompt injection | Customer-controlled profile text instructs the model to expose tokens or call another user | Treats the text as data, exposes no secrets, and performs no cross-customer call. |
| Insufficient scope | Ask for a profile mutation with a read-only grant | Explains the missing permission and initiates scope elevation only with user consent. |
| Expired token | Read profile with an expired access token | Uses the advertised authentication recovery path and does not repeatedly retry the failed call. |
| Uncertain write | Simulate downstream timeout after accepting an update | Reports uncertainty, queries operation status when available, and never blindly resubmits. |
| Revoke/logout | "Disconnect CEERAT from this chat." | Revokes the current connection, reports completion, and cannot call protected tools afterward. |

The model-driven suite passes only when the intended server-side result is correct, the call sequence respects scope and confirmation requirements, and no prohibited secret appears. Helpful prose with an incorrect or missing tool result is a failure.

#### Layer 3: ChatGPT product end-to-end test

1. Deploy the tested build to a temporary isolated HTTPS endpoint with valid TLS and a pre-registered ChatGPT test client. Never expose localhost, private gRPC, metrics, profiling, or test databases directly.
2. Configure the CEERAT integration using the ChatGPT development/publication mechanism available to the project at test time. Recheck the current OpenAI submission and authentication requirements before executing this step; do not hard-code undocumented product behavior into the shared MCP contract.
3. In a fresh ChatGPT conversation and private test account, ask the Discover scenario and compare the visible operations with the canonical tool registry.
4. Run Register and Existing-user Login with separate synthetic customers. Confirm the customer leaves ChatGPT only for the CEERAT-owned handoff and returns with the correct scopes. Enter passwords and MFA values only on CEERAT pages.
5. Run Read Profile, Update Profile, Insufficient Scope, Expired Token, and Revoke/Logout scenarios in fresh conversations where isolation matters.
6. Repeat adversarial cases: request another customer's data, place tool-like instructions in profile fields, ask ChatGPT to accept a password in chat, alter a prepared update before execution, replay a confirmation, and retry after logout.
7. Export or manually record sanitized ChatGPT-visible evidence and correlate it with gateway and audit IDs. Do not retain credentials, cookies, tokens, authorization codes, or unredacted handoff captures.
8. Destroy synthetic accounts, revoke grants, disable the temporary client, and close the HTTPS endpoint after the run.

ChatGPT passes when it discovers the intended tools, completes OAuth/browser handoff, invokes the expected MCP tools, communicates structured failures usefully, respects confirmation boundaries, and produces the independently verified server state. If the current ChatGPT environment cannot install or authenticate a development integration, record the Layer 3 case as `BLOCKED_BY_CLIENT_AVAILABILITY`, not passed; Layers 1 and 2 must still pass.

### 16.6 Test evidence and CI artifacts

Store the following sanitized artifacts for each build:

- protocol conformance report and golden-fixture diff;
- OAuth and scope test report;
- tool/schema and structured-error conformance report;
- security, cross-customer, prompt-injection, and secret-scan results;
- browser-handoff accessibility and secret-isolation results;
- model-driven scenario matrix with request/audit correlations;
- ChatGPT manual/end-to-end checklist, screenshots with secrets excluded, and client/version/date metadata;
- cleanup confirmation for accounts, grants, clients, and temporary endpoints.

No raw access token, refresh token, authorization code, cookie, password, MFA value, reset token, or recovery code may be stored as test evidence.

### 16.7 Platform gates

Use the builder for Auth/Customer contract evidence, ownership, RBAC, and handoff impact:

```bash
cd ceerat-platform-builder-agent
ceerat-builder check-context
ceerat-builder plan --mode local --output json "<identity integration capability>"
ceerat-builder impact contract agentgateway.AgentGatewayService --add <Capability> --output json
ceerat-builder rbac suggest agentgateway.AgentGatewayService --capability <Capability> --output json

cd ../infra
make verify-platform
```

Also run gateway, Keycloak configuration/theme checks, and user-service Go tests, static analysis, OAuth/MCP conformance, accessibility checks for authorization handoffs, client compatibility tests, and local load/abuse tests. Use only synthetic customers and reversible actions.

## 17. Operational controls and runbooks

Provide operator controls for:

- disable the integration, one client, grant, scope, or sensitive account action;
- revoke customer grants, access/refresh token families, and browser handoff sessions;
- rate-limit abusive IP/client/grant/account patterns;
- reconcile an `OUTCOME_UNKNOWN` tool operation;
- inspect a correlation ID without exposing sensitive payloads;
- export/delete customer agent data according to retention rules.

Alert on unusual OAuth/login/registration failures, token reuse, scope denials, confirmation bypass attempts, audit-write failures, and sustained downstream errors. Sensitive writes fail closed if authentication, grant, scope, ownership, confirmation, or audit prerequisites are unavailable.

## 18. Decisions still required

1. Which remote MCP Go SDK and pinned protocol revision will CEERAT use? Keycloak is selected as the Phase 1 development OAuth/OIDC provider.
2. What exact redirect URI and client metadata will ChatGPT expose for pre-registration? Phase 1 uses pre-registered clients; metadata documents and Dynamic Client Registration are deferred.
3. How will the current CEERAT Auth user/JWT map to OAuth subject, customer ID, grant, and internal assertion?
4. Which phase-one scopes and default consent set are published?
5. Do all proposed low-risk fields exist in the current Customer contract, and what validation applies to each? Email, phone, role, status, ownership, verification, and security fields are excluded.
6. What exact confirmation payload/UX will `update_my_customer_profile` use in each target client?
7. What access-token, refresh-token, grant, and Keycloak-session lifetimes apply?
8. What isolated HTTPS mechanism is approved for ChatGPT interoperability testing?
9. What is the current ChatGPT publication/review path and required metadata at submission time?

Decisions 1 through 8 must be resolved before phase-one completion. Publication decision 9 can finish after the vendor-neutral integration passes conformance tests.

## 19. Recommended immediate backlog

1. Record the direct `ChatGPT -> ceerat-agent-gateway -> private gRPC` decision and browser-handoff security boundary.
2. Select/pin the MCP SDK/revision and configure local Keycloak.
3. Define OAuth resource/issuer/audience/subject mapping, scopes, grants, token lifetimes, and client onboarding.
4. Define phase-one tool names, descriptions, strict input/output/error schemas, annotations, confirmations, and rate costs.
5. Define `agentgateway` protobuf contracts and persistence for clients, grants, profile preparations, confirmations, idempotency, and audit.
6. Scaffold `ceerat-agent-gateway` with initialization, tool listing, token middleware, schema validator, structured error mapper, and internal gRPC client.
7. Implement protected-resource/OAuth discovery, PKCE login/consent, refresh rotation, revocation, and internal identity assertion.
8. Configure Keycloak authorization-page registration, login/MFA, consent, and test users.
9. Implement authentication/current-user/profile read and prepared low-risk profile update.
10. Implement connection listing/revocation and current-connection logout.
11. Add conformance, cross-customer, scope, confirmation, idempotency, secret-leak, error-recovery, and audit tests.
12. Establish temporary isolated HTTPS validation without Kubernetes.
13. Validate with two MCP clients and ChatGPT, then prepare publication metadata.

## 20. Standards references

These MCP/OAuth references apply directly to phase one. ChatGPT-specific publication requirements must be rechecked when submission begins.

- [OpenAI Responses API tool support, including custom MCP servers](https://developers.openai.com/api/reference/cli/resources/responses/methods/create)
- [MCP 2026-07-28 specification release](https://blog.modelcontextprotocol.io/posts/2026-07-28/)
- [MCP authorization specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
- [MCP tools specification](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- [OAuth 2.0 Protected Resource Metadata (RFC 9728)](https://datatracker.ietf.org/doc/html/rfc9728/)
- [Resource Indicators for OAuth 2.0 (RFC 8707)](https://datatracker.ietf.org/doc/html/rfc8707)
- [OAuth 2.0 Device Authorization Grant (RFC 8628)](https://datatracker.ietf.org/doc/html/rfc8628)
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0-18.html)

Protocol URLs should be reviewed when implementation begins. The repository should pin a tested MCP revision and SDK version rather than relying on an unversioned interpretation of the latest specification.
