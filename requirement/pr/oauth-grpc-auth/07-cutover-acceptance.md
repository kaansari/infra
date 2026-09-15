# PR 07: OAuth cutover acceptance, cleanup, and freeze

Repositories: `contracts-repo`, `services-repo`, `apps-repo`, `infra`, builder
documentation after validation  
Depends on: PRs 01–06, including PR 03A

## Objective

Prove the single OAuth authentication path end to end, remove obsolete
end-user token machinery, and freeze deployment and operational evidence.

Production completion additionally depends on all required configuration gates
in [`../confi/`](../confi/). OAuth code acceptance alone is insufficient.

## Automated acceptance

- Start only Postgres, Typesense, Keycloak, user-service gRPC, and MCP gateway.
- Run contract, service, gateway, race, build, database lifecycle, RBAC, scope,
  drift, and log-redaction gates.
- Authenticate a direct gRPC customer through real Keycloak authorization code
  + PKCE and execute representative protected reads and reversible writes in
  every implemented domain allowed by its scopes.
- Authenticate agent/admin clients and verify permitted operations plus denied
  cross-role and cross-customer operations.
- Authenticate ChatGPT/Codex MCP and prove the same token/principal reaches gRPC.
- Enumerate every registered RPC: public policy is exact and every protected
  method has scope/RBAC coverage.
- Reject missing, malformed, expired, future, wrong issuer/audience/algorithm,
  disallowed client, insufficient-scope, revoked-session, blocked-user, and old
  CEERAT HS256 tokens.
- Verify refresh and logout/revocation for direct gRPC and MCP without inferring
  server-session state from access-token expiry.
- Verify deployment skew fails closed and no write is blindly retried.

This entire automated acceptance runs locally first. All failures are fixed and
the full local suite rerun before commits are pushed for Render deployment.
Render/ChatGPT testing is a distinct post-push confirmation, never the defect
discovery baseline.

## Cleanup

- Remove superseded internal end-user JWT encode/decode and gateway exchange
  code in the coordinated cutover. Do not retain a compatibility mode.
- Remove obsolete `JWT_SECRET` and gateway workload-secret wiring used only for
  end-user exchange. Retain separately justified workload authentication.
- Remove superseded public password/login/token-validation RPCs from the canonical
  contract in a coordinated new-system cutover; reserve removed protobuf fields
  and method identifiers where applicable. Do not retain aliases or stubs as a
  compatibility API.
- Keep Keycloak account registration, login, recovery, verification, MFA, and
  password lifecycle authoritative.
- Confirm repository, runtime, Render, and local environment documentation no
  longer instructs clients to obtain a CEERAT internal JWT.

## Human acceptance

1. Direct gRPC PKCE login succeeds and a protected profile/product/order read
   returns the authenticated user's data.
2. ChatGPT/Codex connects through MCP and performs the equivalent reads.
3. Server evidence shows the same issuer/subject/client/scope semantics and a
   continuous request/trace chain, with no raw credential.
4. Refresh continues access; logout/revocation requires reauthorization.
5. A captured superseded internal CEERAT test JWT is rejected by protected gRPC.

## Required evidence

Record contract/service/gateway/infra commit tuple, deployed versions, OAuth
client IDs (never secrets), scope matrix hash, test counts, sanitized request
and trace IDs, PASS/FAIL outcomes, and rollback result. Do not store tokens,
codes, PKCE verifiers, session cookies, passwords, or PII.

## Gates

```text
make verify-platform
make db-verify
make verify-grpc-oauth
make verify-phase1-live
make verify-phase2-live
ceerat-builder rbac check --output json
ceerat-builder check sql --output json
ceerat-builder check apps --output json
ceerat-builder check drift --output json
```

## Out of scope

All browser apps, the legacy agent service, REST, WebSocket product work,
preference feature implementation, social-login UX, and unrelated domains.

## Documentation after PR

Update platform, service, contract, gateway, infrastructure, OAuth, security,
logging, API-testing, incident, and deployment documentation. Only after human
acceptance, update the platform-builder architecture/security/service standards
to make Keycloak OAuth -> gRPC scope -> RBAC -> ownership the reusable rule.
