# PR 04: OAuth-only enforcement on protected gRPC

Repositories: `contracts-repo`, `services-repo`, `infra`  
Depends on: PRs 01–03

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
- Keep health and deliberately public OAuth bootstrap methods on the reviewed
  minimal allowlist; remove accidental public entries.
- Configure local Keycloak with the canonical API audience mapper and public
  native `ceerat-grpc-dev` client: exact loopback callback, PKCE S256, no client
  secret, no password/implicit grant.
- Add a local OAuth helper that opens authorization, listens only on loopback,
  verifies state, exchanges the code with PKCE, never prints refresh tokens,
  and writes any temporary access token to a mode-0600 file or passes it only to
  the test process. Avoid shell history and committed token artifacts.
- Add `make verify-grpc-oauth` and a machine-readable redacted result.
- Bind production gRPC to TLS ingress before public exposure. Local plaintext
  must remain loopback-only.

## Required integration matrix

- Real Keycloak login then protected gRPC success for customer, agent, admin.
- Every registered protected RPC rejects missing and legacy internal JWTs.
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
MCP sending the removed internal token format to an OAuth-only gRPC service.

## Out of scope

Browser apps, legacy agent service, REST, device/password grant, wildcard
redirects, and long-lived developer tokens.

## Documentation after PR

Update gRPC API testing, local stack, OAuth client, TLS, security, error, and
deployment-skew documentation plus affected inventories.

