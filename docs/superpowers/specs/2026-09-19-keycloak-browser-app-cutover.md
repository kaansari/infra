# Keycloak Browser Application Cutover Specification

## Objective

Rebuild `ceerat-web-ui`, `ceerat-customer-ui`, and the internal agent chat
service against the current contracts and user service. All authentication uses
Keycloak authorization code flow with PKCE. This is a new system: no legacy
password authentication, compatibility route, fallback token, deprecated API,
or migration behavior remains.

## Application boundaries

`ceerat-web-ui` is the operational portal for active agents and administrators.
New identities arriving through its OAuth client are provisioned as pending
agents and cannot establish an application session until an administrator
activates them.

`ceerat-customer-ui` is the customer self-service portal. New identities
arriving through its OAuth client are provisioned as active customers with a
customer profile. It contains no AI chat surface.

The rebuilt internal agent chat service supports only active agents and
administrators from `ceerat-web-ui`. It calls current private gRPC contracts and
has no customer endpoints or `/chatgpt-client` compatibility surface. The
public `ceerat-agent-gateway` remains a separate MCP boundary.

## Identity provisioning

The user service owns a fail-closed client provisioning policy:

| OAuth client | Initial role | Initial status | Customer profile |
| --- | --- | --- | --- |
| `ceerat-web-ui` | `agent` | `pending` | no |
| `ceerat-customer-ui` | `customer` | `active` | yes |

The client ID comes only from the cryptographically validated token. Requests,
browser fields, Keycloak realm roles, groups, and email addresses cannot select
the Ceerat role or account status. Configuration with an unknown client,
duplicate client, invalid role/status, or overlapping policy fails startup.

An existing issuer/subject binding always loads its database-authoritative
role and status. Email collisions fail closed and never link identities.
Pending agents return a stable, safe `account_pending` result after provisioning
so `ceerat-web-ui` can render a pending-approval page without creating a session.

## OAuth clients

Both clients are public clients with standard authorization code flow, PKCE
S256, token endpoint authentication `none`, exact redirect URIs, no implicit or
password grant, no service account, and no wildcard origin. Login, registration,
Google sign-in, logout, and credential recovery remain Keycloak-owned.

Local callbacks are `http://localhost:3000/oauth/callback` and
`http://localhost:3005/oauth/callback`. Hosted callbacks use the corresponding
exact HTTPS Render host. Each client receives only scopes used by its current
route-to-gRPC inventory.

## Browser session security

Each app stores the access token only in an HttpOnly session cookie. Production
cookies are Secure and SameSite=Lax. OAuth state and PKCE verifier cookies are
single-use and short-lived. Callback validation rejects missing, mismatched,
replayed, or provider-error responses. Mutations require same-origin requests.
Tokens, cookies, codes, verifiers, passwords, claims, and secrets never enter
browser JSON, URLs controlled by the app, logs, or retained test evidence.

The app forwards the original Keycloak access token unchanged to private gRPC.
Production gRPC requires TLS. The user service repeats signature, issuer,
audience, client, time, token-type, verified-email, subject binding, method
scope, active-account, role, RBAC, and handler/repository ownership checks.

## Page and contract policy

Every same-origin API route has a checked-in mapping to one or more exact gRPC
methods. A deterministic test verifies each method exists in
`KnownGRPCMethods`, has a `MethodScopePolicies` entry, and is granted to the
page's role in `DefaultRolePermissions`. Hand-maintained calls to removed RPCs
or direct database/search access fail the gate.

Agent pages use operational cross-user methods for customers, connections,
orders, catalog, companies, jobs, applications, pricing, and current-user
profile. Customer pages use self-scoped profile, customer, product/cart, order,
preference, career, application, and calendar methods. Customer requests never
accept caller-selected ownership identifiers where a `My*` method exists.

The browser apps do not create credentials or change passwords. Registration
pages become Keycloak registration entry points, and preference pages link to
the Keycloak account console for credential management.

## Agent chat

The internal agent chat service accepts the original `ceerat-web-ui` bearer
token, validates it with the shared security package, resolves the database
identity, and requires active `agent` or `admin`. Its tools call current gRPC
methods with the same bearer token. Tool inputs remain bounded and cannot
select a caller identity or bypass RBAC. Thread persistence uses the current
`ai.AIThreadService` contracts.

Customer chat handlers, customer tools, deprecated prompt-result endpoints,
legacy JWT parsing, and compatibility fallbacks are deleted. The web UI exposes
one current same-origin agent-chat API and one current agent-chat page.

## Removal policy

Delete, rather than redirect or retain:

- Email/password login, registration, and change-password handlers.
- Password fields and password-bearing DTOs in both apps.
- Customer chat UI, APIs, assets, and service calls.
- `/chatgpt-client` compatibility pages and prompt-result endpoints.
- Deprecated agent/customer chat endpoints and duplicated legacy adapters.
- Configuration variables used only by deleted paths.

No legacy aliases, hidden fallback routes, dual-write behavior, or migration
flags are permitted.

## Verification gates

Unit and integration tests cover PKCE, exact redirects, client scopes, Google
broker hints, state replay, session cookies, CSRF, role/status provisioning,
email conflicts, pending-agent denial, activation, wrong issuer/audience/client,
missing scopes, RBAC denial/allowance, ownership denial/allowance, and redacted
errors/logs.

Local acceptance uses real loopback Keycloak and invokes real protected gRPC
methods for both clients. It verifies pending agent registration, administrator
activation, active agent pages and chat, active customer registration, and all
customer page groups. Synthetic tokens cannot satisfy the positive gate.

Final gates are builder `check-context`, `rbac check`, `check drift`, `check
apps`, application inventories, all affected Go tests, and `make
verify-platform`. Builder standards are updated only after implementation,
local acceptance, and human validation.
