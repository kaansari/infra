# CEERAT canonical OAuth authentication PR plan

This plan makes Keycloak OAuth access tokens the only end-user credential for
both direct gRPC clients and MCP clients. Browser applications and the legacy
agent service are deliberately excluded.

## Target architecture

```text
Direct client -> Keycloak authorization-code + PKCE -> OAuth access token
              -> TLS gRPC -> OAuth validation -> identity mapping -> scopes
              -> RBAC -> logging -> handler -> PostgreSQL

ChatGPT/Codex -> Keycloak authorization-code + PKCE -> same OAuth access token
              -> HTTPS MCP gateway -> early OAuth/tool-scope validation
              -> private gRPC carrying the original access token
              -> OAuth validation -> identity mapping -> scopes
              -> RBAC -> logging -> handler -> PostgreSQL
```

The gateway may reject an invalid token early, but it is not the final trust
boundary. The gRPC service independently validates the original OAuth token.
No MCP request is translated into a CEERAT HS256 user session.

## Non-negotiable rules

- Keycloak is the sole end-user authentication and token issuer.
- End-user protected gRPC methods reject CEERAT locally issued HS256 tokens.
- Validate signature/algorithm, issuer, API audience, expiry/not-before,
  authorized party/client, subject, session/token identifiers, and scopes.
- Resolve CEERAT identity only from verified `(issuer, subject)` claims. Never
  accept user, customer, role, tenant, or scope authority from request fields.
- Enforce OAuth method scopes, CEERAT RBAC, current account status, and record
  ownership independently on every call.
- Preserve interceptor order `OAuth -> scope -> RBAC -> logging -> handler`.
- Forward the original OAuth token through MCP; do not mint or fall back to an
  internal end-user JWT.
- Service/workload authentication is a separate non-user mechanism with an
  explicit audience and identity. It may not impersonate an end user.
- Production direct gRPC requires TLS. Plaintext is allowed only on explicitly
  loopback-bound local development listeners.
- Never log raw access/refresh tokens, authorization headers, client secrets,
  authorization codes, PKCE verifiers, passwords, or full claim sets.
- No compatibility flag, dual validator, fallback token parser, shadow path,
  browser-app repair, REST endpoint, or legacy AI-tool work is included.

## Dependency order

| Order | PR | Repositories | Outcome |
| --- | --- | --- | --- |
| 1 | [Architecture and scope policy](01-architecture-scope-policy.md) | `infra`, `contracts-repo`, builder docs after validation | Freeze audience, clients, claims, method scopes, workload boundary, and cutover contract |
| 2 | [Shared OAuth validator](02-shared-oauth-validator.md) | `contracts-repo` | Add reusable JWKS/OIDC access-token validation and authenticated principal context |
| 3 | [Identity resolution and account authority](03-identity-resolution.md) | `services-repo` | Resolve/JIT-provision verified Keycloak subjects and remove password-token assumptions from the protected path |
| 4 | [gRPC OAuth enforcement](04-grpc-oauth-enforcement.md) | `contracts-repo`, `services-repo`, `infra` | Cut protected gRPC to OAuth-only scope/RBAC/ownership enforcement and add direct OAuth test login |
| 5 | [MCP bearer pass-through](05-mcp-token-passthrough.md) | `apps-repo`, `services-repo` | Forward the original OAuth bearer token and remove gateway end-user token exchange |
| 6 | [Unified tracing and security logs](06-unified-observability.md) | `contracts-repo`, `services-repo`, `apps-repo`, `infra` | Make direct gRPC and MCP calls produce the same correlation and authorization evidence |
| 7 | [Cutover acceptance and cleanup](07-cutover-acceptance.md) | all implementation repositories | Prove both clients, reject old tokens, remove obsolete code/config, and freeze documentation |

PRs 01–03 add policy or dormant components and must not enable a second runtime
authentication path. PRs 04 and 05 form one coordinated deployment unit:
service first in a maintenance/deployment window and gateway immediately after.
Do not expose a release that silently accepts both end-user token formats.

## OAuth clients and audience

- Use one canonical API audience, `ceerat-api` (final URI/identifier is frozen
  in PR 01), for tokens accepted by protected gRPC methods.
- `ceerat-mcp-chatgpt` and `ceerat-mcp-codex-dev` remain host-specific OAuth
  clients but receive the API audience through an audience mapper.
- Add `ceerat-grpc-dev` as a public native development client with authorization
  code, PKCE S256, exact loopback redirects, no secret, no wildcard redirect,
  and no password/implicit grant.
- Production third-party clients are individually registered/approved. App
  review does not remove OAuth client registration or redirect validation.
- Client credentials are reserved for explicitly authorized workloads and are
  never accepted as customer identity.

## Scope model

PR 01 must inventory all 160 contract methods and give every protected method
an explicit scope policy. Reuse existing profile, connection, product/cart,
order, and preference scopes. Add narrowly named read/write/admin scopes for
career, calendar, AI threads, user administration, and other uncovered domains.
There is no implicit “authenticated means authorized” default. Unmapped methods
fail the build and fail closed at runtime.

## Database boundary

The existing external identity key `(issuer, subject)` remains canonical. PR 03
must determine whether current constraints are sufficient. If schema changes
are necessary, use a new forward migration, rollback policy, preflight, ledger,
checksum, and disposable PostgreSQL lifecycle test. Never edit an already
applied migration. No database change may be added merely to store access or
refresh tokens.

## Required builder workflow

Every PR uses the platform builder for context, boundaries, RBAC, database
checks, verification, and documentation impact:

```text
ceerat-builder check-context
ceerat-builder codex-context --output json
ceerat-builder evidence request "canonical Keycloak OAuth for direct gRPC and MCP" --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder rbac check --output json
ceerat-builder check sql --output json
ceerat-builder check drift --output json
```

Use app inventory only for `ceerat-agent-gateway` compatibility. Do not inspect
or modify browser pages, templates, JavaScript, or legacy agent tools.

## Documentation discipline

After each PR, update affected contract/service/gateway inventories and focused
security, architecture, logging, API-testing, and deployment documentation.
Update durable builder standards only after automated behavior passes and human
validation confirms the reusable pattern.

## Definition of done

- A real Keycloak authorization-code + PKCE token calls protected local gRPC.
- The same grant calls MCP and reaches gRPC with the original token.
- Both paths resolve the same CEERAT actor, scopes, roles, ownership, request
  correlation, and audit decision.
- Invalid issuer/audience/algorithm/client/time/signature/scope/session/account
  cases fail before handlers.
- Old CEERAT-issued end-user JWTs fail protected gRPC.
- Direct gRPC and MCP refresh/revocation behavior is tested.
- All registered protected RPCs have explicit scope/RBAC coverage.
- Database lifecycle, contract, service, gateway, security, race, log-redaction,
  and deployment-skew gates pass.
- Browser apps and legacy agent service remain untouched and out of scope.

