# PR 05: MCP original OAuth bearer-token pass-through

Implementation status: implemented locally; production acceptance remains pending.

Repositories: `apps-repo`, `services-repo` cleanup  
Depends on: PR 04; deploy as the same coordinated unit

## Objective

Make MCP use the identical protected gRPC OAuth credential path by forwarding
the original validated Keycloak access token.

## Work

- Preserve the inbound OAuth bearer token in request-scoped memory only after
  gateway validation; never put it in model-visible state or durable storage.
- Forward it as gRPC `authorization: Bearer` metadata for every platform call.
- Keep gateway issuer/audience/client/time and per-tool-scope validation for
  early MCP errors, while requiring gRPC to repeat authoritative validation.
- Remove `SessionForIdentity` internal-token minting from normal MCP calls.
- Remove gateway use of `auth.Auth/ExchangeExternalIdentity` and its workload
  secret for end-user authentication. Do not add fallback to the old exchange.
- Ensure confirmations and operation-status calls revalidate the current OAuth
  token and remain bound to subject/client/session/resource state.
- Keep revoker service credentials isolated from user delegation.
- Map gRPC auth/scope/RBAC failures into stable MCP envelopes without exposing
  tokens, claims, internal hosts, or cryptographic diagnostics.

## Tests

- exact original-token forwarding and no internal token exchange;
- gateway and gRPC both reject invalid tokens independently;
- same subject/client/scopes observed through MCP and direct gRPC;
- missing tool scope and missing gRPC method scope fail closed;
- expired/refreshed/revoked token and confirmation-after-revocation;
- concurrent calls cannot mix bearer tokens or cached principals;
- log, error, state, and preparation scans contain no raw token.

## Gates

```text
GOWORK=off go test -race ./...
GOWORK=off go build ./...
make verify-grpc-oauth
make verify-phase1-live
make verify-phase2-live
ceerat-builder check apps --output json
ceerat-builder check drift --output json
```

Before push, run local MCP/OAuth with a real local-Keycloak authorization and
prove from correlated gateway/gRPC logs that the original access token reached
the gRPC validator. Also rerun direct gRPC/OAuth so the coordinated pair is
validated together. Do not use ChatGPT or Render as the first integration test.

## Out of scope

Tool additions, domain behavior, browser apps, legacy agent tools, token storage,
REST, and accepting both internal and OAuth end-user tokens.

## Documentation after PR

Update gateway architecture/security, MCP OAuth flow, structured errors,
service caller inventory, and deployment ordering documentation.

## Implemented result

- The gateway retains the validated inbound bearer only in request scope and
  forwards it as standard gRPC authorization metadata.
- Private gRPC independently repeats OAuth validation, identity resolution,
  method-scope enforcement, database RBAC, account checks, and ownership.
- `SessionForIdentity`, `ExchangeExternalIdentity`, the gateway workload secret,
  internal end-user JWT minting, and all fallback paths were removed.
- MCP client tokens carry both their exact MCP resource audience and
  `ceerat-api`; the gateway still requires the former and gRPC requires the latter.
- Unit tests assert exact original-token forwarding. Raw tokens are not placed
  in MCP responses, preparations, durable state, or logs.
