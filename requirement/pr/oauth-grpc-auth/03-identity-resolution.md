# PR 03: Verified OAuth identity resolution and account authority

Repository: `services-repo`  
Depends on: PR 02

## Objective

Map a cryptographically verified Keycloak `(issuer, subject)` to the current
CEERAT user/customer without accepting identity from request payloads or minting
a second end-user token.

## Work

- Add a service adapter that accepts only the shared verified OAuth principal.
- Resolve the existing external identity mapping transactionally; on approved
  first login, JIT-provision the CEERAT user/customer using verified claims.
- Require verified email for automatic provisioning and handle concurrent first
  calls idempotently through the existing unique issuer/subject boundary.
- Reload current CEERAT role/status from PostgreSQL on authorization; token
  claims may not override a blocked/deactivated account or stored RBAC role.
- Define safe behavior for changed email/name, duplicate email, missing customer
  mapping, and subject/client changes. Never merge accounts by unverified email.
- Stop returning or persisting Keycloak access/refresh tokens.
- Determine whether the local password column can be made nullable or removed.
  If changed, add a new migration, rollback/preflight, and disposable lifecycle
  test; never rewrite an applied migration.
- Keep the resolver dormant until PR 04; do not add a second active validator.

## Tests

- existing identity, approved first login, concurrent first login;
- same subject across different issuers, same email across different subjects;
- missing/unverified email and disallowed client;
- blocked/inactive/deleted current CEERAT user;
- customer ownership derivation and no request-controlled identity;
- database error sanitization and absence of token storage.

## Gates

```text
go test -race ./user/... ./customers/...
CEERAT_TEST_DATABASE_URL="$CEERAT_TEST_DATABASE_URL" go test ./...
make db-verify
ceerat-builder check sql --output json
ceerat-builder check drift --output json
```

Before push, exercise identity resolution with a real local-Keycloak token and
disposable local PostgreSQL identities. The resolver remains dormant in the
production path until the coordinated cutover.

## Out of scope

OAuth interceptor activation, gateway changes, UI compatibility, account-linking
UX, social-provider configuration, and generic identity-provider abstraction.

## Documentation after PR

Update service architecture, gRPC security, database/migration, privacy, and
identity lifecycle documentation and service inventory.
