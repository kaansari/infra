# Canonical OAuth architecture for direct gRPC and MCP

Status: PR 01 policy freeze; no runtime or live Keycloak change.

## Decision

CEERAT accepts Keycloak OAuth access tokens with the canonical `ceerat-api`
audience for end-user API access. Direct gRPC clients send that token as Bearer
metadata. MCP authenticates at its public boundary and forwards the same token
to private gRPC. It does not exchange or replace it with the historical CEERAT
JWT.

Authorization is cumulative:

```text
Keycloak signature + issuer + time + ceerat-api audience
  -> explicit method OAuth scope
  -> CEERAT issuer/subject identity and active account
  -> existing method-level RBAC
  -> self/tenant/resource ownership
```

Scopes constrain delegated client access. They do not remove or weaken RBAC.

## Inventory freeze

The contract and service inventories both describe 160 RPCs with no name-level
mismatch. Nine preference RPCs are contractually classified but intentionally
not registered in `ceerat-user-service` yet; their inventory status is
`storage_ready_until_phase3_pr04_handlers`. This is the only known
contract/runtime registration mismatch at this freeze.

All known protected RPCs have an explicit scope in
`security.MethodScopePolicies`. The contract test fails if a method is missing,
is both public and protected, references an unknown method, or has an empty or
non-CEERAT scope.

The nine current public entries contain two health methods and seven
transitional `auth.Auth` methods. PR 07 removes the password/token and external
identity exchange surface. Health is the only intended steady-state public
gRPC capability.

## Clients and workloads

| Client | Class | Flow | Boundary |
| --- | --- | --- | --- |
| `ceerat-grpc-dev` | Native development | Authorization code + PKCE S256 | Loopback redirects; direct gRPC testing |
| `ceerat-mcp-codex-dev` | Native development | Authorization code + PKCE S256 | Loopback redirects; MCP testing |
| `ceerat-mcp-chatgpt` | Hosted confidential | Authorization code + client authentication + PKCE S256 | Exact ChatGPT callback |

Client IDs identify client software, not individual customers. Keycloak
issuer/subject identifies a person. Confidential service clients use separate
workload audiences and scopes; client-credentials tokens cannot impersonate a
customer or call `My`/self-scoped RPCs.

## Errors and logging

Invalid or absent credentials return gRPC `Unauthenticated`. A valid credential
denied by scope, account state, RBAC, or ownership returns `PermissionDenied`.
Responses use stable safe descriptions. Sanitized logs distinguish internal
reason codes but never include tokens, full claims, signing diagnostics,
authorization codes, cookies, passwords, or client secrets.

## Transport and deployment

Plaintext is limited to local loopback. Production public gRPC requires TLS
1.2+ and hostname validation; private transport requires provider isolation and
TLS/mTLS where it crosses an untrusted boundary.

The planned Keycloak definitions under
`deploy/render/keycloak/design/oauth-grpc/` are deliberately outside the live
reconciliation glob. They define the `ceerat-api-audience` mapper and
`ceerat-grpc-dev` client without mutating live state in PR 01.

Runtime PRs cannot deploy until local direct gRPC/OAuth and MCP/OAuth tests pass.
There is no dual-validator mode. A rollback uses a matched known-good release
and configuration; it never restores password grants, obsolete clients,
fallback headers, or the CEERAT JWT path.
