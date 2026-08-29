# CEERAT Public MCP Agent Gateway

Status: Proposed technical design  
Date: 2026-08-29  
Scope: Public, customer-authorized access to CEERAT capabilities through remote Model Context Protocol (MCP)

## 1. Executive summary

CEERAT should add a dedicated public `ceerat-agent-gateway` service at an endpoint such as:

```text
https://agents.ceerat.com/mcp
```

The gateway is an OAuth-protected MCP resource server. It authenticates third-party agent clients, resolves the CEERAT customer who granted access, verifies scopes, enforces stored customer policy, obtains required approvals, applies rate and abuse limits, provides idempotent execution, writes an immutable audit record, and only then invokes CEERAT's private gRPC services.

The gateway should be a new boundary rather than a public route added directly to `ceerat-agent-service`. The existing agent service is an internal LLM/chat orchestrator. It accepts CEERAT JWTs, calls OpenAI, and exposes a useful inventory of customer tools backed by `ceerat-user-service`. It does not currently provide OAuth client onboarding, delegated consent, granular scopes, policy enforcement, approvals, idempotency, asynchronous task management, or public-resource security. Those concerns require a different lifecycle and threat model.

The recommended first production slice is deliberately narrow and identity focused:

1. Implement OAuth login, consent, token lifecycle, logout/revocation, and agent-connection management.
2. Publish only safe self-service user tools: `get_current_user`, `get_my_customer_profile`, and `update_my_customer_profile`.
3. Add job discovery and application-read tools in the second phase.
4. Add preparation, approval-gated submission, and asynchronous campaigns only after the identity foundation is proven safe.

The language model is never the authorization or policy enforcement point. It proposes a tool call; deterministic CEERAT services decide whether that call is allowed and execute it.

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

- Let a customer connect a compatible external assistant to their own CEERAT account.
- Implement remote MCP over HTTPS using the current protocol revision selected at build time.
- Issue least-privilege, customer-delegated access tokens with an audience restricted to the CEERAT MCP resource.
- Expose a stable, well-described tool catalog independent of internal gRPC organization.
- Enforce scopes, ownership, customer policy, approval rules, rate limits, and idempotency before side effects.
- Support safe prepare/execute/verify flows.
- Make every attempted consequential action explainable and auditable.
- Scale gateway instances horizontally without sticky sessions.
- Preserve the private status of internal gRPC services and databases.
- Provide a migration path to long-running campaigns and multiple agent ecosystems.

### 3.2 Non-goals for the first release

- Replacing `ceerat-agent-service` or the existing CEERAT chat UI.
- Exposing internal gRPC reflection or arbitrary RPC proxying to external clients.
- Allowing agents to supply or override authorization decisions.
- Supporting bulk autonomous applications before single-item controls are proven.
- Making PostgreSQL or Typesense directly accessible to agents.
- Implementing a general-purpose workflow engine in phase one.
- Depending on one vendor's proprietary connector behavior.
- Creating or changing Kubernetes manifests, ingress resources, network policies, deployment images, autoscaling, or cluster secrets during development.

### 3.3 Development deployment boundary

All implementation and verification phases in this document target the local CEERAT development stack. The gateway runs as a local process alongside `ceerat-user-service` and uses local environment configuration, loopback ports, and a development OAuth issuer. Kubernetes is explicitly deferred until the application behavior, contracts, authentication, user-management tools, and error protocol are validated.

```text
Local MCP client
      |
      v
http://localhost:8090/mcp
      |
      v
ceerat-agent-gateway local process
      |
      v
localhost:50051 ceerat-user-service
```

Production hosting decisions must not leak into domain contracts or tool behavior. The gateway remains stateless at the request layer so a later container/Kubernetes deployment can be added without redesigning its public API.

## 4. Target architecture

```text
External assistant / MCP client
          |
          | HTTPS + OAuth access token
          v
Public DNS, TLS, WAF / edge rate limiting
          |
          v
Traefik or managed API gateway
          |
          v
+---------------------------------------------------+
| ceerat-agent-gateway                              |
|                                                   |
| MCP transport and protocol negotiation            |
| token validation and principal resolution         |
| tool registry and schema validation               |
| scope + ownership authorization                   |
| policy evaluation                                 |
| approval orchestration                            |
| rate/abuse limits                                 |
| idempotency                                       |
| audit and metrics                                 |
| internal gRPC adapters                            |
+----------------------+----------------------------+
                       |
                       | private gRPC + propagated identity
                       v
              ceerat-user-service
               |               |
               v               v
           PostgreSQL       Typesense

Authorization flow:

External assistant -> CEERAT authorization server
                   -> login and consent UI
                   -> audience-restricted access token

Async flow (later phase):

gateway -> durable task table/queue -> ceerat-agent-worker -> private gRPC
```

### 4.1 Service boundaries

| Component | Responsibility | Must not do |
|---|---|---|
| Authorization server | Login, client trust, consent, token issuance/revocation, discovery | Execute MCP tools |
| Agent gateway | MCP, token validation, scopes, policy, approvals, idempotency, auditing, gRPC adaptation | Call an LLM to decide authorization |
| User service | Domain rules, authenticated ownership, career/application persistence | Trust gateway arguments as identity |
| Agent service | CEERAT-owned conversational orchestration | Serve as the public security gateway |
| Worker | Resume durable, bounded asynchronous tasks | Bypass gateway-created authorization snapshot |
| Customer UI | Consent, connections, policies, approvals, activity | Hold client secrets in browser storage |

The authorization server can initially be a standards-compliant managed or self-hosted identity product. Building token issuance from scratch is not recommended. CEERAT still owns consent, grants, scopes, policies, approval records, and audit records even when an external identity provider performs authentication.

## 5. Protocol and OAuth profile

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

### 5.4 Scope model

Start with explicit, capability-oriented scopes:

```text
openid
profile
ceerat.profile.read
ceerat.profile.write
ceerat.connections.read
ceerat.connections.revoke
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
| Human using a terminal, TV, or client without a usable browser callback | OAuth Device Authorization Grant, if supported | Customer-delegated token after separate-browser confirmation |
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

### 5.7 Device login for headless clients

If terminal or headless clients are in scope, implement the OAuth Device Authorization Grant through the selected authorization server:

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

# CEERAT-owned browser experience
GET  /login
POST /login                                         # normal CEERAT auth backend
GET  /oauth2/consent
POST /oauth2/consent
GET  /settings/agent-connections
POST /settings/agent-connections/{grant_id}/revoke
```

Do not implement these routes inside the LLM-facing MCP tool registry. OAuth endpoints belong to the authorization server, and login/consent pages belong to a CEERAT-controlled browser origin. Cookies used there must be `Secure`, `HttpOnly`, and appropriately `SameSite`; authorization requests require CSRF/state protection and exact redirect-URI matching.

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

## 6. Request processing pipeline

Every `tools/call` follows the same ordered pipeline:

```text
1. Parse request and negotiate MCP protocol version
2. Authenticate token and resolve client + user + customer grant
3. Resolve registered tool definition
4. Validate input against pinned JSON Schema
5. Check scope and client restrictions
6. Check user/customer ownership and account status
7. Load customer policy and evaluate deterministic constraints
8. Determine approval requirement and validate approval token/record
9. Apply per-client, per-user, per-tool, and global rate limits
10. Reserve or replay idempotency record
11. Execute private gRPC call or enqueue durable task
12. Persist result and audit outcome
13. Return structured MCP content with stable error metadata
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

## 7. Tool catalog design

Public tool names are a stable product API. They should not mirror internal RPC names blindly. Each tool needs a precise description, JSON input and output schemas, required scope, risk class, timeout, rate-cost, idempotency mode, approval mode, and downstream adapter.

### 7.1 Phase-one identity and user-management catalog

| Tool | Scope | Effect | Approval | Existing backing capability |
|---|---|---:|---:|---|
| `get_current_user` | `profile` | Read | Never | Validated session/user |
| `get_my_customer_profile` | `ceerat.profile.read` | Read | Never | `CustomerService.GetMyCustomerProfile` |
| `update_my_customer_profile` | `ceerat.profile.write` | CEERAT account write | Confirm changed fields | `CustomerService.UpdateMyCustomerProfile` |
| `list_my_agent_connections` | `ceerat.connections.read` | Read | Never | New grant query in `AgentGatewayService` |
| `revoke_my_agent_connection` | `ceerat.connections.revoke` | Security write | Always | New grant revocation in `AgentGatewayService` |

Login, logout, consent, token refresh, and initial grant revocation are OAuth/browser operations rather than MCP tools. The two connection tools let an already authorized agent explain active connections or help a customer revoke a named connection, but revocation must still require a CEERAT-controlled confirmation. Revoking the grant used by the current call succeeds and then invalidates subsequent calls.

Phase one does not expose password changes, email/phone ownership verification, MFA enrollment, account deletion, role/status changes, user creation, resume operations, job operations, applications, carts, employer functions, or admin tools. Passwords and MFA must remain on CEERAT-owned browser surfaces. Sensitive profile changes such as a primary email or verified phone number must use a dedicated verification workflow before they can be considered complete.

### 7.2 Later tool catalog

| Tool group | Earliest phase | Candidate tools |
|---|---:|---|
| Job and application reads | 2 | `list_my_resumes`, `search_jobs`, `get_job`, `list_my_applications`, `get_my_application` |
| Preparation and policy | 3 | `prepare_application` |
| Consequential execution | 4 | `submit_application` |
| Durable campaigns | 5 | `get_task`, `cancel_task`, campaign tools |

### 7.3 Prepare/execute contract

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

### 7.4 Tool metadata

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
  rpc ResolveGrant(ResolveGrantRequest) returns (ResolveGrantResponse);
  rpc ListMyAgentConnections(ListMyAgentConnectionsRequest) returns (AgentConnectionPage);
  rpc RevokeMyAgentConnection(RevokeMyAgentConnectionRequest) returns (AgentConnectionResponse);
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

## 11. Error contract

The earlier minimal error shape is not sufficient for a reliable AI client. It identifies the failure but does not consistently tell the agent which action is safe next, which input fields are invalid, which scopes are missing, whether user interaction is required, or how long to wait. Errors must be actionable, bounded, safe to show to the user, and deterministic enough that an agent does not have to infer recovery from prose.

### 11.1 Two error layers

Keep protocol/authentication failures separate from tool-execution failures:

- Before an authenticated MCP request exists, use the correct HTTP status and `WWW-Authenticate` challenge. For example, a missing/expired token returns `401`, protected-resource metadata, and only safe OAuth error information.
- After a valid MCP session invokes a known tool, return a normal MCP tool result marked as an error, with the structured CEERAT error envelope below. This lets the agent inspect and act on the failure without treating every business denial as a broken MCP transport.
- Invalid JSON-RPC/MCP envelopes, unsupported protocol versions, unknown methods, and server-level faults use MCP/JSON-RPC protocol errors rather than CEERAT business codes.

Do not return login or consent URLs from arbitrary downstream errors. OAuth discovery drives authentication. When user interaction is required after authentication, return only a CEERAT-owned HTTPS action URL or opaque action ID produced by the gateway.

### 11.2 Agent-actionable error envelope

Return stable machine-readable error codes in MCP tool results without leaking internals:

```json
{
  "ok": false,
  "error": {
    "code": "APPROVAL_REQUIRED",
    "category": "user_action_required",
    "message": "Customer approval is required before submission.",
    "user_message": "Review and approve this application in CEERAT before I submit it.",
    "retryable": false,
    "agent_action": "ask_user_to_approve",
    "correlation_id": "req_01...",
    "details": {
      "approval_id": "apr_01...",
      "expires_at": "2026-08-29T20:15:00Z",
      "action_url": "https://customer.ceerat.com/agent-approvals/apr_01..."
    }
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
| `correlation_id` | Opaque support/trace reference |
| `details` | Code-specific, schema-defined, redacted recovery data |

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

### 11.3 Code-specific recovery details

Minimum code set:

```text
UNAUTHENTICATED
TOKEN_EXPIRED
TOKEN_AUDIENCE_INVALID
GRANT_REVOKED
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

Provide only the relevant typed fields for each code:

| Error | `agent_action` | Required safe details |
|---|---|---|
| `UNAUTHENTICATED`, `TOKEN_EXPIRED` | `reauthenticate` | OAuth resource metadata URL; never a token or credential |
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
| `INTERNAL` | `contact_support` or `retry_after_delay` | correlation ID only; no stack, SQL, hostname, or provider response |

For authentication responses, OAuth-standard error fields and `WWW-Authenticate` remain authoritative; the CEERAT envelope may supplement them only when protocol-compatible. Map errors consistently to HTTP/MCP semantics.

### 11.4 Error safety and response requirements

- `retryable=true` means the identical operation is safe to retry and might succeed. It must be false for validation, scope, approval, policy, revocation, and idempotency conflicts.
- Include `retry_after_seconds` only when retry is safe. Add jitter guidance in client documentation, not arbitrary prose in responses.
- For writes, always state whether the operation was `not_started`, `completed`, or `outcome_unknown`.
- Never expose access/refresh tokens, authorization codes, cookies, passwords, MFA data, stack traces, SQL errors, private hostnames, policy implementation internals, or another tenant's resource existence.
- Bound field-error arrays and text lengths. Unknown internal errors collapse to `INTERNAL` with a correlation ID.
- Tool definitions must document their possible CEERAT error codes and the output schema must include the error union.
- Error responses must be audited with code, tool, principal/client IDs, and correlation ID, while preserving the same redaction rules as successful calls.

### 11.5 Phase-one error examples

Expired login:

```json
{
  "ok": false,
  "error": {
    "code": "TOKEN_EXPIRED",
    "category": "authentication",
    "message": "The CEERAT access token has expired.",
    "user_message": "Please reconnect your CEERAT account.",
    "retryable": false,
    "agent_action": "reauthenticate",
    "correlation_id": "req_01...",
    "details": {
      "resource_metadata": "https://agents.ceerat.com/.well-known/oauth-protected-resource/mcp"
    }
  }
}
```

Invalid profile update:

```json
{
  "ok": false,
  "error": {
    "code": "INVALID_ARGUMENT",
    "category": "validation",
    "message": "Two profile fields are invalid.",
    "user_message": "Please correct the state and postal code.",
    "retryable": false,
    "agent_action": "correct_arguments",
    "correlation_id": "req_02...",
    "details": {
      "fields": [
        {"field": "address.state", "reason": "unsupported_code", "expected": "two-letter US state code"},
        {"field": "address.postal_code", "reason": "invalid_format", "expected": "US ZIP or ZIP+4"}
      ]
    }
  }
}
```

Missing permission:

```json
{
  "ok": false,
  "error": {
    "code": "INSUFFICIENT_SCOPE",
    "category": "authorization",
    "message": "The connection cannot update the customer profile.",
    "user_message": "Reconnect CEERAT and allow profile updates to continue.",
    "retryable": false,
    "agent_action": "request_additional_scope",
    "correlation_id": "req_03...",
    "details": {
      "required_scopes": ["ceerat.profile.write"],
      "granted_scopes": ["openid", "profile", "ceerat.profile.read"]
    }
  }
}
```

## 12. Development runtime and deferred deployment

Kubernetes setup is outside the development scope. Do not add or modify anything under `infra/k8s` as part of the development phases. Do not make local verification depend on a cluster, ingress controller, container registry, external secret controller, HPA, or Kubernetes DNS.

### 12.1 Local process

```text
ceerat-agent-gateway
  listen:             127.0.0.1:8090
  MCP endpoint:       http://localhost:8090/mcp
  user-service gRPC:  localhost:50051
  authorization URL: configured local development issuer
```

Add gateway commands to the existing local stack scripts only after the standalone binary and tests work. Logs should use the existing local `logs/` convention and PID lifecycle used by the infra scripts. Keep configuration injectable so tests can use ephemeral ports and fake dependencies.

### 12.2 Local configuration

Development configuration may use values such as:

```text
CEERAT_MCP_PORT=8090
CEERAT_MCP_RESOURCE=http://localhost:8090/mcp
CEERAT_AUTH_ISSUER=http://localhost:<issuer-port>
CEERAT_USER_SERVICE_ADDR=localhost:50051
CEERAT_MCP_PROTOCOL_VERSION=<pinned revision>
CEERAT_TOKEN_CLOCK_SKEW=30s
CEERAT_TOOL_DEFAULT_TIMEOUT=15s
```

Bind to loopback by default. Plain HTTP is allowed only for isolated local development. Tests must use temporary credentials and must never require committed secrets. Production issuer/resource values must not be hard-coded.

### 12.3 Local security boundary

- Do not expose the local gateway on `0.0.0.0` by default.
- Do not forward `/agent/chat`, private gRPC reflection, metrics, or profiling endpoints through the MCP route.
- Do not connect the gateway directly to PostgreSQL or Typesense.
- Keep OAuth tokens out of command lines, logs, shell history, fixtures, and model context.
- Use fake/test clients and a development issuer for automated tests.
- Preserve issuer/audience/signature/scope/ownership checks in development; local mode must not bypass authentication.

### 12.4 Deferred production deployment handoff

After the local implementation has passed human validation and protocol compatibility testing, create a separate production deployment document. That future work may cover images, Kubernetes Deployments and Services, public ingress/TLS, network policy, secret management, autoscaling, disruption budgets, topology spread, and production DNS. None of those items is an acceptance criterion for the development phases in this document.

## 13. Observability, audit, and SLOs

Use OpenTelemetry for traces, metrics, and structured logs. Propagate a CEERAT correlation ID through gateway and gRPC metadata. Do not record tool arguments wholesale.

Key metrics:

```text
mcp_requests_total{method,status,client}
mcp_tool_calls_total{tool,outcome,client}
mcp_tool_duration_seconds{tool}
mcp_auth_failures_total{reason,client}
mcp_policy_decisions_total{tool,decision,reason}
mcp_approval_total{tool,state}
mcp_idempotency_total{tool,outcome}
mcp_rate_limit_total{dimension,tool}
mcp_downstream_duration_seconds{service,method,status}
mcp_tasks_total{type,state}
mcp_task_age_seconds{state}
```

Initial targets, to be revised after load testing:

- Gateway availability: 99.9% monthly for MCP initialization, discovery, and read tools.
- Read-tool latency: p95 under 1 second excluding explicitly documented search bounds.
- Prepare latency: p95 under 3 seconds.
- Submission acknowledgement: p95 under 2 seconds when execution is synchronous; otherwise return a durable task/preparation reference.
- Audit durability: every write attempt has an audit record; alarm on any detected gap.

Audit events should capture event ID, timestamp, customer/user, client/grant, tool, arguments hash, scope, policy version/decision, approval record, idempotency key hash, target object IDs, result, latency, and correlation/trace IDs. Provide customers an Agent Activity view and operators a restricted investigation view.

## 14. Threat model and controls

| Threat | Required control |
|---|---|
| Stolen token | Short TTL, audience restriction, least scope, revocation, sender-constrained tokens where feasible |
| Confused deputy/token passthrough | Exact issuer/audience checks; never accept tokens meant for another resource; internal credentials isolated |
| Prompt injection in job content | Treat all external content as data; deterministic policy; no dynamic tool creation; output encoding |
| Agent lies about approval | Server-side approval bound to immutable preparation hash |
| Duplicate/retried submission | Mandatory idempotency key and downstream reconciliation |
| Cross-customer access | Identity never accepted from tool arguments; ownership predicates in repositories |
| Malicious/compromised client | Client trust tiers, per-client grants and quotas, rapid revocation, behavioral alerts |
| Schema abuse | Strict JSON Schema, unknown-field rejection, length/page/enum bounds |
| SSRF | No arbitrary URLs in public tools; controlled adapters and allowlists |
| Exfiltration through errors/logs | Redaction, bounded output, no raw tokens/resumes/application bodies |
| Resource exhaustion | Edge and application rate limits, weighted tool costs, timeouts, concurrency caps |
| Queue replay | Signed task authorization snapshot, lease fencing, idempotent item execution |
| Policy race | Versioned preparation; recheck immutable hard constraints immediately before write |

Commission an external security review before enabling `applications.submit` for general availability.

## 15. Phased implementation plan

### Phase 0: prerequisite architecture and protocol spike

- Select and pin the Go MCP SDK/protocol revision after interoperability tests.
- Select the authorization server and client onboarding approach.
- Define production domains, issuer, resource identifier, and trust tiers.
- Implement the browser login/consent journey and authorization code + PKCE flow; decide whether device authorization is required for the pilot.
- Build a disposable `/mcp` initialization/tools-list spike on a loopback development port.
- Prove OAuth discovery, PKCE, audience validation, and token rejection cases with at least two clients.

Exit: an architecture decision record, threat model, compatibility matrix, and no write tools.

### Phase 1: login and user management

- Create the gateway binary, internal gRPC adapter, tool registry, schemas, and error model.
- Integrate the authorization server and implement browser login, authorization code + PKCE, consent, token issuance/refresh, logout, and grant revocation.
- Add OAuth client, grant/consent, connection, and security-audit persistence.
- Publish protected-resource metadata, authorization-server/OIDC discovery, and JWKS metadata.
- Implement only `get_current_user`, `get_my_customer_profile`, `update_my_customer_profile`, `list_my_agent_connections`, and `revoke_my_agent_connection` from section 7.1.
- Require confirmation for profile writes and connection revocation; keep passwords, MFA, email/phone verification, roles, account deletion, and administrator user management on CEERAT-owned browser/admin surfaces.
- Implement the complete agent-actionable error contract, including authentication recovery, missing-scope recovery, field validation, retry safety, and correlation IDs.
- Add local process startup/shutdown/status integration, environment configuration, structured logs, metrics, and development dashboards where useful.
- Add developer documentation and sandbox client registration.

Exit: a customer can connect an approved agent client, log in, grant bounded scopes, inspect/update safe profile fields, inspect/revoke connections, refresh a session, and disconnect. Cross-customer, token, scope, confirmation, revocation, rate, audit, and structured-error tests pass. No job, resume, application, cart, employer, or admin tools are published.

### Phase 2: career discovery and application reads

- Add `list_my_resumes`, `search_jobs`, `get_job`, `list_my_applications`, and `get_my_application`.
- Add bounded pagination, search quotas, output redaction, and resource-not-found recovery hints.
- Verify ownership and client scopes independently in the gateway and user-service layers.

Exit: read-only career pilot passes ownership, pagination, quota, schema, error-recovery, and audit tests.

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

### Phase 6: ecosystem and developer platform

- Publish tool catalog, schemas, examples, sandbox, quotas, changelog, uptime status, and webhook/event documentation.
- Certify integrations client by client.
- Add further tools only through security review and compatibility versioning.

## 16. Testing and verification

### 16.1 Unit tests

- Tool schema validation, including unknown and oversized fields.
- Token claim validation and clock boundaries.
- Scope matrices and grant revocation.
- Profile update allowlist, immutable identity fields, confirmation binding, and sensitive-field rejection.
- Error-code-to-agent-action mapping, typed detail schemas, redaction, and retryability invariants.
- Policy precedence, currency/location ambiguity, and deny-by-default behavior.
- Approval binding, expiration, revocation, and single consumption.
- Idempotency state transitions and hash conflicts.
- Error mapping and redaction.

### 16.2 Integration tests

- OAuth metadata discovery, authorization code + PKCE, refresh/revocation.
- Wrong issuer, audience, client, signature, scope, and expired token rejection.
- Login cancellation, denied consent, refresh-token rotation/reuse, logout, current-grant revocation, and scope elevation.
- Gateway-to-user-service identity propagation and ownership enforcement.
- Phase-one user flow: get user, get profile, confirm/update allowed fields, list connections, revoke connection, and verify immediate denial afterward.
- Phase-one errors: agent follows `reauthenticate`, `request_additional_scope`, `correct_arguments`, and `retry_after_delay` without parsing message prose.
- Ensure all phase-one error responses are schema valid, bounded, redacted, and contain a correlation ID.
- Search pagination and bounded results.
- Prepare/approve/submit/status happy path.
- Concurrent duplicate submission proves exactly one downstream execution.
- Timeout-after-submit produces reconciliation rather than duplicate retry.
- Rate limits across multiple gateway replicas.
- Audit event exists for success, deny, approval required, and dependency failure.

### 16.3 Protocol and client compatibility

Maintain golden MCP initialization, tool-list, tool-call, error, and protocol-version fixtures. Test current versions of targeted clients in CI or a scheduled compatibility environment. A client-specific workaround must stay at the adapter/metadata edge and must not weaken the shared authorization model.

### 16.4 Platform gates

Follow the builder's contract-first workflow:

```bash
cd ceerat-platform-builder-agent
ceerat-builder check-context
ceerat-builder plan --mode local --output json "<gateway capability>"
ceerat-builder impact contract agentgateway.AgentGatewayService --add <Capability> --output json
ceerat-builder rbac suggest agentgateway.AgentGatewayService --capability <Capability> --output json

cd ../infra
make verify-platform
```

Also add gateway-specific Go tests, static analysis, OAuth conformance tests, and local load tests. Container scanning and deployment-manifest policy checks are deferred with production deployment. Run live write verification only against dedicated test customers and fake/sandbox application targets.

## 17. Operational controls and runbooks

Provide operator controls for:

- disable all public MCP traffic;
- disable one client, grant, customer, scope, or tool;
- force approval for a tool globally;
- revoke signing keys/tokens and rotate internal credentials;
- pause workers and campaigns;
- reconcile an `OUTCOME_UNKNOWN` submission;
- inspect a correlation ID without exposing sensitive payloads;
- export/delete customer agent data according to retention rules.

Alert on unusual auth failures, policy denies, submission spikes, approval bypass attempts, idempotency conflicts, reconciliation backlog, audit-write failures, JWKS refresh failures, and sustained downstream errors. Consequential tools should fail closed if authoritative grant, policy, approval, or idempotency storage is unavailable.

## 18. Decisions still required

1. Which authorization server will CEERAT operate or buy, and does it support the needed MCP client metadata/registration profile?
2. Will the gateway source live in `apps-repo`, a new repository, or a backend service repository? This design recommends a dedicated binary and image regardless.
3. Will gateway domain state be an `agentgateway` module in `ceerat-user-service` or a new private gRPC service? Start as a module if team/scale does not justify a new deployable.
4. What constitutes legal/customer consent for submitting an employment application, and what information must be shown at approval time?
5. Which clients are admitted to the first pilot, and which client-specific limitations apply?
6. What are the retention periods for preparations, approvals, task payloads, idempotency records, and audit events?
7. Does CEERAT need regional data residency or tenant-specific encryption before public launch?

None of these decisions blocks a read-only protocol and OAuth spike. Decisions 1, 4, and 6 block production write tools.

## 19. Recommended immediate backlog

1. Record the new-service gateway decision in an ADR.
2. Choose the authorization server and validate its MCP discovery/client onboarding behavior.
3. Implement an end-to-end login/consent prototype using authorization code + PKCE, token refresh, grant revocation, and MCP protected-resource discovery.
4. Define phase-one protobuf contracts for grant resolution, connection listing/revocation, profile self-service integration, and agent activity/audit queries.
5. Scaffold `ceerat-agent-gateway` with health/readiness, MCP initialization, the phase-one static tool registry, token middleware, and structured error mapper.
6. Implement `get_current_user`, `get_my_customer_profile`, and confirmation-gated `update_my_customer_profile`.
7. Implement `list_my_agent_connections` and confirmation-gated `revoke_my_agent_connection`.
8. Add loopback-only local stack integration and a local OAuth test issuer; do not add Kubernetes or ingress configuration.
9. Add golden protocol/error fixtures, cross-tenant tests, agent-recovery tests, and OpenTelemetry.
10. Run login plus user-management interoperability tests with two clients before adding career tools.

## 20. Standards references

- [MCP 2026-07-28 specification release](https://blog.modelcontextprotocol.io/posts/2026-07-28/)
- [MCP authorization specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
- [MCP tools specification](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- [OAuth 2.0 Protected Resource Metadata (RFC 9728)](https://datatracker.ietf.org/doc/html/rfc9728/)
- [Resource Indicators for OAuth 2.0 (RFC 8707)](https://datatracker.ietf.org/doc/html/rfc8707)
- [OAuth 2.0 Device Authorization Grant (RFC 8628)](https://datatracker.ietf.org/doc/html/rfc8628)
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0-18.html)

Protocol URLs should be reviewed when implementation begins. The repository should pin a tested MCP revision and SDK version rather than relying on an unversioned interpretation of the latest specification.
