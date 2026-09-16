# PR 04: OAuth-only enforcement on protected gRPC

Implementation status: complete locally; coordinated PR 05 token pass-through
is implemented. The remaining role/session/TLS matrix blocks production rollout.

Repositories: `contracts-repo`, `services-repo`, `infra`  
Depends on: PRs 01–03A

## Objective

Make the original Keycloak access token the only end-user credential accepted
by protected gRPC methods and provide a real authorization-code + PKCE local
test path.

## Work

- Wire interceptor order `OAuth validation -> identity resolution -> method
  scope -> RBAC -> logging -> handler` for unary and streaming RPCs.
- Reject CEERAT HS256 end-user tokens and any token with the wrong API audience,
  issuer, client, or token type.
- Enforce the complete PR 01 method-scope matrix before RBAC and handlers.
- Preserve repository ownership checks as the final record boundary.
- Keep only health checks on the reviewed public allowlist.
- Configure local Keycloak with the canonical API audience mapper and public
  native `ceerat-grpc-dev` client: exact loopback callback, PKCE S256, no client
  secret, no password/implicit grant.
- Add a local OAuth helper that opens authorization, listens only on loopback,
  verifies state, exchanges the code with PKCE, never prints refresh tokens,
  and writes any temporary access token to a mode-0600 file or passes it only to
  the test process. Avoid shell history and committed token artifacts.
- Add `make verify-grpc-oauth` and a machine-readable redacted result.
- Make `verify-grpc-oauth` refuse public hosts/live issuers and require a real
  local authorization-code + PKCE token; synthetic or internally minted JWTs
  do not satisfy its success case.
- Bind production gRPC to TLS ingress before public exposure. Local plaintext
  must remain loopback-only.

## Required integration matrix

- Real Keycloak login then protected gRPC success for customer, agent, admin.
- Every registered protected RPC rejects missing and non-Keycloak credentials.
- Invalid signature/issuer/audience/client/time/algorithm/token-type failures.
- Valid token with missing scope, wrong role, and cross-customer ownership.
- Refresh obtains continued access; logout/revocation prevents subsequent use
  according to the documented token/session policy.
- All failures stop before handler/database mutation and return safe status.

## Gates

```text
make start-stack CEERAT_MCP_ONLY=true
make verify-grpc-oauth
go test -race ./...
go build ./...
ceerat-builder rbac check --output json
ceerat-builder check sql --output json
```

## Deployment constraint

PR 04 and PR 05 are one coordinated runtime cutover. Do not leave production
MCP sending any alternate token format to an OAuth-only gRPC service.
Do not push this PR for Render until the complete local direct gRPC/OAuth matrix
passes and its sanitized evidence has been reviewed.

## Out of scope

Browser apps, legacy agent service, REST, device/password grant, wildcard
redirects, and long-lived developer tokens.

## Documentation after PR

Update gRPC API testing, local stack, OAuth client, TLS, security, error, and
deployment-skew documentation plus affected inventories.

## Implemented result

- Replaced the service's active HS256/internal-token interceptor with the
  fail-closed chain `OAuth -> identity -> method scope -> RBAC -> logging ->
  handler` for unary and streaming RPCs.
- Accepts end-user credentials only as an OAuth Bearer header. Password login,
  registration, token validation, token minting, and identity-exchange RPCs
  have been removed from the protobuf contract and service implementation.
- Preserved database-backed CEERAT roles, account status, and repository
  ownership as independent authorization boundaries.
- Added public PKCE-only `ceerat-grpc-dev`, exact loopback callbacks, canonical
  `ceerat-api` audience, explicit subject claim, and no secret/password/implicit
  grant.
- Added loopback-only reconciliation and `make verify-grpc-oauth`. The verifier
  performs real Google -> Keycloak authorization code + S256 PKCE, never logs
  OAuth material, proves missing-token denial, and invokes the protected
  `GetMyCustomerProfile` RPC with the original Keycloak access token.

## Local evidence (2026-09-15)

```text
real authorization-code + PKCE customer gRPC: PASS
missing-token protected RPC denial: PASS
main PostgreSQL JIT identity persisted: PASS (aggregate external identities 0 -> 1)
contracts go test -race ./... and go build ./...: PASS
user service go test -race ./... and go build ./...: PASS
Keycloak realm policy: PASS (208 assertions)
ceerat-builder RBAC: PASS (0 issues)
ceerat-builder SQL: PASS (0 issues)
```

No Render deployment is authorized by this result. PR 05 now forwards the
original MCP OAuth token with the canonical API audience. Real agent/admin role
grants, missing-scope/wrong-role cases, refresh,
logout/revocation, and public TLS ingress remain required acceptance work.
