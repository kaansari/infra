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
| 3A | [Google identity broker](03a-google-identity-broker.md) | `infra`, Keycloak configuration | Add Google login through Keycloak while preserving one Keycloak-token security path |
| 4 | [gRPC OAuth enforcement](04-grpc-oauth-enforcement.md) | `contracts-repo`, `services-repo`, `infra` | Cut protected gRPC to OAuth-only scope/RBAC/ownership enforcement and add direct OAuth test login |
| 5 | [MCP bearer pass-through](05-mcp-token-passthrough.md) | `apps-repo`, `services-repo` | Forward the original OAuth bearer token and remove gateway end-user token exchange |
| 6 | [Unified tracing and security logs](06-unified-observability.md) | `contracts-repo`, `services-repo`, `apps-repo`, `infra` | Make direct gRPC and MCP calls produce the same correlation and authorization evidence |
| 7 | [Cutover acceptance and cleanup](07-cutover-acceptance.md) | all implementation repositories | Prove both clients, reject old tokens, remove obsolete code/config, and freeze documentation |

PRs 01–03 add policy or dormant components and must not enable a second runtime
authentication path. PRs 04 and 05 form one coordinated deployment unit:
service first in a maintenance/deployment window and gateway immediately after.
Do not expose a release that silently accepts both end-user token formats.

## New-system rule

CEERAT is a new system. This series implements one final authentication design;
it does not preserve compatibility with the current development-only internal
JWT path. At coordinated cutover, superseded code, RPCs, configuration, secrets,
tests, and documentation are removed rather than retained behind aliases,
fallback validation, feature flags, dual issuance, dual reads, or migration
shims. Browser applications will be rebuilt later against the canonical API and
do not constrain this cutover.

## Local-first delivery gate

No implementation PR in this series may be pushed for Render deployment until
the complete affected path passes locally. Mocked tokens, unit tests, a process
health check, unauthenticated reflection, or gateway-only validation do not
satisfy this gate.

Run validation in this order:

1. Start only local Postgres, Typesense, Keycloak, `ceerat-user-service`, and
   `ceerat-agent-gateway` with `CEERAT_MCP_ONLY=true make start-stack`.
2. Reconcile only the local Keycloak realm. The command and output must clearly
   identify `http://localhost:8080/realms/ceerat`; never use a target containing
   `live` for this gate.
3. Complete a real authorization-code + PKCE login through the local
   `ceerat-grpc-dev` client and obtain a short-lived Keycloak access token.
4. Call protected gRPC methods directly with that token. Verify issuer,
   audience, client, scope, current CEERAT RBAC, ownership, trace, and logs.
5. Complete a separate local OAuth authorization through the MCP development
   client, call MCP, and prove the original OAuth token reaches the same gRPC
   enforcement chain.
6. Run missing/invalid/expired/wrong-audience/wrong-client/missing-scope,
   wrong-role, cross-customer, refresh, and revocation cases locally.
7. Run contract, service, gateway, race, database, RBAC, drift, and redaction
   gates and save only sanitized evidence.
8. Review the local evidence. Only then commit/push the PR and permit Render to
   build or deploy it.

The local harness must fail if it resolves a public Render hostname, uses a
live Keycloak issuer, or lacks an explicit local-only acknowledgement. Live
reconciliation and Render acceptance remain separate post-push gates.

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
- Google is an upstream Keycloak identity provider only. CEERAT and its clients
  still trust and receive only Keycloak-issued API access tokens.

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
- Local direct gRPC/OAuth and local MCP/OAuth end-to-end tests pass before the
  implementing commit is pushed or any Render deployment begins.

Local functional completion is not production completion. The required
configuration-hardening gates in [`../confi/`](../confi/) must also pass before
this authentication series is declared production-ready.
