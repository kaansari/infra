# Public agent integration Phase 1 milestone

Status: completed interoperability milestone with documented production gaps  
Validated: 2026-08-31  
Public MCP endpoint: `https://ceerat-agent-gateway.onrender.com/mcp`

## Outcome

CEERAT Phase 1 is deployed and was exercised successfully from both Codex CLI
and a ChatGPT developer-mode plugin. The validated request path is:

```text
ChatGPT or Codex
  -> OAuth authorization code + PKCE at CEERAT Keycloak
  -> short-lived OAuth access token
  -> Authorization: Bearer <token> on MCP tools/call
  -> ceerat-agent-gateway token, scope, schema and confirmation enforcement
  -> private Render gRPC
  -> ceerat-user-service RBAC and customer ownership enforcement
  -> PostgreSQL
```

The public integration exposes nine Phase 1 MCP tools:

```text
describe_ceerat
get_authentication_status
get_current_user
get_my_customer_profile
prepare_my_customer_profile_update
update_my_customer_profile
list_my_agent_connections
revoke_my_agent_connection
logout_current_connection
```

Jobs, skills, resumes, applications, carts, password operations, verified
contact changes, account deletion and administrative operations remain outside
the public Phase 1 surface.

## Acceptance evidence

The following passed against the Render deployment with disposable identities,
followed by a human-owned customer account:

- unauthenticated MCP initialize and tools/list;
- OAuth Protected Resource Metadata and Keycloak OIDC/JWKS discovery;
- an unauthenticated protected call returning a model-actionable OAuth challenge;
- authorization-code login with PKCE from Codex;
- authorization-code login, consent and plugin registration from ChatGPT;
- token issuer, audience, expiry, client, scope and CEERAT identity validation;
- authenticated status and current-user calls;
- customer profile lookup through the private gRPC boundary;
- agent connection listing;
- destructive-tool confirmation behavior and current-connection revocation;
- strict structured success/error envelopes and operation-state reporting;
- ChatGPT discovery of tool schemas, scopes and risk annotations;
- Codex interoperability with standard MCP `params._meta` metadata.

No access token, refresh token, authorization code, password or client secret
was printed in the test results. Disposable OAuth and CEERAT records were
removed after automated tests.

PR 04 locks client validation to the configured
`CEERAT_OAUTH_ALLOWED_CLIENT_IDS` allowlist in addition to signature, issuer,
audience, time, identity, verified-email, and per-tool scope checks. The legacy
client remains in that allowlist only for the explicit PR 03 rollback window.

PR 05 binds a gateway connection to the validated Keycloak `sid` plus OAuth
client ID, keeping it stable across access-token refreshes. Confirmed logout or
connection revocation first records the local deny decision, then uses a
service-only Keycloak client to delete the identified normal/offline session.
No OAuth token is stored. If Keycloak cannot confirm deletion, the response is
truthful `OUTCOME_UNKNOWN` while local access remains denied. Because Keycloak's
supported API deletes a user session rather than one child client session,
another CEERAT client sharing the same SSO session may also be signed out.

On 2026-09-03, live ChatGPT logout returned both `revoked: true` and
`authorization_server_session_revoked: true`. A subsequent protected request
required connector reconnection, validating that the refresh path had been
terminated. An earlier mismatched revoker credential correctly produced
`OUTCOME_UNKNOWN` after local denial; coordinated secret rotation resolved it
without exposing credentials. Reconciliation now preserves the independent
ChatGPT client secret to prevent accidental token-exchange breakage.

## OAuth and identity decisions validated by testing

OAuth is the credential acquisition and delegation mechanism. The MCP wire
authentication is still a bearer token on every protected request. CEERAT uses
separate pre-registered clients using authorization code, PKCE `S256`, bounded
redirect URIs, and explicit scopes. Hosted ChatGPT is a confidential client;
native Codex is a public client.

The following integration details were required in addition to the initial
design:

- ChatGPT requests `offline_access`; Keycloak's existing `offline_access`
  client scope is optional on `ceerat-mcp-chatgpt` and
  `ceerat-mcp-codex-dev`.
- `ceerat-mcp-chatgpt` accepts only the stable hosted callback
  `https://chatgpt.com/connector_platform_oauth_redirect`. It never accepts a
  loopback or wildcard HTTPS redirect.
- `ceerat-mcp-codex-dev` accepts only `127.0.0.1` and `localhost` dynamic-port
  callbacks required by the native CLI. It never accepts the ChatGPT callback.
- Keycloak 26 rejects unknown custom user attributes by default. The realm
  declarative user profile now defines `ceerat_user_id` as an
  administrator-viewable and administrator-editable attribute.
- The `ceerat_user_id` token mapper and MCP audience mapper are required on the
  pre-registered client. The gateway never accepts user or customer IDs as
  tool arguments.
- Keycloak access tokens observed in this deployment can omit `sub`. After
  issuer, signature and audience validation, the gateway uses the configured
  `ceerat_user_id` as the principal and stable subject fallback. It still
  requires the configured client claim (`azp`).
- Codex and ChatGPT attach standard MCP `_meta` fields to tool-call parameters.
  The gateway accepts this reserved metadata while continuing to reject other
  unknown fields.
- Do not configure Codex with `--oauth-resource` for this server. The protected
  resource metadata already supplies the resource; configuring it again causes
  Keycloak to reject a duplicated `resource` parameter.

## Error and security behavior

Public authentication responses remain deliberately generic and contain an
OAuth `WWW-Authenticate` challenge plus a structured CEERAT error with stable
code, category, user message, retryability, agent action, safe details, request
ID and operation state. Token-validation internals are not returned to the
model. The gateway records a security-safe server-side reason, request ID and
tool name so operators can distinguish invalid issuer, audience, signature,
expiry and required-claim failures without logging the token.

Consequential profile writes remain split into prepare and execute operations.
The execute tool requires an opaque preparation ID and `confirmed: true`.
Connection revocation and logout are annotated as destructive and require
explicit confirmation where defined. Client annotations improve model UX, but
gateway validation is authoritative.

The gateway accepts only audience-restricted RS256 tokens from the configured
issuer, obtains an internal user-service session over the private gRPC network,
and never forwards the public OAuth token as a general downstream credential.
The gRPC service continues to enforce customer RBAC and ownership.

## Deployment corrections proven in the milestone

- Render's private user service listens on port `10000`; the gateway must use
  `ceerat-user-service:10000`, not the earlier `50051` value.
- Keycloak and the user service currently share one PostgreSQL database to
  reduce pilot cost. They also share the `public` schema, where generic table
  names can collide (the Keycloak `user_role_mapping` table was observed).
  This is accepted only for the development pilot. Production must use
  separate schemas and database users, or separate databases.
- Realm import uses `IGNORE_EXISTING`; changing the checked-in realm JSON does
  not mutate an existing live realm. Live realm changes must be applied through
  the Keycloak Admin API and also persisted in the import file for clean
  environments.

## Remaining gates

Phase 1 interoperability is complete, but it is not yet a self-service public
release. The highest-priority gap is automatic account provisioning:

```text
Keycloak registration
  -> create CEERAT customer-role user
  -> create/link CEERAT customer profile
  -> store ceerat_user_id on the Keycloak user
  -> issue a token containing the linked identity
```

The milestone used manual provisioning for the human account. New users must
not require direct SQL or an administrator to establish this link.

Before production publication, also replace the private ID-based internal
session exchange with an authenticated gateway-specific assertion/exchange,
move process-local preparations and connection state to durable shared storage,
integrate authorization-server revocation, isolate database schemas, complete
rate limiting and idempotency retention, and finish plugin submission material,
domain verification, privacy, terms and reviewer test credentials.

## Repeatable client checks

Codex uses a pre-registered client and discovery-derived resource:

```bash
codex mcp add ceerat \
  --url https://ceerat-agent-gateway.onrender.com/mcp \
  --oauth-client-id ceerat-mcp-codex-dev

codex mcp login ceerat \
  --scopes openid,profile,email,ceerat.profile.read,ceerat.profile.write,ceerat.connections.read,ceerat.connections.revoke
```

In ChatGPT developer mode, add the public MCP URL, select OAuth with the
pre-registered confidential `ceerat-mcp-chatgpt` client, provide its Keycloak
client secret only through ChatGPT's protected configuration, and sign in
through the CEERAT-owned Keycloak page. Never commit or expose that secret. A useful
read-only acceptance prompt is:

```text
Use only CEERAT. Check my authentication status, current user, customer
profile, and agent connections. Report PASS or FAIL for each and do not modify
anything.
```
